package RTSP::Request;

=head1 NAME

RTSP::Request - Class encapsulating RTSP requests

=head1 SYNOPSIS

 my $request = new RTSP::Request ('SETUP',
 	URI     => 'rtsp://somesite.com/some/stream',
 	Version => '1.0',
 	Headers => {
 		'Content-Type'
 	}
 
 $request->method('METHOD_NAME');
 $request->version('1.0');
 
 my $accept = $request->get_header('Accept');
 
=head1 DESCRIPTION

This class is used to encapsulate RTSP requests sent by an RTSP client to an
RTSP server or from an RTSP server to an RTSP client.

An RTSP request consists of a request line containing the RTSP method name,
the URL of the requested resource, and a protocol version. After that are the
request headers, and possibly a request body.

This class contains methods to manipulate the elements of an RTSP request,
including its request line, headers, and body. It inherits the methods from
B<RTSP::Headers> to enable header manipulation, so all methods from that class
can be called on B<RTSP::Request> objects.

=cut

use 5.005;
use strict;
use warnings;
use base 'RTSP::Error';
use base 'RTSP::Headers';
use RTSP::Utility 'get_named_params';
use RTSP::URI 'make_uri_absolute';







#==============================================================================#

=head2 new(METHOD [, OPTIONS])

The constructor method. This creates a new RTSP::Request object and returns a
reference to it. The first and only mandatory argument is a string containing
the RTSP request method name (for example, "SETUP", "OPTIONS", or "TEARDOWN").

In addition, it takes the following optional named parameters:

=over 4

=item URI/URL

The URI (alternately spelled URL) of the RTSP request. The URI of an RTSP, if
its present, must be absoluteDefaults to "*".

=item Version

(Optional.) The RTSP protocol version number. Defaults to 1.0.

=cut

sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	my $method = shift;

	my ($uri, $url, $version, $headers, $body, $callback);
	get_named_params({
		URI              => \$uri,
		URL              => \$url,
		Version          => \$version,
		Headers          => \$headers,
		Body             => \$body,
		ResponseCallback => \$callback
		}, \@_
	);

	$uri     ||= $url;
	$version ||= 1.0;



	# create a new RTSP::Headers object:
	my $self = $class->SUPER::new;

	# a string containing the request method ("DESCRIBE",
	# "OPTIONS", "SETUP", or "PLAY", for example):
	$self->{method}           = $method;

	# a string containing the absolute URI of the request or just a
	# "*", indicating the request isn't specific to any one
	# resource:
	$self->{uri}              = make_uri_absolute($uri);

	# the protocol version number (probably 1.0):
	$self->{version}          = $version;

	# the request body (probably nothing):
	$self->{body}             = $body;

	# the callback to invoke if the request is sent successfully:
	$self->{success_callback} = $success_callback;

	# the callback to invoke if the request is unsuccessfull:
	$self->{failure_callback} = $failure_callback;

	# the time() the request was sent (used to ensure proper
	# retransmission of requests over UDP if no response is
	# received in the alloted time:
	$self->{_time_sent}       = undef;

	# has the request been acknowledged by the server (meaning that
	# the response is being received)?
	$self->{_acknowledged}    = 0;



	$self->initialize_headers($headers);

	return $self;
}





sub as_string
{
	my $self = shift;

	$self->set_header(
		Name  => 'Content-Length',
		Value => size_in_bytes($self->body)
	) if (defined $self->body);

	my $request_string  = $self->method;
           $request_string .= ' ';
	   $request_string .= $self->uri;
	   $request_string .= ' RTSP/';
	   $request_string .= $self->version;
	   $request_string .= $CRLF;
	   $request_string .= $self->headers_as_string;

	   $request_string .= $CRLF;
	   $request_string .= $CRLF;

	   $request_string .= $self->body if (defined $self->body);

	return $request_string;
}





sub host
{
	my $self = shift;

	$self->{host} = shift if @_;

	return $self->{host};
}





sub method
{
	my $self = shift;

	$self->{method} = shift if @_;

	return $self->{method};
}





sub uri
{
	my $self = shift;

	$self->{uri} = make_uri_absolute(shift) if @_;

	return $self->{uri};
}

sub url { return shift->uri(@_) }





sub version
{
	my $self = shift;

	$self->{version} = shift if @_;

	return $self->{version};
}





sub body
{
	my $self = shift;

	$self->{body} = shift if @_;

	return $self->{body};
}





sub body_ref
{
	return \$self->{body}
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





sub succeed
{
	my $self = shift;

	invoke_callback($self->success_callback, @_);
}





sub fail
{
	my $self = shift;

	invoke_callback($self->failure_callback, $self->error, @_);
}





sub time_sent
{
	my $self = shift;

	$self->{time_sent} = shift if @_;

	return $self->{time_sent};
}





sub acknowledged
{
	my $self = shift;

	$self->{acknowledged} = (shift @_) ? 1 : 0 if @_;

	return $self->{acknowledged};
}

1;
