package RTSP::Request;

=head1 NAME

RTSP::Request - Class encapsulating RTSP requests

=head1 SYNOPSIS

 my $request = new RTSP::Request ('SETUP',
 	URI     => 'rtsp://somesite.com/some/stream',
 	Version => '1.0',
 	Headers => {
 		
 	}
 
 $request->method('METHOD_NAME');
 $request->version('1.0');
 my $accept = $request->header('Header-Name');
 
 
=cut

use 5.005;
use strict;
use warnings;
use vars '$VERSION';
use base 'RTSP::Headers';
use RTSP::Utility;

$VERSION = '0.9';





#==============================================================================#

=head2 new([METHOD, OPTIONS])

The constructor method. This creates a new RTSP::Request object and returns a
reference to it. The first argument is a string containing the RTSP request
method name (for example, "SETUP", "OPTIONS", or "TEARDOWN"). In addition, it
takes the following optional named parameters:

=over 4

=item URI/URL

(Optional.) The I<full> URI (alternately spelled URL) of the RTSP request.
Defaults to "*".

=item Version

(Optional.) The RTSP protocol version number. Defaults to 1.0.

=cut

sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	my $method = shift;

	my ($uri, $url, $version, $headers) =
		get_named_params([qw(
			URI
			URL
			Version
			Headers
			Body
			Handler
			)], \@_
		);

	$uri = $uri || $url;

	my $self = {
		method  => $method,

		uri     => $uri,

		version => $version,

		headers => [],

		# the request body (probably nothing):
		body    => $body

		handler => $handler 
	};

	$self->_set_headers($headers);

	return $self;
}





sub as_string
{
	my $self = shift;

	my $request_string  = $self->method;
           $request_string .= ' ';
	   $request_string .= $self->uri;
	   $request_string .= ' RTSP/';
	   $request_string .= $self->version;
	   $request_string .= $CRLF;


}





sub method
{
	my $self = shift;

	if (@_)
	{
		$self->{'method'} = shift;
	}
	else
	{
		return $self->{'method'};
	}
}





sub uri
{
	my $self = shift;

	if (@_)
	{
		$self->{'uri'} = shift;
	}
	else
	{
		return $self->{'uri'};
	}
}

sub url { shift->uri(@_) }





sub version
{
	my $self = shift;

	if (@_)
	{
		$self->{'version'} = shift;
	}
	else
	{
		return $self->{'version'};
	}
}





sub handler
{
	my $self = shift;

	if (@_)
	{
		$self->{'handler'} = shift;
	}
	else
	{
		return $self->{'handler'};
	}
}
