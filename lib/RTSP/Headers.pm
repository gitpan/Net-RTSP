=head1 NAME

RTSP::Headers

=head1 SYNOPSIS

 ...
 
 $object->set_header(
 	Name  => 'Some-Header',
 	Value => 'value'
 );
 
 $object->get_header('Some-Header', N => 1);

=head1 DESCRIPTION

This class contains methods to manipulate RTSP request or response headers.
Headers are stored in a B<RTSP::Request> or B<RTSP::Response> object as an
array where each element contains the name and value (as a hash) for a single
RTSP header. While the idea is roughly the same, the implementation and the
interface offered here differ substantially from B<HTTP::Headers>.

=cut

use 5.005;
use strict;
use warnings;
use Carp;







sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	my $self = {
		# the array of headers for the RTSP::Headers methods:
		header_list  => [],

		# the hash table used by RTSP::Headers to search header_list
		# more efficiently:
		header_table => {}
	};

	bless($self, $class);

	return $self;
}





#==============================================================================#

=head1 add_header([OPTIONS])

This method adds a single header to the header list within a request or
response object.

This method takes the following named parameters:

=over 4

=item Name

The name of the RTSP header to add.

=item Value

The value of the RTSP header to add.

=back 

=cut

sub add_header
{
	my $self = shift;

	my ($name, $value);
	get_named_params({Name => \$name, Value => \$value}, \@_);

	my $header = {
		name  => $name,
		value => $value
	};

	push(@{ $self->{header_list} }, $header);

	$self->{header_table}{$name} = []
		unless (exists $self->{header_table}{$name}));

	push(@{ $self->{header_table}{$name} }, $header);
}





#==============================================================================#

=head1 get_header(NAME [, OPTIONS])

This method retrieves a header from the list. It takes the name of the header
to retrieve as the first argument, and returns the value if it can
find the header, or nothing if it couldn't.

=cut

sub get_header
{
	my $self = shift;
	my $name = shift;

	my $n;
	get_named_params({N => \$n}, \@_);

	$n ||= 1;
	$n--; # for zero indexing

	if (exists $self->{header_table}{$name})
	{
		return $self->{header_table}{$name}[$n];
	}
}





sub set_header
{
	my $self = shift;

	my ($name, $value, $n);
	get_named_params({Name => \$name, Value => \$value, N => \$n}, \@_);

	$n ||= 1;

	if (exists $self->{header_table}{$name}
		and scalar @{ $self->{header_table}{$name} } >= $n)
	{
		$n--;

		$self->{header_table}{$name}[$n]{value} = $value;
	}
	else
	{
		$self->add_header(
			Name  => $name,
			Value => $value
		);
	}
}





sub remove_header
{
	my $self = shift;
	my $name = shift;

	my $n;
	get_named_params({N => \$n}, \@_);

	if ($n)
	{
		$n--;


	}
}





sub header_is_set
{
	my ($self, $name) = @_;

	return 1 if (exists $self->{header_table}{$name}
			and defined $self->{header_table}{$name}[0]);
}





sub headers_as_string
{
	my $self = shift;

	my $string;
	foreach my $header (@{ $self->{header_list} })
	{
		if (defined $header->{name})
		{
			$string .= "$header->{name}:";
			$string .= " $header->{value}"
				if (defined $header->{value);
			$string .= $CRLF;
		}
	}

	return $string;
}





sub initialize_headers
{
	my $self = shift;

	my $headers_ref;
	my $first_arg = $_[0];
	if (ref $first_arg eq 'HASH')
	{
		$headers_ref = [ %$first_arg ];
	}
	elsif (ref $first_arg eq 'ARRAY')
	{
		$headers_ref = $_[0];
	}
	else
	{
		$headers_ref = [ @_ ];
	}

	while (my ($name, $value) = (shift @$headers_ref, shift @$headers_ref))
	{
		$self->add_header(
			Name  => $name,
			Value => $value
		);
	}
}

1;
