package RTSP::Error;

use 5.005;
use strict;
use warnings;
use Carp;
use RTSP::Utility 'invoke_callback';

use vars qw(
	$LAST_ERROR $LAST_WARNING
	$ERROR_CALLBACK $WARNING_CALLBACK
	$RAISE_ERRORS $RAISE_WARNINGS
);



# the last error to occur:
$LAST_ERROR       = undef;

# the last warning to be raised:
$LAST_WARNING     = undef;

# the global error callback to be called whenever an error occurs:
$ERROR_CALLBACK   = undef;

# the global warning callback to be called whenever a warning is raised:
$WARNING_CALLBACK = undef;

$RAISE_ERRORS     = undef;

$RAISE_WARNINGS   = undef;







sub error { return $LAST_ERROR }





sub error_raised { return $LAST_ERROR ? 1 : 0 }





sub warning { return $LAST_WARNING }





sub warning_raised { return $LAST_WARNING ? 1 : 0 }





sub error_callback
{
	my $self = shift;

	$ERROR_CALLBACK = shift if @_;

	return $ERROR_CALLBACK;
}





sub warning_callback
{
	my $self = shift;

	$WARNING_CALLBACK = shift if @_;

	return $WARNING_CALLBACK;
}





sub use_error_callback
{
	my $self = shift;

	$RAISE_ERRORS = (shift) ? 1 : 0 if @_;

	return $RAISE_ERRORS;
}





sub use_warning_callback
{
	my $self = shift;

	$RAISE_WARNINGS = (shift) ? 1 : 0 if @_;

	return $RAISE_WARNINGS;
}





sub raise_error
{
	my ($self, $error) = @_;

	$LAST_ERROR = $error;

	# invoke the global error callback:
	invoke_callback($self->error_callback, $self->error)
		if $self->use_error_callback;

	# always return nothing, so callers can do
	# "return $self->raise_error(...);" and their routines will always
	# return nothing upon failure:
	return;
}





sub raise_warning
{
	my ($self, $warning) = @_;

	$LAST_WARNING = $warning;

	invoke_callback($self->warning_callback, $self->warning)
		if $self->use_warning_callback;

	return;
}





sub _default_error_callback { croak shift }





sub _default_warn_callback { carp shift }

1;
