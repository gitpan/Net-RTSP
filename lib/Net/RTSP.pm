
package Net::RTSP;

=head1 NAME

Net::RTSP - The Perl RTSP client API

=head1 SYNOPSIS

 use Net::RTSP;
 
 my $rtsp = new Net::RTSP;

 my $presentation = $rtsp->initialize($uri);
 
 my $stream_uri;
 $presentation->describe(
 	SuccessCallback => sub {
 		my $response = shift;

 		my ($stream_uri, $trasnport_method) =
			extract_sdp_info($response->content);

 		my $session = $presentation->setup_session($stream_uri);
		
 		$session->play;
 	}
 );

 $rtsp->run;

=head1 DESCRIPTION

B<Net::RTSP> implements the Real Time Streaming Protocol in Perl.

=head1 METHODS

=cut

use 5.005;
use strict;
use warnings;
use vars '$VERSION';
use Net::RTSP::EventLoop;
use Net::RTSP::Presentation;
use Net::RTSP::Session;
use Net::RTSP::Socket;
use RTSP::Error;
use RTSP::Request;
use RTSP::Response;
use RTSP::Utility;

use constant DEFAULT_TIMEOUT     => 60;
use constant DEFAULT_BUFFER_SIZE => 4096;

use constant EVENT_DRIVEN_INTERFACE => 1;
use constant PROCEDURAL_INTERFACE   => 2;

push(@ISA, 'Net::RTSP::EventLoop');







#==============================================================================#

=head2 new([OPTIONS])

This is the constructor method. It creates a new Net::RTSP object and returns
a reference to it.

This method does the job of setting up the interface and setting some defaults
which propogate down through all objects spawned from it.

It takes the following named parameters:

=over 4

=item Interface

(Optional.) This takes the type of interface you want to use with B<Net::RTSP>
in the form of a string, eiter "EventDriven" or "Proceedural." If you don't
specify an interface style, then the default event driven interface will be
used instead.

=item Timeout

(Optional.) This allows you to specify a number to be used as the default
timeout limit for many RTSP operations.

If you don't specify a default timeout limit, then 60 seconds becomes the
default.

=item BufferSize

(Optional.) This allows you to specify the default size (in bytes) of the read
buffers used.

If you don't specify a buffer size, then 4096 becomes the default.

=item ErrorCallback

(Optional.) This takes a reference to a routine to be invoked whenever an error
occurs. If you don't specify this, then B<Carp.pm's> C<croak()> function will
be used as the error callback instead.

Every time a B<Net::RTSP> routine raises an error, it calls the error
callback with the error message as the argument and then returns undef. So if
you want, you can supply your own error callback that doesn't C<die()> in place
of C<croak()> and then go about manually checking the return values of all
method calls for success or failure.

=item WarningCallback

(Optional.) This takes a reference to a routine to be invoked for warnings. If
you don't specify this, then B<Carp.pm's> C<carp()> function will be used
instead.

=item RaiseErrors

(Optional.) Should B<Net::RTSP> raise errors at all? If you specify a false
value for this, then the error callback will never ever be invoked. Routines
will just silently fail, stopping execution and returning undef.

=item RaiseWarnings

(Optional.) Should B<Net::RTSP> warn you about potentially bad stuff? If these
helpfull messages start getting in the way, you can specify a false value to
this to disable warning all together; the warn callback will never be invoked
and warnings will go nowhere.

=back

See also the corresponding accessor methods:

=cut

sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	my ($interface, $timeout, $buffer_size, $error_callback,
	    $warn_callback, $raise_errors, $raise_warnings);
	get_named_params({
		Interface     => \$interface,
		Timeout       => \$timeout,
		BufferSize    => \$buffer_size,
		ErrorCallback => \$error_callback,
		WarnCallback  => \$warn_callback,
		RaiseErrors   => \$raise_errors,
		RaiseWarnings => \$raise_warnings,
		}, \@_
	);



	# we create a new Net::RTSP::EventLoop object:
	my $self = $class->SUPER::new;

	# save away the interface type as one of the constants:
	$interface ||= 'EventDriven';
	if (lc $interface eq 'eventdriven')
	{
		$self->{interface_type} = EVENT_DRIVEN_INTERFACE;
	}
	else if (lc $interface eq 'procedural')
	{
		$self->{interface_type} = PROCEDURAL_INTERFACE;
	}
	else
	{
		return Net::RTSP->raise_error(
			"Bad interface type: \"$interface\". It should be " .
			"\"EventDriven\" or \"Procedural\" instead."
		);
	}

	$self->{timeout}         = $timeout        || DEFAULT_TIMEOUT;
	$self->{buffer_size}     = $buffer_size    || DEFAULT_BUFFER_SIZE;
	$self->{raise_errors}    = $raise_errors   ? 1 : 0;
	$self->{raise_warnings}  = $raise_warnings ? 1 : 0;

	# then make it a Net::RTSP object:
	bless($self, $class);

	$self->error_callback($error_callback)     if ($error_callback);
	$self->warning_callback($warning_callback) if ($warning_callback);
	$self->raise_errors($raise_errors);
	$self->raise_warnings($raise_errors);

	return $self;
}





#==============================================================================#

=head2 initialize(PRESENTATION [, OPTIONS])

This method is used to initialize a new RTSP presentation.

The first argument is the URI of the presentation to initialize. The URI should
be absolute. If the scheme of the URI is "rtsp://" then communication will take
place over TCP/IP. If the scheme is "rtspu://" then the communication will take
place over UDP/IP.

In addition to a presentation URI, this method takes the following named
parameters:

=over 4

=item SuccessCallback

(Optional.) For the event-driven interface, this takes a reference to a
callback routine to be invoked if C<initialize()> succeeds in initializing your
presentation. 

The first argument passed to your callback routine will be the
B<Net::RTSP::Presentation> object.

=item FailureCallback

(Optional.) For the event-driven interface, this takes a reference to a
subroutine to be invoked if C<initialize()> fails to initialize your
presentation.

The first argment passed to your callback routine will be the error message.

=item Timeout

(Optional.) The number of seconds to timeout after. If not specified, then the
current timeout value in your B<Net::RTSP> object will be used instead.

=item BufferSize

(Optional.) The read size to use when reading response messages from the
server.

=item PipeLining

(Optional.) If set to true and you're using the event-driven interface, then
all of your requests spawned off of the resulting B<Net::RTSP::Presentation>
object will be "pipe-lined"--that is, they will be sent one after the other
without waiting for the server's response to each; only after the final request
has been sent will the server's response messages be processed. By default,
pipe-lining is off.

=back

With the event-driven interface, you get back an B<Net::RTSP::Presentation>
object right away, but its a mere place holder that won't be filled until you
invoke the C<run()> method and B<Net::RTSP> starts processing events, and the
result of initialization can only be determined via your callback routine.

With the proceedural interface, you'll get back a working
B<Net::RTSP::Presentation> object returned to you, or undef if an error
occurred.

=cut

sub initialize
{
	my $self = shift;

	return new Net::RTSP::Presentation ($self, @_);
}

1;
