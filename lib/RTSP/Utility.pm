package RTSP::Utility;

use 5.005;
use strict;
use warnings;
use vars qw(@EXPORT_OK $CRLF);
use base 'Exporter';
use Carp;

BEGIN {
	# this hack allows us to "use bytes" or fake it for older (pre-5.6.1)
	# versions of Perl (thanks to Liz from PerlMonks):
	eval { require bytes };

	if ($@)
	{
		# couldn't find it, but pretend we did anyway:
		$INC{'bytes.pm'} = 1;

		# 5.005_03 doesn't inherit UNIVERSAL::unimport:
		eval 'sub bytes::unimport { return 1 }';
	}
}

@EXPORT_OK = qw(
	$CRLF

	get_named_params
	get_os_name
	size_in_bytes
	remove_package_prefix
	invoke_callback
);



$CRLF = "\015\012";







sub get_named_params
{
	my ($destinations, $arg_list) = @_;

	croak "Arguments weren't sent as a reference to a hash or array."
		unless (ref $arg_list eq 'ARRAY' or ref $arg_list eq 'HASH');
	
	# this will store a reference to a hash containing the named parameters
	# passed to your sub:
	my $params_hashref;
	if (ref $arg_list eq 'ARRAY')
	{
		if (@$arg_list == 1)
		{
			# The callers of your sub can optionally pass their
			# named parameters as a hash or array references, in
			# which case @_ contains the reference as its first and
			# only element:
			my $ref      = $$arg_list[0];
			my $ref_type = ref $ref;

			croak(
				'Odd number of arguments sent to sub ' .
				'expecting named parameters.'
			) unless $ref_type;

			croak (
				"Bad refernce type \"$ref_type\" for named " .
				"parameters. Pass them instead as either a " .
				"hash or array reference."
			) unless ($ref_type eq 'ARRAY' or $ref_type eq 'HASH');

			$params_hashref = (ref $ref eq 'ARRAY')
						? { @$ref }
						: $ref;
		}
		else
		{
			$params_hashref = { @$arg_list };
		}
	}
	else
	{
		$params_hashref = $arg_list;
	}



	my %name_translation_table;
	foreach my $real_name (keys %$destinations)
	{
		my $stripped_name = strip_param_name($real_name);

		$name_translation_table{$stripped_name} = $real_name;
	}

	foreach my $supplied_name (keys %$params_hashref)
	{
		my $stripped_name = strip_param_name($supplied_name);

		next unless (exists $name_translation_table{$stripped_name});

		my $real_name       = $name_translation_table{$stripped_name};
		my $destination_ref = $destinations->{$real_name};

		$$destination_ref = $params_hashref->{$supplied_name};
	}
}





sub strip_param_name
{
	my $stripped_name = lc shift;
	   $stripped_name =~ s/_//g;
	   $stripped_name =~ s/^-//;

	return $stripped_name;
}





################################################################################
#
#	Function
#		get_os_name()
#
#	Purpose
#		This function reliably returns the name of the OS the script is
#		running one, checking $^O or using Config.pm if that doesn't
#		work.
#

sub get_os_name
{
	my $operating_system = $^O;

	unless ($operating_system)
	{
		require Config;
		$operating_system = $Config::Config{'osname'};
	}

	return $operating_system;
}





################################################################################
#
#	Function
#		size_in_bytes($scalar)
#
#	Purpose
#		This function returns the size of a scalar value in bytes. Use
#		this instead of the built-in length() function (which, as of
#		5.6.1, returns the length in characters as opposed to bytes)
#		when you need to find out out the number of bytes in a scalar,
#		not the number of characters.
#
#	Parameters
#		$scalar - The scalar you want the size of.
#

sub size_in_bytes ($)
{
	use bytes;

	return length shift;
}





sub remove_package_prefix
{
	my $error_message = shift;

	$error_message =~ s/.*?: // if (defined $error_message);

	return $error_message;
}




sub invoke_callback
{
	my $callback = shift;

	if (ref $callback eq 'ARRAY')
	{
		my $routine   = shift @$callback;
		my @arguments = @$callback;

		return $routine->(@_, @arguments);
	}
	elsif (ref $callback eq 'CODE')
	{
		return $callback->(@_);
	}
}

1;
