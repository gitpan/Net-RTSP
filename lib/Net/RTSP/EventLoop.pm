package Net::RTSP::EventLoop;

=head1 NAME

Net::RTSP::EventLoop - The Net::RTSP event loop.

=head1 SYNOPSIS

 use Net::RTSP::EventLoop;
 
 my $event_loop = new Net::RTSP::EventLoop;
 
 ...
 
 $event_loop->add_socket($socket);
 
 ...
 
 $event_loop->run;

=head1 DESCRIPTION

=cut

use 5.005;
use strict;
use warnings;
use Net::RTSP::Exception;
use Net::RTSP::Socket;
use RTSP::Utility 'get_named_params';

use constant DEFAULT_MAX_CONNECTIONS => 12;

BEGIN {
	eval {
		require Time::HiRes;
		Time::HiRes->import('time');
	};

	Net::RTSP::Exception->call_warn(
		"Couldn't load Time::HiRes for high resolution microsecond " .
		"time manipulation: $@. All time manipulations will be less " .
		"accurate."
	) if ($@);
}





sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	my ($sockets, $max_active_connections) =
		get_named_params(['Sockets', 'MaxActiveConnections'], \@_);

	my $self = {
		# a hash containing all of the active Net::RTSP::Socket
		# objects where each key is, unfortunately, the stringified
		# file handle obtained via $socket->file_handle:
		active_sockets         => {},

		# the select() read bitmask:
		read_mask              => '',

		# the select() write bitmask:
		write_mask             => '',

		# the select() exception bitmask:
		exception_mask         => '',

		# this stores a queue of all pending Net::RTSP::Socket objects.
		# We'll shift them out of here and stick them in active_sockets
		# as needed:
		pending_sockets        => $sockets ? $sockets : [],

		# this stores a list of arrayrefs for after events--that is,
		# events that are scheduled to occur "after" a certain amount
		# of time. Each array contains an event ID, the time() value of
		# when the event is to occur, and a reference to a sub
		# containing the event to execute:
		after_events           => {},

		# the maximum number of sockets in active_sockets at once:
		max_active_connections =>
			$max_active_connections || DEFAULT_MAX_CONNECTIONS

		# After IDs are incremented for each new event added to the
		# after_events list. This is the current ID number to use:
		next_after_id          => 1
	};
}





sub do_one_event
{
	my $self = shift;

	# make sure there's still *something* left to do:
	return unless (%{ $self->{after_events} }
		or %{ $self->{active_sockets} }
		or %{ $self->{pending_sockets} });



	# first, execute any pending after events:
	foreach my $after_id (keys %{ $self->{after_events} })
	{
		if ($self->{after_events}{$after_id}[0] > time)
		{
			# call the callback:
			&{ $self->{after_events}{$after_id}[1] };

			# now remove it:
			delete $self->{after_events}{$after_id};
		}
	}

	
	while (%{ $self->{active_sockets } < $self->max_active_connections
		and $self->{pending_sockets})
	{
		my $socket = shift @{ $self->{pending_sockets} };

		$socket->connect_socket or next;

		# we store the Net::RTSP::Socket object in the active sockets
		# hash using its file descriptor number (or faked file
		# descriptor number on windows), as this is what the select()
		# bitmasks take and set:
		my $fd = fileno $socket->file_handle;

		$self->{active_sockets}{$fd} = $socket;
 
		# add the file descriptor to the bitmasks:
		vec($self->{read_mask}, $fd, 1)      = 1;
		vec($self->{write_mask}, $fd, 1)     = 1;
		vec($self->{exception_mask}, $fd, 1) = 1;
	}

	# Mark the handles in $read_mask that have stuff to read, the ones in
	# $write_mask that are ready for writing, and the ones in
	# $exception_mask with pending exceptions. But don't block when doing
	# it:
	my ($read_mask, $write_mask, $exception_mask);
	my $handles_to_process = select(
		$read_mask      = $self->{read_mask},
		$write_mask     = $self->{write_mask},
		$exception_mask = $self->{exception_mask}
		undef
	);

	if ($handles_to_process)
	{
		foreach my $fd (keys %{ $self->{active_sockets} })
		{
			my $socket = $self->{active_sockets}{$fd};

			# make sure it's still connected:
			unless ($socket->is_connected)
			{
				$self->remove_socket($socket);

				next;
			}

			# check for timeouts:
			if (time - $socket->last_active > $socket->timeout)
			{
				$socket->disconnect;

				$self->remove_socket($socket);

				next;
			}

			# we give reading the highest priority:
			if (vec($read_mask, $fd, 1))
			{
				$socket->read_from_socket;

				$socket->last_active(time);
			}

			# ...then writing, if there's something to write:
			if (vec($write_mask, $fd, 1)
				and defined $socket->write_bufer)
			{
				$socket->write_to_socket;

				$socket->last_active(time);
			}
		}
	}

	return 1;
}





sub run
{
	my $self = shift;

	my $total_events;
	while ($self->do_one_event)
	{
		$total_events++;
	}

	return $total_events;
}





sub add_socket
{
	my ($self, $socket) = @_;

	push(@{ $self->{pending_sockets} }, $socket);
}





sub remove_socket
{
	my ($self, $socket) = @_;

	my $fd = fileno $socket->file_handle;

	delete $self->{active_sockets}{$fd};

	vec($self->{read_mask}, $fd, 1)      = 0;
	vec($self->{write_mask}, $fd, 1)     = 0;
	vec($self->{exception_mask}, $fd, 1) = 0;
}





sub after
{
	my $self  = shift;
	my $after = shift;

	my $callback = get_named_parameters(['Callback'], @_);

	my $time_to_execute = time + $after;
	my $after_id        = $self->{next_after_id};

	$self->{next_after_id}++;

	$self->{after_events}{$after_id} = [$time_to_execute, $callback];

	return $after_id;
}





sub cancel_after_event
{
	my ($self, $after_id) = @_;

	if (exists $self->{after_events}{$after_id})
	{
		delete $self->{after_events}{$after_id};
	}
}





sub max_active_connections
{
	my $self = shift;

	if (@_)
	{
		$self->{max_active_connections} = shift;
	}
	else
	{
		return $self->{max_active_connections};
	}
}

1;
