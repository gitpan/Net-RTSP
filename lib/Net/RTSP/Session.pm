package Net::RTSP::Session;

=head1 NAME

Net::RTSP::Session - Create and manage real time streaming sessions

=head1 SYNOPSIS

 ...
 
 my $session = $sequence->start_session(
 	'http://example.com/stuff/stream.audio',
 	
 );
	

=cut

use 5.005;
use strict;
use warnings;
use Carp;

# states for the session manager:
use constant SETTING_UP   => 1;
use constant READY        => 2;
use constant PLAYING      => 3;
use constant RECORDING    => 4;
use constant TEARING_DOWN => 5;







sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	my $uri = shift;

	my $self = {
		uri           => make_uri_absolute($uri);
	
		# the current state of the session:
		state         => SETTING_UP,

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

	$self->add_session_request(
		new RTSP::Request (PLAY => @_)
	);
}





sub add_session_request
{
	my $self = shift;

	push(@{ $self->{request_queue} }, shift);
}

1;
