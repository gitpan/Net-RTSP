# This class encapsulates IO::Socket::INET objects for both TCP/IP sockets as
# well as UDP/IP sockets.

package Net::RTSP::Socket;

use 5.005;
use strict;
use warnings;
use base 'Exporter';
use vars qw(@EXPORT @ISA);

use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use Socket qw(AF_INET SOCK_STREAM SOCK_DGRAM inet_aton sockaddr_in);
use Symbol 'gensym';
use RTSP::Error;
use RTSP::Utility qw(
	invoke_callback size_in_bytes get_os_name remove_package_prefix
);

# default values if no others are supplied:
use constant DEFAULT_TIMEOUT   => 60;
use constant DEFAULT_READ_SIZE => 4096;

# the states for the socket:
use constant DISCONNECTED => 0;
use constant CONNECTABLE  => 1;
use constant CONNECTING   => 2;
use constant CONNECTED    => 3;
use constant READABLE     => 5;
use constant READING      => 6;
use constant WRITABLE     => 7;
use constant WRITING      => 8;

# this constant is only used for ioctl() on Windows:
use constant FIONBIO => 0x8004667e;

# this is used to quickly lookup the protocol numbers by socket type:
use vars '@PROTOCOLS';
$PROTOCOLS[SOCK_STREAM] = getprotobyname 'tcp',
$PROTOCOLS[SOCK_DGRAM]  = getprotobyname 'udp';

# we export the state constants so the the socket state can be checked and set
# if needed:
@EXPORT = qw(
	DISCONNECTED
	CONNECTABLE
	CONNECTING
	CONNECTED
	READABLE
	READING
	WRITABLE
	WRITING
);

push(@ISA, 'RTSP::Error');





# thanks to Benjamin Goldberg for this hack to get the EINPROGRESS and
# EWOULDBLOCK constants even on Windows (in addition to EINTR, which should be
# available everywhere):
BEGIN
{
	if (get_os_name() =~ /^MSWin/i)
	{
		require Errno;
		import  Errno qw(EINTR EAGAIN);

		*EWOULDBLOCK = sub () { 10035 };
		*EINPROGRESS = sub () { 10036 };
 	}
	else
	{
		require Errno;
		import  Errno qw(EINTR EAGAIN EWOULDBLOCK EINPROGRESS);
	}
}








################################################################################
#
# 	Method
# 		new($socket_type)
#
# 	Purpose
# 		This is the constructor method. It creates a new
# 		Net::RTSP::Socket object for a TCP/IP socket or a UDP/IP
# 		socket and returns a reference to it.
#
# 	Parameters
# 		$socket_type - A string containing the socket type: either
# 		               "TCP/IP" or "UDP/IP".
#

sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	# determine what type of socket to create:
	my $type = (shift =~ m|^UDP(?:/IP)?$|i)
			? SOCK_DGRAM
			: SOCK_STREAM;

	# create the socket:
	my $socket = gensym;
	socket($socket, AF_INET, $type, $PROTOCOLS[$type]);



	my $self = {
		# the current state of the socket:
		state                      => DISCONNECTED,

		# this stores a reference to the socket file handle:
		handle                     => $socket,

		# the hostname:
		host                       => undef,

		# the port number:
		port                       => undef,

		# this stores the type of socket this object encapsulates,
		# either a stream (TCP/IP) or datagram (UDP/IP) socket, using
		# the constants from Socket.pm:
		type                       => $type,

		# The time() of when the socket was last active. This is used
		# to time out a connect() and other operations:
		last_active                => 0,

		# the number of seconds to time a connect out afterwards:
		connect_timeout            => 0,

		# place store data the user "unreads" back into the socket if
		# they aren't ready for it yet:
		unread_buffer              => '',

		# this stores a string containing the last network error that
		# occurred:
		network_error              => undef,

		# the sub to call when the socket is connectable, when its
		# removed from the pending sockets queue:
		connectable_callback       => undef,

		# the sub to call if the socket gets connected successfully:
		connect_success_callback   => undef,

		# the sub to call if the socket doesn't get connected
		# successfully:
		connect_failure_callback   => undef,

		# the sub to call when the socket becomes writable:
		writable_callback          => undef,

		# the sub to call when the socket becomes readable:
		readable_callback          => undef,

		# the sub to call when a network error occurs:
		network_error_callback     => undef,
	};

	bless($self, $class);

	return $self;
}





