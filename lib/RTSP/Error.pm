package RTSP::Error;

use 5.005;
use strict;
use warnings;
use Carp;
use RTSP::Utility 'invoke_callback';

use vars qw($LAST_ERROR $LAST_WARNING $ERROR_CALLBACK $WARNING_CALLBACK);





# the last error to occur:
$LAST_ERROR       = undef;

# the last warning to be raised:
$LAST_WARNING     = undef;

# the global error callback to be called whenever an error occurs:
$ERROR_CALLBACK   = \&_default_error_callback;

# the global warning callback to be called whenever a warning is raised:
$WARNING_CALLBACK = \&_default_warning_callback;





sub error { return $LAST_ERROR }





sub error_raised { return $LAST_ERROR ? 1 : 0 }





sub warning { return $LAST_WARNING }





sub warning_raised { return $LAST_WARNING ? 1 : 0 }





sub error_callback
{
	my $self = shift;

	if (@_)
	{
		$ERROR_CALLBACK = shift;
	}
	else
	{
		return $ERROR_CALLBACK;
	}
}





sub warning_callback
{
	my $self = shift;

	if (@_)
	{
		$WARNING_CALLBACK = shift;
	}
	else
	{
		return $WARNING_CALLBACK;
	}
}





sub raise_error
{
	my ($self, $error) = @_;

	$LAST_ERROR = $error;

	# invoke the global error callback:
	invoke_callback($ERROR_CALLBACK, $LAST_ERROR);

	# always return nothing, so callers can do
	# "return $self->raise_error(...);" and their routines will always
	# return nothing upon failure:
	return;
}





sub raise_warning
{
	my ($self, $LAST_WARNING) = @_;

	invoke_callback($WARNING_CALLBACK, $LAST_WARNING);

	return;
}





sub _default_error_callback
{
	croak shift;
}





sub _default_warn_callback
{
	carp shift;
}

1;
