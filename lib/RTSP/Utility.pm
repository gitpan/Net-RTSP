package RTSP::Utility;

use 5.005;
use strict;
use warnings;
use vars '@EXPORT_OK';
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
	get_named_params
	get_os_name
	size_in_bytes
	remove_package_prefix
	invoke_callback
);







sub get_named_params
{
	my ($destinations, $arg_list) = @_;

	my $params_hashref;
	if (ref $arg_list eq 'ARRAY')
	{
		if (@$arg_list == 1)
		{
			# only one arg on the stack, so it must be reference to
			# the hash or array we *really* want:
			my $ref = $$arg_list[0];

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
		my $bare_name = lc $real_name;
		   $bare_name =~ s/_//g;
		   $bare_name =~ s/^-//;

		$name_translation_table{$bare_name} = $real_name;
	}

	foreach my $supplied_name (keys %$params_hashref)
	{
		my $bare_name = lc $supplied_name;
		   $bare_name =~ s/_//g;
		   $bare_name =~ s/^-//;

		if (exists $name_translation_table{$bare_name})
		{
			my $real_name   = $name_translation_table{$bare_name};
			my $destination = $destinations->{$real_name};

			$$destination = $params_hashref->{$supplied_name};
		}
	}
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

	# not all systems support $^O:
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