################################################################################
#
# 	Method
# 		register_connectable_callback($callback)
#
# 	Purpose
# 		This method is used to register a callback for the connectable
# 		state. When the socket becomes connectable, the callback will
# 		be executed.
#
# 	Parameters
# 		$callback - (Optional.) A reference to a subroutine to execute
# 		            when the socket becomes connectable.
#

sub register_connectable_callback
{
	my ($self, $callback) = @_;

	$self->{connectable_callback} = $callback;
}





################################################################################
#
# 	Method
# 		register_writable_callback($callback)
#
# 	Purpose
# 		This method is used to register a callback for the writable
# 		state. When the socket becomes writable, the callback will
# 		be executed.
#
# 	Parameters
# 		$callback - (Optional.) A reference to a subroutine to execute
# 		            when the socket becomes writable.
#

sub register_writable_callback
{
	my ($self, $callback) = @_;

	$self->{writable_callback} = $callback;
}





################################################################################
#
# 	Method
# 		register_readable_callback($callback)
#
# 	Purpose
# 		This method is used to register a callback for the readable
# 		state. When the socket becomes readable, the callback will be
# 		executed.
#
# 	Parameters
# 		$callback - (Optional.) A reference to a subroutine to execute
# 		            when the socket becomes readable.
#

sub register_readable_callback
{
	my ($self, $callback) = @_;

	$self->{readable_callback} = $callback;
}





################################################################################
#
# 	Method
# 		register_network_error_callback($callback)
#
# 	Purpose
# 		This method is used to register a callback for the network
# 		errors. When ever a network error occurs, the callback will be
# 		executed with the error message sent as its argument.
#
# 	Parameters
# 		$callback - (Optional.) A reference to a subroutine to execute
# 		            whenever network errors occur.
#

sub register_network_error_callback
{
	my ($self, $callback) = @_;

	$self->{network_error_callback} = $callback;
}





################################################################################
#
# 	Method
# 		connectable_state()
#
# 	Purpose
# 		This method makes the socket connectable. It invokes the
# 		"connectable" callback set using the
# 		register_connectable_callback() method.
#
# 	Parameters
# 		None.
#

sub connectable_state
{
	my $self = shift;

	$self->state(CONNECTABLE);

	invoke_callback($self->{connectable_callback}, $self);
}





################################################################################
#
# 	Method
# 		non_blocking_connect(
# 			$host,
# 			$port
# 			[, $timeout, $success_callback, $failure_callback]
# 		)
#
# 	Purpose
# 		Once the socket is in its connectable state, this method can be
# 		used to establish a TCP/IP connection or perform the necessary
# 		initialization for UDP/IP, asynchronously. It allows you to
# 		set a callback to be invoked if the socket is successfully
# 		connected and a callback to be invoked if it cannot be
# 		successfully connected.
#
# 	Parameters
# 		$host             - The host to connect to.
# 		$port             - The port to connect at.
# 		$timeout          - (Optional.) The number of seconds to give
# 		                    up (timeout) after (defaults to 60
# 		                    seconds).
# 		$success_callback - (Optional.) The callback to invoke if the
# 		                    socket can be connected.
# 		$failure_callback - (Optional.) The callback to invoke if the
# 		                    socket cannot be connected.
#

sub non_blocking_connect
{
	my ($self, $host, $port, $timeout,
	    $success_callback, $failure_callback) = @_;

	$self->_make_non_blocking
		or return invoke_callback($failure_callback, $self);

	$self->state(CONNECTING);

	$self->{connect_timeout}          = $timeout || DEFAULT_TIMEOUT;
	$self->{connect_failure_callback} = $failure_callback;
	$self->{connect_success_callback} = $success_callback;

	my $rc = $self->_connect($host, $port);
	unless ($rc or $! == EINPROGRESS or $! == EWOULDBLOCK)
	{
		$self->state(DISCONNECTED);
		$self->network_error(
			"Couldn't connect to $host at port $port: $!"
		);

		return invoke_callback($failure_callback, $self);
	}

	$self->last_active(time);
}





