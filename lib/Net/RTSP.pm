
package Net::RTSP;

=head1 NAME

Net::RTSP - The Perl Real-Time Streaming Protocol client interface

=head2 SYNOPSIS


=head1 DESCRIPTION

This module is not usable. It is still in its early alpha stages.

=head1 METHODS

=cut

use 5.005;
use strict;
use warnings;
use vars qw($VERSION);
use Net::RTSP::EventLoop;
use Net::RTSP::RequestResponseCycle;
use Net::RTSP::Session;
use Net::RTSP::Socket;
use RTSP::Request;
use RTSP::Response;
use RTSP::Utility;





#==============================================================================#

=head2 new([OPTIONS])


=cut

sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	my ($buffer_size, $timeout, $error_handler,
	    $warn_handler, $raise_errors, $raise_warnings) =
		get_named_params([qw(
			BufferSize
			Timeout
			ErrorHandler
			WarnHandler
			RaiseErrors
			RaiseWarnings
			)], \@_
		);

	my $self = {
		buffer_size   => (defined $buffer_size)
					? $buffer_size
					: DEFAULT_BUFFER_SIZE,
		timeout       => (defined $timeout)
					? $timeout
					: DEFAULT_TIMEOUT
	};

	bless($self, $class);

	return $self;
}
