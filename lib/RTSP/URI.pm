package RTSP::URI;

use 5.005;
use strict;
use warnings;
use vars '@EXPORT_OK';
use base 'Exporter';
use RTSP::Error;

@EXPORT_OK = 'make_uri_absolute';





sub make_uri_absolute
{
	my $partial_uri = shift;

	my $absolute_uri;
	if (defined $partial_uri and length $partial_uri)
	{
		$partial_uri = "rtsp://$partial_uri"
			unless ($partial_uri =~ m|^[a-zA-Z0-9]+?://|);

		my $uri = new URI $partial_uri;

		# make sure the URL's scheme isn't something besides RTSP,
		# cause that's all we can handle:
		RTSP::Error->raise_warning(
			sprintf('RTSP URI "%s" has the scheme "%s" when it ' .
			        'shouldis be "rtsp" or "rtspu" instead.',
				$uri->as_string,
				$uri->scheme
			)
		) unless (lc $uri->scheme eq 'rtsp'
			or lc $uri->scheme eq 'rtspu');

		$absolute_uri = $uri->as_string;
	}
	else
	{
		$absolute_uri = '*';
	}

	return $absolute_uri;
}

1;