################################################################################
#
# 	Method
# 		blocking_connect($host, $port [, $timeout])
#
# 	Purpose
# 		This method tries to connect a socket using blocking IO.
#
# 	Parameters
# 		$host    - The host to connect to.
# 		$port    - The port to connect at.
# 		$timeout - (Optional.) The number of seconds to timeout after
# 		           (defaults to 60 seconds).
#

sub blocking_connect
{
	my ($self, $host, $port, $timeout) = @_;

	$self->state(CONNECTING);

	my $rc = $self->_connect($host, $port);
	unless ($rc or $! == EINPROGRESS)
	{
		$self->state(DISCONNECTED);
		return $self->network_error(
			"Couldn't connect to $host at $port: $!"
		);
	}

	# now wait for it to become writable or timeout:
	my $write_mask = '';
	vec($write_mask, fileno $self->handle, 1) = 1;
	if (select(undef, $write_mask, undef, $timeout))
	{
		$self->state(CONNECTED);
		$self->_make_blocking;
	}
	else
	{
		$self->state(DISCONNECTED);
		$self->network_error('Connect timed out');
	}

	return 1;
}





################################################################################
#
# 	Method
# 		poll_non_blocking_connect()
#
# 	Purpose
# 		This method polls the non-blocking connect initiated by a call
# 		to the non_blocking_connect() method. If it determines that
# 		the socket was successfully connected, then it will invoke the
# 		success callback. If it determines that the socket couldn't be
# 		connected or if the time allowed for a connection attempt has
# 		been met or exceeded, then it invokes the failure callback.
#
# 	Parameters
# 		None.
#

sub poll_non_blocking_connect
{
	my $self = shift;

	if ($self->is_connected)
	{
		$self->state(CONNECTED);
		$self->_make_blocking;

		invoke_callback($self->{connect_success_callback}, $self);
	}
	elsif (time - $self->last_active > $self->{connect_timeout})
	{
		$self->state(DISCONNECTED);
		$self->network_error('Connect timed out');

		invoke_callback($self->{connect_failure_callback}, $self);
	}
}





################################################################################
#
# 	Method
# 		readable_state()
#
# 	Purpose
# 		This method makes sets the socket to its readable state. It
# 		invokes the readable callback set by the
# 		register_readable_callback() method.
#
# 	Parameters
# 		None.
#

sub readable_state
{
	my $self = shift;

	$self->state(READABLE);

	invoke_callback($self->{readable_callback}, $self);
}





################################################################################
#
# 	Method
# 		non_blocking_read($read_buffer_ref [, $read_size])
#
# 	Purpose
# 		This method attempts to do a non-blocking read of the socket.
# 		It tries to read $read_size bytes from the socket into the
# 		scalar referred to by $read_buffer_ref. It returns the number
# 		of bytes actually read; zero if the there are no more bytes
# 		to read or undef if some network error occurs (call
# 		network_error() to retrieve the error message).
#
# 	Parameters
# 		$read_buffer_ref - A reference to a scalar to store the bytes
# 		                   read from the socket in.
# 		$read_size       - (Optional.) The number of bytes to read
# 		                   (defaults to 4096).
# 		$offset          - (Optional.) The offset in $read_buffer_ref
# 		                   of where to put the bytes that are read.
#

sub non_blocking_read
{
	my $self = shift;

	# first, check for unread'ed data we can give them back instead of
	# having to go to the socket:
	if (size_in_bytes($self->{unread_buffer}))
	{
		return $self->_read_unreaded_data(@_);
	}

	return $self->_system_read(@_);
}





################################################################################
#
# 	Method
# 		blocking_read(
# 			$read_buffer_ref [, $read_size, $offset, $timeout]
# 		)
#
# 	Purpose
# 		This method attempts to do a blocking read of the socket.
#
# 		First, it blocks until the socket becomes readable or $timeout
# 		seconds pass and a timeout occurs. Then it tries to read
# 		$read_size bytes from the socket into the scalar referred to by
# 		$read_buffer_ref. It returns the number of bytes actually read;
# 		zero if the there are no more bytes to read or undef if some
# 		network error occurs (call network_error() to retrieve the error
# 		message).
#
# 	Parameters
# 		$read_buffer_ref - A reference to a scalar to store the bytes
# 		                   read from the socket in.
# 		$read_size       - (Optional.) The number of bytes to read
# 		                   (defaults to 4096).
# 		$offset          - (Optional.) Offset in $read_buffer_ref of
# 		                   where to put the bytes that are read.
# 		$timeout         - (Optional.) The number of seconds to timeout
# 		                   after (defaults to 60 seconds).
#

