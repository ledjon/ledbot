package LedBot::Timer;

# time events to happen
# by Jon Coulter

use strict;

sub new { bless( { }, __PACKAGE__ ); }

# add by key
# usage:
# main->timer->add('name', 10, \&ref, [...]);
sub add {
	my ($self, $name, $time, $ref, @other) = @_;

	# add the entry for this event
	$self->{$name} = {
		'interval'	=> $time,
		'code'		=> $ref,
		'other'		=> [@other],
		'exec'		=> (time + $time)
	};

	return 1;
}

# remove by key
sub remove {
	my ($self, $name) = @_;

	return delete $self->{$name};
}

# gets called quite often
sub trigger {
	my $self = shift;
	my $time = time;

	for my $name (keys %{$self}) {
		my $event = $self->{$name};

		# execute it
		if($event->{'exec'} <= $time) {
			$event->{'code'}->( @{$event->{'other'}} );
			$event->{'exec'} = ($time + $event->{'interval'});
		}
	}
}

1;
__END__
