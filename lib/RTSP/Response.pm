package RTSP::Response;

use 5.005;
use strict;
use warnings;
use base 'RTSP::Headers';
use RTSP::Utility;
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
		Headers     => \$haders,
		Content     => \$content
	});

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

	if (@_)
	{
		$self->{version} = shift;
	}
	else
	{
		return $self->{version};
	}
}





sub code
{
	my $self = shift;

	if (@_)
	{
		$self->{code} = shift;
	}
	else
	{
		return $self->{code};
	}
}





sub description
{
	my $self = shift;

	if (@_)
	{
		$self->{description} = shift;
	}
	else
	{
		return $self->{description};
	}
}





sub content
{
	my $self = shift;

	if (@_)
	{
		$self->{content} = shift;
	}
	else
	{
		return $self->{content};
	}
}





sub content_ref
{
	return \$self->{content}
}





sub succeeded
{
	my $self = shift;

	return 1 if ($self->code and $self->code >= 200 and $self->code < 300);
}





sub failed
{
	my $self = shift;

	return 1 unless ($self->succeeded);

	return;
}

1;
