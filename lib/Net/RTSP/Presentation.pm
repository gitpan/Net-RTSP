package Net::RTSP::Presentation;

use 5.005;
use strict;
use warnings;
use vars '@ISA';
use URI;
use RTSP::Error;
use RTSP::URI 'make_uri_absolute';
use RTSP::Utility qw(get_named_params invoke_callback size_in_bytes);
use Net::RTSP::Socket;

# states for the presentation:
use constant UNINITIALIZED      => 0;
use constant INITIALIZING       => 1;
use constant INITIALIZED        => 2;
use constant SENDING_REQUEST    => 3; # client -> server
use constant RECEIVING_RESPONSE => 4; # client <- server
use constant RECEIVING_REQUEST  => 5; # server -> client
use constant SENDING_RESPONSE   => 6; # server <- client


use constant DEFAULT_ACCEPT => 'application/sdp, application/rtsl, ' .
                               'application/mheg';

# we use smaller, more reasonable read sizes for the request/status line and
# message header, since the default buffer size of 4096 is a little too large:
use constant START_LINE_READ_SIZE => 128;
use constant HEADER_READ_SIZE     => 1024;

push(@ISA, qw(RTSP::Error));






sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	# the Net::RTSP object passed on to us:
	my $rtsp = shift;

	# the hopefully full URI of the presentation:
	my $presentation_uri = make_uri_absolute(shift);

	my ($success_callback, $failure_callback, $server_request_callback,
	    $timeout, $buffer_size, $pipelining);
	get_named_params({
		SuccessCallback       => \$success_callback,
		FailureCallback       => \$failure_callback,
		ServerRequestCallback => \$server_request_callback,
		Timeout               => \$timeout,
		BufferSize            => \$buffer_size,
		Pipelining            => \$pipelining
		}, \@_
	);

	# default to the Net::RTSP object's master settings:
	$timeout     ||= $rtsp->timeout;
	$buffer_size ||= $rtsp->buffer_size;



	my $uri = new URI $presentation_uri;

	# are we going to communicate over TCP/IP or UDP/IP?
	my $transport_protocol =
		($uri->scheme eq 'rtspu') ? 'UDP/IP' : 'TCP/IP';

	# the socket to use for this presentation:
	my $socket = new Net::RTSP::Socket $transport_protocol;

	# our Net::RTSP::Presentation object:
	my $self = {
		# the state of the presentation:
		state                    => UNINITIALIZED,

		# the Net::RTSP object:
		rtsp                     => $rtsp,

		# the Net::RTSP::Socket object:
		'socket'                 => $socket,

		# the absolute URI of the presentation:
		uri                      => $presentation_uri,

		# the transport protocol to be used:
		transport_protocol       => $transport_protocol,

		# the name of the host to connect to:
		host                     => $uri->host,

		# the port to connect at:
		port                     => $uri->port,

		# the sequence number to use for the next request dispatched:
		cseq                     => 1,

		# the callback to invoke if the socket and its transport
		# protocol can be successfully initialized:
		success_callback         => $success_callback,

		# the callback to invoke if the socket and its transport
		# protocol can't be successfully initialized:
		failure_callback         => $failure_callback,

		# the callback to invoke to process incoming requests:
		server_request_callback  => $server_request_callback,

		# the number of seconds to timeout after:
		timeout                  => $timeout,

		# the size to use when reading from the socket:
		buffer_size              => $buffer_size,

		# is RTSP request pipelining enabled?
		pipelining               => $pipelining ? 1 : 0,

		# the queue of pending request objects to dispatch (used with
		# the event-driven interface):
		_pending_requests        => [],

		# the list of pending responses to dispatch to the server (used
		# with the event-driven interface):
		_pending_responses       => [],

		# The list of active requests. Requests get shifted out of the
		# above list and pushed into this one:
		_active_requests         => [],

		# the buffer used to process the incoming request/status line:
		_incoming_start_line     => '',

		# the offset within _incoming_start_line of where to store the
		# next bytes read from the socket:
		_start_line_offset       => 0,

		# was the request/status line received yet?
		_received_start_line     => 0,

		# the buffer used to process the incoming message header:
		_incoming_message_header => '',

		# the offset within _incoming_message_header of where to store
		# the next bytes read from the socket:
		_message_header_offset   => 0,

		# was the header received yet?
		_received_message_header => 0,

		# the offset within either _incoming_request->body or
		# _incoming_response->content:
		_message_body_offset     => 0,

		# the number of bytes read so far for the request body/response
		# content (checked against the value in the Content-Length
		# header):
		_message_body_bytes_read => 0,

		# was the message body received yet?
		_received_message_body   => 0,

		# if the incoming message is a request message, this stores the
		# RTSP::Request object for it:
		_incoming_request        => undef,

		# if the incoming message is a response message, this stores
		# the RTSP::Response object for it:
		_incoming_response       => undef
	};

	bless($self, $class);

	if ($self->rtsp->is_event_driven)
	{
		# add the socket to the list of pending sockets and register
		# callback to try to connect/initialize the socket as soon as
		# it becomes connectable:
		$self->rtsp->add_socket($self->socket);

		$self->socket->register_connectable_callback(
			sub { $self->_non_blocking_initialization }
		);

		return $self;
	}
	else
	{
		# otherwise, we'll just do blocking initialization right away:
		return $self->_blocking_initialization;
	}
}