sub blocking_read
{
	my $self = shift;

	# first, check for unread'ed data we can give them back instead of
	# having to go to the socket:
	if (size_in_bytes($self->{unread_buffer}))
	{
		return $self->_read_unreaded_data(@_);
	}

	my $timeout = pop || DEFAULT_TIMEOUT;

	# block until the socket is readable:
	my $read_mask = '';
	vec($read_mask, fileno $self->handle, 1) = 1;
	select($read_mask, undef, undef, $timeout);

	# if it isn't readable after all of that blocking, time out:
	return $self->network_error('Read timed out')
		unless (vec($read_mask, fileno $self->handle, 1) == 1);

	$self->state(READABLE);

	return $self->_system_read(@_);
}





################################################################################
#
# 	Method
# 		unread($data)
#
# 	Purpose
# 		This method puts data back unto the socket. Call this method
# 		if you've read to much data arean't ready to process all of what
# 		you've read yet.
#
# 	Parameters
# 		$data - The data to unread back onto the socket.
#

sub unread
{
	my ($self, $data) = @_;


	$self->{unread_buffer} = $data . $self->{unread_buffer};
}





################################################################################
#
# 	Method
# 		writable_state()
#
# 	Purpose
# 		This method sets the socket to its writable state. It invokes
# 		any writable callback set using the
# 		register_writable_callback() method.
#
# 	Parameters
# 		None.
#

sub writable_state
{
	my $self = shift;

	$self->state(WRITABLE);

	invoke_callback($self->{writable_callback}, $self);
}





################################################################################
#
# 	Method
# 		non_blocking_write($write_buffer [, $write_size])
#
# 	Purpose
# 		This method attempts to do a non-blocking write to the socket.
# 		It writes $write_size bytes from $write_buffer to the socket,
# 		or, if $write_size is not specified, then all of $write_buffer
# 		to the socket. It returns the number of bytes successfully
# 		written or undef if some error occurs (call network_error() to
# 		retrieve the error message.
#
# 	Parameters
# 		$write_buffer - A string containing stuff you want written to
# 		                the socket.
# 		$write_size   - (Optional.) The number of bytes to write from
# 		                $write_buffer.
#

sub non_blocking_write
{
	my $self = shift;

	return $self->_system_write(@_);
}





################################################################################
#
# 	Method
# 		blocking_write($write_buffer [, $write_size, $timeout])
#
# 	Purpose
# 		This method attempts to do a blocking write to the socket.
#
# 		First, it blocks until the socket becomes writable or $timeout
# 		seconds pass and a timeout occurs. Then it tries to write
# 		$write_size bytes to the socket from $write_buffer, or all of
# 		$write_buffer if $write_size is not specified. It returns the
# 		number of bytes actually written or undef if some network error
# 		occurs (call network_error() to retrieve the error message).
#
# 	Parameters
# 		$write_buffer - A string containing bytes to write to the
# 		                socket.
# 		$write_size   - (Optional.) The number of bytes from
# 		                $write_buffer to write (defaults to 4096).
# 		$timeout      - (Optional.) The number of seconds to timeout
# 		                after (defaults to 60 seconds).
#

sub blocking_write
{
	my $self    = shift;
	my $timeout = $_[2];

	# first, block until the socket is writable:
	my $write_mask = '';
	vec($write_mask, fileno $self->handle, 1) = 1;
	select(undef, $write_mask, undef, $timeout);

	# if it isn't writable after all of that blocking, time out:
	return $self->network_error('Write timed out')
		unless (vec($write_mask, fileno $self->handle, 1) == 1);

	$self->state(WRITABLE);

	return $self->_system_write(@_);
}





################################################################################
#
# 	Method
# 		disconnect()
#
# 	Purpose
# 		This method disconnects the socket.
#
# 	Parameters
# 		None.
#

sub disconnect
{
	my $self = shift;

	close $self->handle;

	$self->last_active(time);
	$self->state(DISCONNECTED);

	return 1;
}





################################################################################
#
# 	Method
# 		is_connected()
#
# 	Purpose
# 		This method checks to see if the socket is connected. It
# 		returns true if it is, undef if it isn't.
#
# 	Parameters
# 		None.
#

