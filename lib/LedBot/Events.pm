package LedBot::Events;

# new layer for events
# by Jon Coulter

use strict;
use Net::IRC;
use Net::IRC::Event;

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	
	my $self = { '_conn' => shift @_ };
	
	bless($self, $class);
	
	$self->_setup_events;
	
	return $self;
}

*add = \&add_handler;
*add_global_handler = \&add_handler;
sub add_handler {
	my $self = shift;
	
	while(my ($event, $code) = (shift, shift)) {
		last unless $event and $code;
		
		my $pri = 0;
		if(ref($code) eq 'ARRAY') {
			($code, $pri) = @{$code};
		}
		
		for my $e (ref($event) eq 'ARRAY' ? @{$event} : ($event)) {
			$e = ($e =~ /^\d+$/ ? Net::IRC::Event->trans($e) : $e);
			
			next if !$e or (ref($code) ne 'CODE');
			
			# try as much as we can to keep from duplicating
			$self->remove($e, $code);

			main->debug("add event: $e:$code");
			($pri ? unshift(@{$self->{$e}}, $code) :  push(@{$self->{$e}}, $code));
		}
	}
	
	return 1;
}

*remove = \&remove_handler;
sub remove_handler {
	my $self = shift;
	my $event = shift;
	
	main->debug("remove event: $event:@_");
	
	return unless defined $self->{$event};
	
	my @no = ( );
	for(@_) {
		if(!ref) {
			my $i = int;
			my $t = 0;
			
			push(@no, grep { $t++ == $i } @{$self->{$event}});
		} else {
			my $r = $_;
			push(@no, grep { $_ eq $r } @{$self->{$event}});
		}
	}
	
	my @final = ( );
	for my $e (@{$self->{$event}}) {
		push(@final, $e) unless grep { $_ eq $e } @no;
	}
	
	@{$self->{$event}} = @final;
	
	return 1;
}

# setup core events
sub _setup_events {
	my $self = shift;
	
	my @names = grep { defined }
			map { 	Net::IRC::Event->trans(
					sprintf('%03s', $_)
				)
			} (1..600);
	
	# common non-numeric events
	push(@names, $_) for qw(nick quit public join part mode
				topic kick msg notice ping other
				invite kill disconnect leaving umode
				error cping cversion csource ctime cdcc
				cuserinfo cclientinfo cerrmsg cfinger
				caction crpint crversion crsource crtime
				cruserinfo crclientinfo);
			
	$self->{'_conn'}->add_handler($_, \&_handler, 2) for @names;
}

sub id {
	shift->{'_eventid'};
}

# the main mother
sub _handler {
	my $events = main->events or exit;
	my ($self, $event) = @_;
	
	my $e = $event->type or return;
	
	$events->{$e} ||= [];
	
	return unless scalar(@{$events->{$e}});
	
	$events->{'_eventid'}++;
	
	for (@{$events->{$e}}) {
		main->debug("$_ -> $e: @_");
		
		# an event can stop further events by returning -1
		last if eval { $_->(@_) } == -1;

		main->debug("ERROR: $@") if $@;
	}
}

1;
__END__