sub describe
{
	my $self = shift;

	my $request = new RTSP::Request (DESCRIBE => @_);

	$request->uri($self->uri) if ($request->uri eq '*');
	$request->set_header(
		Name   => 'Accept',
		Accept => DEFAULT_ACCEPT
	) unless $request->is_header_set('Accept');

	return $self->send_request($request);
}





sub announce
{
	my $self = shift;

	return $self->send_request(
		new RTSP::Request (ANNOUNCE => @_)
	);
}





sub options
{
	my $self = shift;

	return $self->send_request(
		new RTSP::Request (OPTIONS => @_)
	);
}





sub setup_session
{
	my $self = shift;

	my $request = new RTSP::Request (SETUP => @_);
	my $uri     = $request->uri || $self->uri;

	my $session = new Net::RTSP::Session ($self, $uri);
	if ($self->presentation->is_event_driven)
	{
		$request->session_success_callback(sub {
			my $response = shift;

			my $session_id = $response->get_header('Session');

			$session->id($session_id);
			$session->ready;
		});

		$self->send_request($request);
	}
	else
	{
		my $response = $self->send_request($request);

		if ($response)
		{
			my $session_id = $response->get_header('Session');

			$session->id($session_id);
			$session->ready;
		}

		return $response;
	}
}





sub get_parameter
{
	my $self = shift;

	return $self->send_request(
		new RTSP::Request (GET_PARAMETER => @_)
	);
}





sub set_parameter
{
	my $self = shift;

	return $self->send_request(
		new RTSP::Request (SET_PARAMETER => @_)
	);
}





sub send_request
{
	my ($self, $request) = @_;

	if ($self->rtsp->is_event_driven)
	{
		push(@{ $self->{_pending_requests} }, $request);
	}
	else
	{
		# send the request:
		$self->_dispatch_request($request) or return;

		# check if retransmission is needed:
		if ($self->transport_protocol eq 'UDP/IP')
		{
			my $fd = fileno $self->socket->handle;
			my $readable_mask = '';

			vec($readable_mask, $fd, 1) = 1;
			my $ready = select(
				$readable_mask, undef, undef, $self->timeout
			);

			unless ($ready)
			{
				$self->_dispatch_request($request) or return;
			}
		}



		# this stores the resulting response object:
		my $response;

		# get the status line:
		while (1)
		{
			$self->_read_start_line or return;

			if ($self->_received_start_line)
			{
				return $self->raise_error(
					'A message other than an RTSP ' .
					'response was received from the server.'
				) if ($self->_incoming_request
					or not $self->_incoming_response);

				$response = $self->_incoming_response;

				last;
			}
		}

		# get the response header:
		while (1)
		{
			$self->_read_message_header or return;

			last if $self->_received_message_header;
		}

		# now get the response body:
		while (1)
		{
			$self->_read_message_body or return;

			last if $self->_received_message_body;
		}

		$self->_clear_incoming_message;

		return $response;
	}
}





sub send_response
{
	my ($self, $response) = @_;

	if ($self->rtsp->is_event_driven)
	{
		push(@{ $self->{_pending_responses} }, $response);
	}
	else
	{
		$self->_dispatch_response($response) or return;
	}

	return 1;
}





sub state
{
	my $self = shift;

	$self->{state} = shift if @_;

	return $self->{state};
}





sub rtsp
{
	my $self = shift;

	$self->{rtsp} = shift if @_;

	return $self->{rtsp};
}





sub socket
{
	my $self = shift;

	$self->{'socket'} = shift if @_;

	return $self->{'socket'};
}





