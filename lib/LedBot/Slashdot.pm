package LedBot::Slashdot;

# fetch and display slashdot headlines
# by Jon Coulter

use strict;
use vars qw($VERSION);
use FindBin qw($RealBin);
use LedBot::Special qw(
	:xmlcommon strftime fh mkpath
	entities getopts shellwords addcommas
);

$VERSION = '1.02';

my $debug = 0;
my $max = 5;

# Slashdot config
my %slash = (
	cache	=> undef,
	updated	=> 0,
	url 	=> 'http://slashdot.org/slashdot.xml'
);

my $dodump = 1;
my $dumpdir = $RealBin . '/dumps/slashdot';

# now we can define other on_public events
main->addcmd('slashdot', \&cmd_handler, '/.', 'slash');
main->addcmd('slashopt', \&cmd_slashopt, 'slashopts');

sub cmd_handler {
	my ($self, $event, $chan, $data, @to) = @_;

	return unless main->can_access($event->userhost);

	return slash_headlines($chan, $data);
}

sub cmd_slashopt {
	my ($self, $event, $chan, $data, @to) = @_;

	return unless main->can_access($event->userhost);
	
	local @ARGV = shellwords( $data );
	getopts('d:m:', \my %opts);
	
	set_dump( $opts{'d'} ) if defined $opts{'d'};
	$max = int($opts{'m'}) if defined $opts{'m'};
}

########
# Slashdot headlines
########
sub cache {
	my $chan = shift;
	my $time = shift || $slash{'updated'};
	
	unless($time < (time() - (60 * 60))) { # Cache for one hour
		return $slash{'cache'};
	} else {
		if($chan) {
			main->doqueue($chan, "Refreshing Slashdot Headlines.");
		}
	}
	
	$slash{'cache'} = fetchpage($slash{'url'});
	my $len = length($slash{'cache'});
	if($len > (5 * 1024)) { # too big, error
		main->doqueue($chan,
			sprintf("Size of result to large (%s bytes) so I'm assuming it was an error.",
				addcommas($len)
			)
		);

		return undef;
	} else {
		if($len) {
			$slash{'updated'} = time();
			slashdump($slash{'cache'}) if $dodump;
		} else {
			main->doqueue($chan, 'Unable to get (refresh) headlines!') if $chan;
			return undef;
		}
	}
	
	return $slash{'cache'};
}

sub slash_headlines {
	my $chan = shift;
	my $range = shift || $max;

	my $cache = cache($chan);
	
	return unless defined $cache;
	
	my $ref = xml_parse($cache);
	
	my ($start, $stop) = getrange($range);

	for(my $i = $start; $i < $stop && $ref->{'story'}[$i]; $i++) {
		main->qmsg($chan,
			sprintf('[%02d] ', $i + 1) . entities($ref->{'story'}[$i]{'title'}) .
				' [ '. $ref->{'story'}[$i]{'url'} .'&mode=nocomment ]'
		);
	}
		
	return 1;
}

# save the xml data to a file now
sub slashdump {
	return unless $dodump;	
	my $cache = shift;
	my @pieces = split(/,/, strftime('%Y,%m', localtime()));
	my $path = $dumpdir;
	
	$path .= '/' . shift(@pieces) while(@pieces);
	
	mkpath($path, 0, 0777) unless -d $path;
	
	return dump_to_file($cache, $path . '/' . strftime('%d.%H.xml', localtime()));
}

sub dump_to_file {
	my ($cache, $file) = @_;
	
	main->debug("Dumping slashdot data ($file)!");
	
	my $fh = fh($file, 'w') or die $!;
	$fh->print($cache);
	$fh->close;
	
	main->debug("Finished with slashdot data dump!");
	
	return $file;
}

sub set_dump($) {
	my $ret = $dodump;
	
	$dodump = (shift) ? 1 : 0;
	
	return $ret;
}

# only accessable via .calc (or .eval)
sub force_recache {
	cache(shift, (time() - 4600));
	return 1;
}

1;
__END__
