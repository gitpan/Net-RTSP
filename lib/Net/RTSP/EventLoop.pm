package Net::RTSP::EventLoop;

=head1 NAME

Net::RTSP::EventLoop - The Net::RTSP event loop

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
use Time::HiRes;
use RTSP::Utility qw(get_named_params invoke_callback);
use Net::RTSP::Socket;

use constant DEFAULT_MAX_CONNECTIONS => 12;







sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	my $max_connections = shift || DEFAULT_MAX_CONNECTIONS;

	my $self = {
		# the read bitmask for the select() system call:
		read_mask       => '',

		# the write bitmask for the select() system call:
		write_mask      => '',

		# the exception bitmask for the select() system call:
		exception_mask  => '',

		# the queue of Net::RTSP::Socket objects waiting to be
		# processed:
		pending_sockets => [],

		# a hash containing Net::RTSP::Socket structs as values,
		# indexed by the file descriptor number of each socket file
		# handle:
		active_sockets  => {},

		# the maximum number of axtive connections allowed at once:
		max_connections => $max_connections,

		# the queue of pending "after" events:
		after_events    => [],

		# the ID to use for the next after event:
		next_after_id   => 1,

		# hooks for other event loops:
		hooks           => [],

		# how many things have we done so far?
		count           => 0
	};

	bless($self, $class);

	return $self;
}





sub execute_event_cycle
{
	my $self = shift;

	my $pre_event_count = $self->count;

	# look for a pending after event ready to be executed:
	if (@{ $self->{after_events} }
		and time >= $self->{after_events}[0]{after_time})
	{
		my $after_event = shift @{ $self->{after_events} };

		invoke_callback($after_event->{callback});

		$self->{count}++;
	}

	# if we have room for another active socket, then unqueue one and make
	# it connectable:
	while (keys %{ $self->{active_sockets} } < $self->max_connections
		and @{ $self->{pending_sockets} })
	{
		my $socket = shift @{ $self->{pending_sockets} };

		$socket->connectable_state;

		if ($socket->state == CONNECTING or $socket->state == CONNECTED)
		{
			my $fd = fileno $socket->handle;

			vec($self->{read_mask}, $fd, 1)      = 1;
			vec($self->{write_mask}, $fd, 1)     = 1;
			vec($self->{exception_mask}, $fd, 1) = 1;

			$self->{active_sockets}{$fd} = $socket;
		}
	}



	# now find the active sockets ready for for reading, writing, or with
	# pending exceptins:
	my $readable       = $self->{read_mask};
	my $writable       = $self->{write_mask};
	my $has_exceptions = $self->{exception_mask};
	select($readable, $writable, $has_exceptions, 0);
	while (my ($fd, $socket) = each %{ $self->{active_sockets} })
	{
		if ($socket->state == CONNECTING)
		{
			$socket->poll_non_blocking_connect;

			$self->{count}++;
		}

		# remove dead sockets:
		if ($socket->state == DISCONNECTED)
		{
			delete $self->{active_sockets}{$fd};

			vec($self->{read_mask}, $fd, 1)      = 0;
			vec($self->{write_mask}, $fd, 1)     = 0;
			vec($self->{exception_mask}, $fd, 1) = 0;

			next;
		}

		# notify the caller if their socket is readable:
		if ($self->socket_is_readable($socket, $readable))
		{
			$socket->readable_state;

			$self->{count}++;
		}

		# notify the caller if their socket is writable:
		if ($self->socket_is_writable($socket, $writable))
		{
			$socket->writable_state;

			$self->{count}++;
		}
	}

	# the hooks to execute events from another event loop:
	foreach my $hook (@{ $self->{loop_hooks} })
	{
		$self->{count}++ if (invoke_callback($hook));
	}

	return $self->{count} - $pre_event_count;
}





sub run
{
	my $self = shift;

	my $events_executed = 0;
	
	$events_executed++ while ($self->execute_event_cycle);

	return $events_executed;
}





sub add_socket
{
	my ($self, $socket) = @_;

	push(@{ $self->{pending_sockets} }, $socket);
}





sub remove_socket
{
	my ($self, $socket) = @_;

	# first, we'll check the active sockets hash, cause that's probably
	# where it is, and if it's there, we won't have to bother linear
	# searching the pending sockets queue:
	my $fd = fileno $socket->handle;
	if (exists $self->{active_sockets}{$fd})
	{
		delete $self->{active_sockets}{$fd};

		vec($self->{read_mask}, $fd, 1)      = 0;
		vec($self->{write_mask}, $fd, 1)     = 0;
		vec($self->{exception_mask}, $fd, 1) = 0;
	}
	else
	{
		@{ $self->{pending_sockets} } =
			grep {fileno $_->handle != $fd}
				@{ $self->{pending_sockets} };
	}
}





sub add_after_event
{
	my ($self, $after_time, $after_event) = @_;

	my $event = {
		after_id    => $self->{next_after_id},
		after_time  => $after_time,
		after_event => $after_event,
	};

	push(@{ $self->{after_events} }, $event);

	# order them so the next event to execute is at the beginning of the
	# list:
	@{ $self->{after_events} } = 
		sort {$a->{after_time} <=> $b->{after_time}}
			@{ $self->{after_events} };

	$self->{next_after_id}++;

	return $event->{after_id};
}





sub cancel_after_event
{
	my ($self, $after_id) = @_;

}





sub add_hook
{
	my ($self, $hook) = @_;

	push(@{ $self->{hooks} }, $hook);
}





sub socket_is_readable
{
	my ($self, $socket, $read_mask) = @_;

	return unless ($socket->is_connected);

	return 1 if (vec($read_mask, fileno $socket->handle, 1));
}





sub socket_is_writable
{
	my ($self, $socket, $write_mask) = @_;

	return unless ($socket->is_connected);

	return 1 if (vec($write_mask, fileno $socket->handle, 1));
}




sub max_connections
{
	my $self = shift;

	if (@_)
	{
		$self->{max_connections} = shift;
	}
	else
	{
		return $self->{max_connections};
	}
}





sub count { return shift->{count} }

1;