sub uri
{
	my $self = shift;

	$self->{uri} = shift if @_;

	return $self->{uri};
}





sub transport_protocol
{
	my $self = shift;

	$self->{transport_protocol} = shift if @_;

	return $self->{transport_protocol};
}





sub host
{
	my $self = shift;

	$self->{host} = shift if @_;

	return $self->{host};
}





sub port
{
	my $self = shift;

	$self->{port} = shift if @_;

	return $self->{port};
}





sub cseq
{
	my $self = shift;

	$self->{cseq} = shift if @_;

	return $self->{cseq};
}





sub success_callback
{
	my $self = shift;

	$self->{success_callback} = shift if @_;

	return $self->{success_callback};
}





sub failure_callback
{
	my $self = shift;

	$self->{failure_callback} = shift if @_;

	return $self->{failure_callback};
}





sub timeout
{
	my $self = shift;

	$self->{timeout} = shift if @_;

	return $self->{timeout};
}





sub buffer_size
{
	my $self = shift;

	$self->{buffer_size} = shift if @_;

	return $self->{buffer_size};
}





sub pipelining
{
	my $self = shift;

	$self->{pipelining} = shift if @_;

	return $self->{pipelining};
}





sub succeed
{
	my $self = shift;

	invoke_callback($self->success_callback, $self);
}





sub fail
{
	my $self = shift;

	invoke_callback($self->failure_callback, $self->error, $self);
}





sub terminate
{
	my $self = shift;

	return if ($self->state == UNINITIALIZED);

	$self->socket->disconnect;
	$self->rtsp->remove_socket($self->socket);
	$self->state(UNINITIALIZED);
}





sub _non_blocking_initialization
{
	my $self = shift;

	$self->state(INITIALIZING);
	$self->socket->non_blocking_connect(
		$self->host,
		$self->port,
		$self->timeout,
		sub {
			$self->state(INITIALIZED);
			$self->succeed;
			$self->socket->register_writable_callback(
				sub { $self->_dispatch_pending_messages }
			);
			$self->socket->register_readable_callback(
				sub { $self->_process_incoming_message }
			);
		},
		sub {
			$self->state(UNINITIALIZED);
			$self->raise_error(
				sprintf("Couldn't initialize socket: %s.",
					$self->socket->network_error
				)
			);
			$self->fail;
		}
	);
}





sub _blocking_initialization
{
	my $self = shift;

	$self->state(INITIALIZING);

	my $initialized = $self->socket->blocking_connect(
		$self->host,
		$self->port,
		$self->timeout
	);

	if ($initialized)
	{
		$self->state(INITIALIZED);

		return $self;
	}
	else
	{
		$self->state(UNINITIALIZED);

		return $self->raise_error(
			sprintf("Couldn't initialize socket: %s.",
				$self->socket->network_error
			)
		);
	}
}





sub _dispatch_pending_messages
{
	my $self = shift;

	return unless ($self->state == INITIALIZED);

	# check for any outstanding responses to send to the server:
	if ($self->_pending_responses)
	{
		my $response = shift @{ $self->{_pending_responses} };

		$self->_dispatch_response($response);
	}

	# check for timeouts in any active request/response cycles:
	foreach my $request (@{ $self->{_active_requests} })
	{
		# check for needed retransmission of a request if it
		# hasn't been acknowledged after a considerable amount
		# of time:
		if (!$request->acknowledged
			and $self->transport_protocol eq 'UDP/IP')
		{
			my $elapsed_time = time - $request->_time_sent;
			if ($self->_max_round_trip_time > $elapsed_time)
			{
				$self->_dispatch_request($request);
				next;
			}
		}

		
	}

	# send a pending request, or every pending request if pipelining is
	# turned on:
	if ($self->_pending_requests)
	{
		if ($self->pipelining)
		{
			my @requests;
			while (my $request =
				shift @{ $self->{_pending_requests} })
			{
				push(@requests, $request);
			}
			
			$self->_dispatch_requests(@requests);
		}
		else
		{
			my $request = shift @{ $self->{_pending_requests} };

			$self->_dispatch_request($request);
		}
	}
}





sub _dispatch_request
{
	my ($self, $request) = @_;

	$self->state(SENDING_REQUEST);

	$self->_prepare_request($request);

	my $bytes_written = $self->_write_to_socket($request->as_string);
	unless ($bytes_written)
	{
		my $failed_request = shift @{ $self->{_active_requests} };

		$self->raise_error(
			sprintf("Couldn't send request: %s.",
				$self->socket->network_error
			)
		);

		$failed_request->fail($self) if $self->rtsp->is_event_driven;

		return;
	}

	$self->state(RECEIVING_RESPONSE);

	return 1;
}





