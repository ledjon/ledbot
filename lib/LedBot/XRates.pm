package LedBot::XRates;

use strict;
use vars qw($VERSION);
use LedBot::Special qw(strftime fetchpage addcommas);
use constant BASE_RATE => 1;

$VERSION = '1.00';

my %config = (
	time	=> time() - (24 * 3600 - 1),
	url 	=> 'http://www.x-rates.com/calculator.html',
	rates 	=> { }
);

my %rates = ( );
my %rev = ( );

main->addcmd('xrate', \&cmd_handler, 'xrates');

sub cmd_handler {
	my ($self, $event, $chan, $data, @to) = @_;

	my ($from, $rate, $to) = split(/\s+/, $data);

	unless($to and $rate and $from) {
		return main->qmsg($chan, "Usage: " . main->trigger . "xrate <from> <rate> <to>");
	}

	unless(xrates($chan, $rate, $from, $to)) {
		main->qmsg($chan, "Error fetching rates!");
	}
}

sub xrates {
	my ($chan, $rate, $from, $to) = @_;
	my $baserate = BASE_RATE; # always what usd sits at
	cache($chan);
	
	$from = uc $from;
	$to = uc $to;
	
	$from = $rev{$from} if length($from) < 3;
	$to = $rev{$to} if length($to) < 3;
	
	my $fromrate = $rates{$from};
	my $torate = $rates{$to};
	
	unless($fromrate and $torate) {
		main->qmsg($chan, "Unable to get all needed data ($from:$fromrate) ($to:$torate)");
		return 0;
	}
	
	# need to bring it all back to the 'base' measurement
	my $convpct = (eval { $torate / $baserate } || 0.00001) / $fromrate;
	my $value = $rate * $convpct;
	
	return main->qmsg($chan, sprintf('$%s %s -> $%s %s (Rate: %1.2f - Updated: %s)',
					addcommas(sprintf('%1.2f', $rate)), $from,
					addcommas(sprintf('%1.2f', $value)), $to, $convpct,
					strftime('%r', localtime($config{'time'}))
				)
			);
}

sub cache {
	my ($chan) = @_;
	
	if($config{'time'} < (time() - (60 * 60))) { # Cache for one hour
		if($chan) {
			main->doqueue($chan, "Refreshing XRates.");
		}
		
		my $data = fetchpage($config{'url'});
		$data =~ s/\r//;
		
		# read it all and figure how what is what
		for(split(/\n/, $data)) {
			if(/var (\S+) = new Array\((.+)\)/) {
				my $elm = $1;
				for my $arg (split(/,/, $2)) {
					$arg =~ s/\"//g;
					push(@{$config{'rates'}->{$elm}}, $arg);
				}
			}
		}

		# make it all more uniform
		for(my $i = 0; $i < @{$config{'rates'}->{'currency'}}; $i++) {
			$rates{$config{'rates'}->{'currency'}->[$i]} = $config{'rates'}->{'rate'}->[$i];

			# build a reverse lookup table
			$rev{$config{'rates'}->{'country'}->[$i]} = $config{'rates'}->{'currency'}->[$i];
		}

		$config{'rates'} = { };
		$config{'time'} = time();
	}
	
	return 1;
}

1;
__END__
