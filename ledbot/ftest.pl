#!/usr/bin/perl

use strict;
use lib './lib';
use LedBot::FifoEvent;
use Data::Dumper;

$|++;
select(STDERR); $|++;
select(STDOUT);

my $fifo = LedBot::FifoEvent->new;
$fifo->add('asdf', \&_trigger, 'test');

while(1) {
	$fifo->trigger;
}

sub _trigger {
	my $data = shift;

	warn("got callback\n");

	print $data;
}

sub debug {
	shift;
	warn(@_, $/);
}

1;
__END__