sub _dispatch_requests
{
	my ($self, @requests) = @_;

	$self->state(SENDING_REQUEST);

	my $requests_to_dispatch = '';
	foreach my $request (@requests)
	{
		$self->_prepare_request($request);

		$requests_to_dispatch .= $request->as_string;
	}

	my $bytes_written = $self->_write_to_socket($requests_to_dispatch);
	unless ($bytes_written)
	{
		$self->raise_error(
			sprintf("Couldn't send %d piplined requests to " .
			        "server: %s.",
				scalar @requests,
				$self->socket->network_error
			)
		);

		# they all failed, all of them, not a single one can be used:
		while (my $failed_request = shift @{$self->{_active_requests}})
		{
			$failed_request->fail($self)
				if $self->rtsp->is_event_driven;
		}

		return;
	}

	$self->state(RECEIVING_RESPONSE);
}





sub _dispatch_response
{
	my ($self, $response) = shift;

	$self->state(SENDING_RESPONSE);

	$self->_prepare_response($response);

	my $bytes_written = $self->_write_to_socket($response->as_string);
	unless ($bytes_written)
	{
		$self->raise_error(
			sprintf("Couldn't send response to server: %s.",
				$self->socket->network_error
			)
		);

		$response->fail($self) if $self->rtsp->is_event_driven;

		return;
	}

	$response->succeed($self) if $self->rtsp->is_event_driven;

	return $bytes_written;
}





sub _prepare_request
{
	my ($self, $request) = @_;

	# the sequence number to use for this request:
	$self->_set_sequence_number($request);

	# increment it for the next request:
	$self->{cseq}++;

	# add it to the list of active requests:
	push(@{ $self->{_active_requests} }, $request);

}





sub _prepare_response
{
	my ($self, $response) = @_;

	# the sequence number to use for this response:
	$self->_set_sequence_number($response);
}





sub _process_incoming_message
{
	my $self = shift;

	my $done;
	if ($self->_received_start_line)
	{
		if ($self->_received_message_header)
		{
			$self->_read_message_body or return;

			if ($self->_received_message_body)
			{
				if ($self->state == RECEIVING_RESPONSE)
				{
					my $request =
					shift @{ $self->{_active_requests} };
					
					$request->succeed(
						$self->_incoming_response,
						$self
					) if $self->rtsp->is_event_driven;

					$self->state(INITIALIZED)
						unless $self->_active_requests;

					my $response =
						$self->_incoming_response;

					$self->_clear_incoming_message;

					return $response;
				}
				elsif ($self->state == RECEIVING_REQUEST)
				{
					# increment the sequence number for the
					# next request we might send:
					$self->{cseq}++;

					invoke_callback(
						$self->server_request_callback,
						$self->_incoming_request
					);

					$self->_clear_incoming_message;
				}
			}
		}
		else
		{
			$self->_read_message_header or return;
		}
	}
	else
	{
		$self->_read_start_line or return;
	}
}





sub _set_sequence_number
{
	my ($self, $request) = @_;

	my $cseq;
	if ($request->is_header_set('CSeq'))
	{
		$cseq = $request->get_header('CSeq');
	}
	else
	{
		$cseq = $self->cseq;

		# and set the CSeq header for it:
		$request->set_header(
			Name  => 'CSeq',
			Value => $cseq
		);
	}

	return $cseq;
}





