package RTSP::Response;

use 5.005;
use strict;
use warnings;
use base 'RTSP::Headers';
use RTSP::Utility qw(get_named_params size_in_bytes);
use RTSP::URI 'make_uri_absolute';







sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	my ($version, $code, $description, $headers, $content);
	get_named_params({
		Version     => \$version,
		Code        => \$code,
		Description => \$description,
		Headers     => \$headers,
		Content     => \$content
		}, \@_
	);

	my $self = $class->SUPER::new;

	$self->{version}     = $version;
	$self->{code}        = $code;
	$self->{description} = $description;
	$self->{content}     = $content;

	$self->initialize_headers($headers);

	bless($self, $class);

	return $self;
}





sub version
{
	my $self = shift;

	$self->{version} = shift if @_;

	return $self->{version};
}





sub code
{
	my $self = shift;

	$self->{code} = shift if @_;

	return $self->{code};
}





sub description
{
	my $self = shift;

	$self->{description} = shift if @_;

	return $self->{description};
}





sub content
{
	my $self = shift;

	$self->{content} = shift if @_;

	return $self->{content};
}





sub content_ref
{
	my $self = shift;

	return \$self->{content}
}





sub is_ok
{
	my $self = shift;

	return 1 if ($self->code and $self->code >= 200 and $self->code < 300);
}





sub is_not_ok
{
	my $self = shift;

	return 1 unless ($self->is_ok);

	return;
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

1;
