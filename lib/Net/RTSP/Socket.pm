package Net::RTSP::Socket;

use strict;
use warnings;
use IO::Socket qw(SOCK_STREAM SOCK_DGRAM);





sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	my ($host, $port, $type, $timeout, $write_callback, $read_callback,
	    $read_size, $error_callback) =
		get_named_params([qw(
			Host
			Port
			Type
			Timeout
			WriteCallback
			ReadCallback
			ReadSize
			ErrorCallback
			)], \@_
		);

	my $self = {
		file_handle      => undef,
		type             => (lc $type eq 'udp')
					? SOCK_DGRAM,
					: SOCK_STREAM,
		host             => $host,
		port             => $port,
		timeout          => DEFAULT_TIMEOUT,
		last_active      => undef,
		write_buffer     => undef,
		write_callback   => undef,
		read_buffer      => undef,
		read_callback    => undef,
		read_buffer_size => DEFAULT_BUFFER_SIZE,
		network_error    => undef,
		error_callback   => undef
	};

	bless($self, $class);

	return $self;
}





sub connect
{
	my $self = shift;

	my ($host, $port) = get_named_params(['Host', 'Port'], @_);

	$host ||= $self->host;
	$port ||= $self->port;

	my $socket = new IO::Socket::INET (
		PeerHost => $host,
		PeerPort => $port,
		Timeout  => $self->timeout,
		Type     => $self->type,
		Proto    => ($self->type eq SOCK_STREAM) ? 'tcp' : 'udp'
	) or return $self->network_error($@);

	$self->file_handle($socket);
	$self->last_active(time);

	return $self;
}





sub read_from_socket
{
	my $self          = shift;
	my $bytes_to_read = shift || $self->read_buffer_size;

	# first, empty the buffer:
	$self->read_buffer(undef);

	while (1)
	{
		my $rv;
		if ($self->type eq SOCK_STREAM)
		{
			$rv = $self->file_handle->sysread(
				$self->{'read_buffer'}, $bytes_to_read
			);
		}
		else
		{
			$rv = $self->file_handle->recv(
				$self->{'read_buffer'}, $bytes_to_read, 0
			);
		}

		unless (defined $rv)
		{
			# try again if we were interrupted by SIGCHLD or
			# something else:
			redo if ($! == EINTR);

			# a real network error occurred and there's nothing we
			# can do about it:
			return $self->network_error(
				"Couldn't read from socket: $!"
			);
		}

		# sysread() returns the number of bytes actually written,
		# recv()--which is actually recvfrom()--unfortunately, doesn't:
		my $bytes_read = ($self->type eq SOCK_STREAM)
					? $rv
					: size_in_bytes($self->read_buffer);
	
		if ($self->read_callback)
		{
			$self->read_callback->(
				$self, $self->read_buffer, $bytes_read);
		}

		$self->last_active(time);

		return $bytes_read;
	}
}





sub write_to_socket
{
	my $self           = shift;
	my $data           = shift || $self->write_buffer;
	my $bytes_to_write = shift || size_in_bytes($data);

	while (1)
	{
		my $bytes_written;
		if ($self->type eq SOCK_STREAM)
		{
			$bytes_written = $self->file_handle->syswrite(
				$data, $bytes_to_write
			);
		}
		else
		{
			# perldoc -f says send() returns the number of
			# *characters* written, but--as of 5.6.1--it still
			# returns the number of bytes of written (which is what
			# you'd want and expect anyway). 5.8.1 says it depends
			# on if and how the socket was binmode()'d. Making this
			# scope run under the "bytes" pragma probably wont
			# hurt:
			use bytes;

			$bytes_written = $self->send($data, 0);
		}

		unless (defined $bytes_written)
		{
			# try again if we were interrupted by SIGCHLD or
			# something else:
			redo if ($! == EINTR);

			# a real network error occurred and there's nothing we
			# can do about it:
			return $self->network_error(
				"Couldn't write to socket: $!"
			);
		}
		
		# make sure the entire request was sent:
		return $self->network_error(
			sprintf('Data partially written (only %d %s of data ' .
				'of a total of %d %s): %s',
				$bytes_written,
				($bytes_written == 1) ? 'byte' : 'bytes',
				$bytes_to_write,
				($bytes_to_write == 1) ? 'byte' : 'bytes',
				$!
			)
		) unless ($bytes_written == $bytes_to_write);

		if ($self->write_callback)
		{
			$self->write_callback->($self, $data, $bytes_written);
		}

		# clear the write buffer:
		$self->write_buffer(undef);

		$self->last_active(time);

		return $bytes_written;
	}
}





sub disconnect
{
	my $self = shift;

	if ($self->file_handle)
	{
		close($self->file_handle);

		$self->{connected} = 0;
	}

	$self->last_active(time);
}





sub is_connected
{
	my $self = shift;

	if ($self->{connected}
		and $self->file_handle
		and $self->file_handle->connected)
	{
		return 1;
	}
}





sub file_handle { return shift->{file_handle} }





sub host
{
	my $self = shift;

	if (@_)
	{
		$self->{host} = shift;
	}
	else
	{
		return $self->{host};
	}
}





sub port
{
	my $self = shift;

	if (@_)
	{
		$self->{port} = shift;
	}
	else
	{
		return $self->{port};
	}
}





sub type { return shift->{type} }





sub timeout
{
	my $self = shift;

	if (@_)
	{
		$self->{timeout} = shift;
	}
	else
	{
		return $self->{timeout};
	}
}





sub last_active
{
	my $self = shift;

	if (@_)
	{
		$self->{last_active} = shift;
	}
	else
	{
		return $self->{last_active};
	}
}





sub write_buffer
{
	my $self = shift;

	if (@_)
	{
		$self->{write_buffer} = shift;
	}
	else
	{
		return $self->{write_buffer};
	}
}





sub write_callback
{
	my $self = shift;

	if (@_)
	{
		$self->{write_callback} = shift;
	}
	else
	{
		return $self->{write_callback};
	}
}





sub read_buffer
{
	my $self = shift;

	if (@_)
	{
		$self->{read_buffer} = shift;
	}
	else
	{
		return $self->{read_buffer};
	}
}





sub read_callback
{
	my $self = shift;

	if (@_)
	{
		$self->{read_callback} = shift;
	}
	else
	{
		return $self->{read_callback};
	}
}





sub read_size
{
	my $self = shift;

	if (@_)
	{
		$self->{read_size} = shift;
	}
	else
	{
		return $self->{read_size};
	}
}





sub error_callback
{
	my $self = shift;

	if (@_)
	{
		$self->{error_callback} = shift;
	}
	else
	{
		return $self->{error_callback};
	}
}

1;
