package LedBot::Loop;

# main event-loop for ledbot
# by Jon Coulter
# use with care!
# things in the loop get called very often and very fast

use strict;

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	
	my $self = [ ];
	
	bless($self, $class);
	
	$self->add(@_) if @_;

	return $self;
}

sub add {
	my $self = shift;
	
	while(my ($code, $args) = (shift @_, shift @_)) {
		last unless $code and $args;
		
		push(@{$self}, [$code, $args]);
	}
	
	return 1;
}

sub remove {
	my $self = shift;

	while(my $code = shift @_) {
		last unless $code;

		# $code = [$code, $args] -> $code
		$code = $code->[0] if ref($code) eq 'ARRAY';

		@{$self} = grep { $_->[0] ne $code } @{$self}; 
	}
	
	return 1;
}

sub events {
	return @{shift @_};
}

# the main loop
# just call each event with the params passed
sub loop {
	my $self = shift;

	for my $e ($self->events) {
		last if $e->[0]->(@{$e->[1]}, @_) == -1;
	}
}

1;
__END__