sub is_connected
{
	my $self = shift;

	# IO::Socket::connected() uses getpeername():
	return 1 if ($self->state != DISCONNECTED
			and $self->handle
			and getpeername($self->handle));
}





################################################################################
#
# 	Method
# 		state()
#
# 	Purpose
# 		This method returns the current state of the socket in the form
# 		of a number which can be compared with the following
# 		constants: DISCONNECTED, CONNECTABLE, CONNECTING, CONNECTED,
# 		READABLE, READING, WRITABLE, WRITING.
#
# 	Parameters
# 		None.
#

sub state
{
	my $self = shift;

	if (@_)
	{
		$self->{state} = shift;
	}
	else
	{
		return $self->{state};
	}
}





################################################################################
#
# 	Method
# 		handle([$handle])
#
# 	Purpose
# 		This method gets or sets the file handle of the socket used
# 		internally.
#
# 	Parameters
# 		$handle - (Optional.) A socket file handle.
#

sub handle
{
	my $self = shift;

	$self->{handle} = shift if @_;

	return $self->{handle};
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





################################################################################
#
# 	Method
# 		type()
#
# 	Purpose
# 		This method returns the socket type as a number, which can be
# 		compared with the IO::Socket constants SOCK_STREAM and
# 		SOCK_DGRAM.
#

sub type { return shift->{type} }





################################################################################
#
# 	Method
# 		last_active([$time])
#
# 	Purpose
# 		This method gets or sets the time() the socket was last active.
#
# 	Parameters
# 		$time - (Optional.) A new time() value of when the socket was
# 		        last active.
#

sub last_active
{
	my $self = shift;

	$self->{last_active} = shift if @_;

	return $self->{last_active};
}





################################################################################
#
# 	Method
# 		network_error([$error])
#
# 	Purpose
# 		This method gets or sets the last network error message.
#
# 	Parameters
# 		$error - (Optional.) The last network error message.
#

sub network_error
{
	my $self = shift;

	if (@_)
	{
		$self->{network_error} = shift;

		# return nothing, so the caller can do
		# "return $self->network_error($error_message);" and their sub
		# will return correctly:
		return;
	}
	else
	{
		return $self->{network_error};
	}
}





# this method performs a connect
sub _connect
{
	my ($self, $host, $port) = @_;

	$self->host($host);
	$self->port($port);

	# first get the packed four byte IP address:
	my $address;
	if ($host =~ /^\d+(\.\d+){3}$/)
	{
		$address = inet_aton($host);
	}
	else
	{
		$address = gethostbyname($host);
	}

	# now connect:
	return connect($self->handle, sockaddr_in($port, $address));
}





sub _make_non_blocking
{
	my $self = shift;

	# On Windows we need to use ioctl() (in Winsock, this is
	# socketioctl()) to make a socket non-blocking, since a socket isn't
	# *just* a file descriptor. Everywhere else we can just use fcntl():
	if (get_os_name() =~ /^MSWin/i)
	{
		my $mode = pack('L', 1);
		ioctl($self->handle, FIONBIO, \$mode)
			or return $self->network_error(
				"Couldn't make the socket non-blocking: $!\n"
			);
	}
	else
	{
		my $flags = fcntl($self->handle, F_GETFL, 0)
			or return $self->network_error(
				"Can't get IO flags for the socket: $!\n"
			);
		fcntl($self->handle, F_SETFL, $flags|O_NONBLOCK)
			or return $self->network_error(
				"Couldn't make the socket non-blocking: $!\n"
			);
	}

	return 1;
}





sub _make_blocking
{
	my $self = shift;

	unless (get_os_name() =~ /^MSWin/i)
	{
		my $flags = fcntl($self->handle, F_GETFL, 0)
			or return $self->network_error(
				"Couldn't get socket flags: $!"
			);

		until (fcntl($self->handle, F_SETFL, $flags & ~O_NONBLOCK))
		{
			return $self->network_error(
				"Couldn't set socket to non-blocking mode: $!"
			) unless ($! == EAGAIN or $! == EWOULDBLOCK);
		}
	}
	else
	{
		my $mode = pack("L", 0);
		ioctl($self->handle, FIONBIO, $mode)
			or return $self->network_error(
				"Couldn't set socket to non-blocking mode: $!"
			);
	}
}





# This reads data that was unread back onto the socket using unread():
sub _read_unreaded_data
{
	my ($self, $read_buffer_ref, $read_size, $offset) = @_;

	$read_size ||= DEFAULT_READ_SIZE;
	$offset    ||= 0;

	substr($$read_buffer_ref, $offset) =
		substr($self->{unread_buffer}, 0, $read_size);

	return size_in_bytes(substr($$read_buffer_ref, $offset));
}





# This method performs a system-level read on the socket. It takes as its first
# argument a reference to a scalar. The bytes read from the socket will be
# stored there. As the second argument, it takes the number of bytes to read
# from the socket into the buffer. As the third argument, it takes an offset of
# where to start copying the bytes read into the buffer.
#
# It returns the number of bytes read or undef if some error occurs.
sub _system_read
{
	my ($self, $read_buffer_ref, $read_size, $offset) = @_;

	$read_size ||= DEFAULT_READ_SIZE;
	$offset    ||= 0;

	while (1)
	{
		$self->state(READING);

		my $rv;
		if ($self->type == SOCK_STREAM)
		{
			$rv = sysread(
				$self->handle,
				$$read_buffer_ref,
				$read_size,
				$offset
			);
		}
		else
		{
			use bytes;

			if ($offset)
			{
				my $udp_recv_buffer;

				$rv = recv(
					$self->handle,
					$udp_recv_buffer,
					$read_size,
					0,
				);

				if (defined $rv)
				{
					substr($$read_buffer_ref, $offset) =
						$udp_recv_buffer;
				}
			}
			else
			{
				$rv = recv(
					$self->handle,
					$$read_buffer_ref,
					$read_size,
					0,
				);
			}
		}

		$self->state(CONNECTED);
		$self->last_active(time);

		unless (defined $rv)
		{
			# try again if we were interrupted by SIGCHLD or
			# something else:
			redo if ($! == EINTR);

			# a real network error occurred and there's nothing we
			# can do about it:
			return $self->network_error(
				"Couldn't read from socket: $!"
			);
		}

		# sysread() returns the number of bytes actually read,
		# recv()--which is actually recvfrom()--unfortunately, doesn't:
		my $bytes_read =
			($self->type eq SOCK_STREAM)
				? $rv
				: size_in_bytes($$read_buffer_ref) - $offset;

		return $bytes_read;
	}
}





# This method performs a system-level write on the socket. It takes a scalar
# containing bytes to write to the socket as its first argument, and as the
# second optional argument it takes the number of bytes to write. If you don't
# specify the number of bytes to write, then it will write all of the bytes in
# the first argument to the socket.
#
# It returns the number of bytes written or undef if some error occurs.
sub _system_write
{
	my $self         = shift;
	my $write_buffer = shift;
	my $write_size   = shift || size_in_bytes($write_buffer);

	while (1)
	{
		$self->state(WRITING);

		my $bytes_written;
		if ($self->type eq SOCK_STREAM)
		{
			$bytes_written = syswrite(
				$self->handle, $write_buffer, $write_size
			);
		}
		else
		{
			# perldoc -f says send() returns the number of
			# *characters* written, but--as of 5.6.1--it still
			# returns the number of bytes of written (which is what
			# you'd want and expect anyway). 5.8.1 says it depends
			# on if and how the socket was binmode()'d. Making this
			# scope run under the "bytes" pragma probably wont
			# hurt (See RTSP/Utility.pm for the magic we use to
			# ensure "use bytes" always works):
			use bytes;

			$bytes_written = $self->send($write_buffer, 0);
		}

		$self->state(CONNECTED);
		$self->last_active(time);

		unless (defined $bytes_written)
		{
			# try again if we were interrupted by SIGCHLD or
			# something else:
			redo if ($! == EINTR);

			# a real network error occurred and there's nothing we
			# can do about it:
			return $self->network_error(
				"Couldn't write to socket: $!"
			);
		}

		# make sure the entire request was sent:
		return $self->network_error(
			sprintf('Data partially written (only %d %s of data ' .
				'of a total of %d %s): %s',
				$bytes_written,
				($bytes_written == 1) ? 'byte' : 'bytes',
				$write_size,
				($write_size == 1) ? 'byte' : 'bytes',
				$!
			)
		) unless ($bytes_written == $write_size);

		return $bytes_written;
	}
}

1;