sub _read_start_line
{
	my $self = shift;

	my $bytes_read = $self->_read_from_socket(
		\$self->{_incoming_start_line},
		START_LINE_READ_SIZE,
		$self->_start_line_offset
	);

	unless ($bytes_read)
	{
		if (defined $bytes_read)
		{
			$self->raise_error(
				'The server closed the connection before ' .
				'sending the status/request line.'
			);
		}
		else
		{
			$self->raise_error(
				sprintf("Couldn't read the status/request " .
				        "line of the server's message: %s." .
					$self->socket->network_error
				)
			);
		}

		if ($self->state == RECEIVING_RESPONSE)
		{
			my $failed_request = shift @{$self->{_active_requests}};

			$failed_request->fail($self)
				if $self->rtsp->is_event_driven;
		}

		return;
	}

	$self->{_start_line_offset} += $bytes_read;

	if (index($self->_incoming_start_line, "\015\012"))
	{
		my ($line, $remainder) =
			split(/\015\012/, $self->_incoming_start_line, 2);

		# put back the rest:
		$self->socket->unread($remainder);

		my (@tokens) = split(/ /, $line, 3);
		my $version_pattern = qr/^RTSP\/(\d+\.\d+)$/;
		if ($tokens[0] =~ /$version_pattern/)
		{
			my $response = new RTSP::Response (
				Version     => $1,
				Code        => $tokens[1],
				Description => $tokens[2]
			);

			$self->_incoming_response($response);
		}
		elsif ($tokens[2] =~ /$version_pattern/)
		{
			my $request = new RTSP::Request ($tokens[0],
				URI     => $tokens[1],
				Version => $1
			);

			$self->_incoming_request($request);
			$self->state(RECEIVING_REQUEST);
		}
		else
		{
			$self->raise_error(
				'A malformed message was sent; ignoring.'
			);

			if ($self->state == RECEIVING_RESPONSE)
			{
				my $failed_request =
					shift @{$self->{_active_requests}};

				$failed_request->fail($self)
					if $self->rtsp->is_event_driven;
			}
		}

		$self->_received_start_line(1);
	}

	return 1;
}





sub _read_message_header
{
	my $self = shift;

	my $bytes_read = $self->_read_from_socket(
		\$self->{_incoming_message_header},
		HEADER_READ_SIZE,
		$self->_message_header_offset
	);

	unless (defined $bytes_read)
	{
		if ($self->state == RECEIVING_RESPONSE)
		{
			my $failed_request = shift @{$self->{_active_requests}};

			$self->raise_error(
				"The response header could not be read. %s.",
				$self->socket->network_error
			);

			$failed_request->fail($self)
				if $self->rtsp->is_event_driven;
		}
		elsif ($self->state == RECEIVING_REQUEST)
		{
			$self->raise_error(
				"The request header could not be read. %s.",
				$self->socket->network_error
			);
		}

		return;
	}

	$self->{_message_header_offset} += $bytes_read;

	# check for completed header "Name: value" pairs:
	while ($self->_incoming_message_header =~ /\015\012[^ \t]/)
	{
		# headers usually take up a single CRLF temrinated line:
		my ($header, $remainder) =
			split(/\015\012/, $self->{_incoming_message_header}, 2);

		# Headers can be continued over multiple lines by starting
		# subsiquint lines with a linear white space. So we see if the
		# remainder after CRLF is a space, and continue the header if
		# it is. (This is called "unfolding" a "folded" header.)
		my $line;
		while ($remainder =~ /^[ \t]/)
		{
			($line, $remainder) = split(/\015\012/, $remainder, 2);

			$header .= $line;
		}

		my ($name, $value) = $header =~ /(\S+):\s?(.*)/;
		if ($self->state == RECEIVING_RESPONSE)
		{
			$self->_incoming_response->set_header(
				Name  => $name,
				Value => $value
			);
		}
		elsif ($self->state == RECEIVING_REQUEST)
		{
			$self->_incoming_request->set_header(
				Name  => $name,
				Value => $value
			);
		}

		if (substr($remainder, 0, 2) eq "\015\012")
		{
			# put the rest back onto the socket, we're not ready
			# for it yet:
			$self->socket->unread(substr($remainder, 2));

			# but we are done:
			$self->_received_message_header(1);

			last;
		}
		else
		{
			# put back the header, minus the one we just parsed:
			$self->_incoming_message_header($remainder);
			$self->_message_header_offset(
				size_in_bytes($remainder)
			);
		}
	}

	return 1;
}





