package Net::RTSP::Session;

=head1 NAME

Net::RTSP::Session - Create and manage real time streaming sessions

=head1 SYNOPSIS

 ... 
 my $session = $sequence->start_session(
 	'http://example.com/stuff/stream.audio',	
 );
 $session->play;

=cut

use 5.005;
use strict;
use warnings;
use base 'Exporter';
use vars '@EXPORT';
use Carp;

# states for the session manager:
use constant INACTIVE  => 0;
use constant READY     => 1;
use constant PLAYING   => 2;
use constant PAUSED    => 3;
use constant RECORDING => 4;







sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	my ($presentation, $uri) = @_;

	my $self = {
		# the current state of the session:
		state         => INACTIVE,

		# the Net::RTSP::Presentation object:
		presentation  => $presentation,

		# the session URI:
		uri           => make_uri_absolute($uri),

		# the session ID given to us by the server in its response to
		# the SETUP request:
		id            => undef,

		# Queue of request objects to be sent from this session.
		# These can't be sent until the initial SETUP request is
		# acknowledged:
		request_queue => []
	};

	bless($self, $class);

	return $self;
}





sub play
{
	my $self = shift;

	my $request = new RTSP::Request ('PLAY', @_);

	$request->session_success_callback(sub { $self->state(PLAYING) });

	return $self->send_request($request);
}





sub pause
{
	my $self = shift;

	my $request = new RTSP::Request ('PAUSE', @_);

	$request->session_success_callback(sub {  $self->state(PAUSED) });

	return $self->send_request($request);
}





sub record
{
	my $self = shift;

	my $request = new RTSP::Request ('RECORD', @_);

	$request->session_success_callback(sub {  $self->state(RECORDING) });

	return $self->send_request($request);
}





sub teardown
{
	my $self = shift;

	return $self->send_request(
		new RTSP::Request ('TEARDOWN',
			SessionSuccessCallback => sub {
				$self->state(INACTIVE)
			},
			@_
		)
	);
}





sub send_request
{
	my ($self, $request) = @_;

	unless ($self->is_inactive)
	{
		$request->set_header(
			Name  => 'Session',
			Value => $self->id
		);

		$self->presentation->send_request($request);
	}
	else
	{
		push(@{ $self->{request_queue} }, $request);
	}
}





sub ready
{
	my $self = shift;

	$self->state(READY);

	if (@{ $self->{request_queue} })
	{
		while (my $request = shift @{ $self->{request_queue} } )
		{
			$request->set_header(
				Name  => 'Session',
				Value => $self->id
			);

			$self->presentation->send_request($request);	
		}
	}
}





sub state
{
	my $self = shift;

	$self->{state} = shift if @_;

	return $self->{state};
}





sub presentation { return shift->{presentation} }





sub uri
{
	my $self = shift;

	$self->{uri} = shift if @_;

	return $self->{uri};
}

sub url { shift->uri(@_) }





sub id
{
	my $self = shift;

	$self->{id} = shift if @_;

	return $self->{id};
}





sub is_inactive { return 1 if (shift->state == INACTIVE) }





sub is_ready { return 1 if (shift->state == READY) }





sub is_playing { return 1 if (shift->state == PLAYING) }





sub is_paused { return 1 if (shift->state == PAUSED) }





sub is_recording { return 1 if (shift->state == RECORDING) }

1;