sub _read_message_body
{
	my $self = shift;

	my $destination;
	my $content_length;
	if ($self->state == RECEIVING_RESPONSE)
	{
		$destination    = $self->_incoming_response->content_ref;
		$content_length = $self->_incoming_response->get_header(
			'Content-Length'
		);
	}
	elsif ($self->state == RECEIVING_REQUEST)
	{
		$destination    = $self->_incoming_request->body_ref;
		$content_length = $self->_incoming_request->get_header(
			'Content-Length'
		);
	}

	unless ($content_length)
	{
		$self->_received_message_body(1);
		return 1;
	}

	# this bit of logic ensures we don't read any part of the next response
	# message:
	my $bytes_left    = $content_length - $self->_message_body_bytes_read;
	my $bytes_to_read = ($bytes_left > $self->buffer_size)
				? $self->buffer_size
				: $bytes_left;

	my $bytes_read = $self->_read_from_socket(
		$destination, $bytes_to_read, $self->_message_body_offset
	);
	unless (defined $bytes_read)
	{
		if ($self->state == RECEIVING_RESPONSE)
		{
			my $failed_request = shift @{$self->{active_requests}};

			$self->raise_error(
				sprintf("Couldn't read response content from " .
				        "server. %s.",
					$self->socket->network_error
				)
			);

			$failed_request->fail($self)
				if $self->rtsp->is_event_driven;
		}
		elsif ($self->state == RECEIVING_REQUEST)
		{
			$self->raise_error(
				sprintf("Couldn't read request body from " .
				        "server. %s.",
					$self->socket->network_error
				)
			);
		}

		$self->state(INITIALIZED);

		return;
	}

	$self->{_message_body_bytes_read} += $bytes_read;
	$self->{_message_body_offset}     += $bytes_read;

	$self->_received_message_body(1)
		if ($self->_message_body_bytes_read >= $content_length);

	return 1;
}





sub _pending_requests
{
	my $self = shift;

	@{ $self->{_pending_requests} } = @_ if @_;

	return @{ $self->{_pending_requests} };
}





sub _pending_responses
{
	my $self = shift;

	@{ $self->{_pending_responses} } = @_ if @_;

	return @{ $self->{_pending_responses} };
}





sub _incoming_start_line
{
	my $self = shift;

	$self->{_incoming_start_line} = shift if @_;

	return $self->{_incoming_start_line};
}





sub _start_line_offset
{
	my $self = shift;

	$self->{_start_line_offset} = shift if @_;

	return $self->{_start_line_offset};
}





sub _received_start_line
{
	my $self = shift;

	$self->{_received_start_line} = shift if @_;

	return $self->{_received_start_line};
}





sub _incoming_message_header
{
	my $self = shift;

	$self->{_incoming_message_header} = shift if @_;

	return $self->{_incoming_message_header};
}





sub _message_header_offset
{
	my $self = shift;

	$self->{_message_header_offset} = shift if @_;

	return $self->{_message_header_offset};
}





sub _received_message_header
{
	my $self = shift;

	$self->{_received_message_header} = shift if @_;

	return $self->{_received_message_header};
}





sub _message_body_bytes_read
{
	my $self = shift;

	$self->{_message_body_bytes_read} = shift if @_;

	return $self->{_message_body_bytes_read};
}





sub _message_body_offset
{
	my $self = shift;

	$self->{_message_body_offset} = shift if @_;

	return $self->{_message_body_offset};
}





sub _received_message_body
{
	my $self = shift;

	$self->{_received_message_body} = shift if @_;

	return $self->{_received_message_body};
}





sub _incoming_response
{
	my $self = shift;

	$self->{_incoming_response} = shift if @_;

	return $self->{_incoming_response};
}





sub _incoming_request
{
	my $self = shift;

	$self->{_incoming_request} = shift if @_;

	return $self->{_incoming_request};
}





sub _clear_incoming_message
{
	my $self = shift;

	$self->_incoming_start_line(undef);
	$self->_start_line_offset(0);
	$self->_received_start_line(0);

	$self->_incoming_message_header(undef);
	$self->_message_header_offset(0);
	$self->_received_message_header(0);

	$self->_message_body_bytes_read(0);
	$self->_message_body_offset(0);
	$self->_received_message_body(0);

	$self->_incoming_request(undef);
	$self->_incoming_response(undef);
}





sub _write_to_socket
{
	my ($self, $bytes_to_write) = @_;

	my $bytes_written;
	if ($self->rtsp->is_event_driven)
	{
		$bytes_written = $self->socket->non_blocking_write(
			$bytes_to_write,
			size_in_bytes($bytes_to_write)
		);
	}
	else
	{
		$bytes_written = $self->socket->blocking_write(
			$bytes_to_write,
			size_in_bytes($bytes_to_write),
			$self->timeout
		);
	}

	return $bytes_written;
}





sub _read_from_socket
{
	my ($self, $read_buffer_ref, $read_size, $offset) = @_;

	my $bytes_read;
	if ($self->rtsp->is_event_driven)
	{
		$bytes_read = $self->socket->non_blocking_read(
			$read_buffer_ref,
			$read_size,
			$offset
		);
	}
	else
	{
		$bytes_read = $self->socket->blocking_read(
			$read_buffer_ref,
			$read_size,
			$offset,
			$self->timeout
		);
	}

	return $bytes_read;
}

1;
