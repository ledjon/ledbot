package LedBot::StockQuote;

# stock quotes package

use strict;
use vars qw($VERSION);
use LedBot::Special qw(fetchpage);

$VERSION = '1.01';

my %config = (
	baseurl => 'http://qs.cnnfn.cnn.com/tq/stockquote?symbols=%s',
	codes	=> [
		{
			'name'	=> 'Company Name',
			'regex'	=> '<span class="stockheadline">([^<]+)</span><span class="stocksymbol">([^<]+)</span>',
			'index'	=> '$1 . " " . $2'
		},
		{
			'name'	=> 'Last Price',
			'regex'	=> 'class="stockheader">(\d+\.\d+)</td>',
			'index'	=> '$1'
		},
		{
			'name'	=> 'Change',
			'regex'	=> '(-?(\d|\.)+ / [+-](\d|\.)+%)',
			'index'	=> '$1'
		},
		{
			'name'	=> 'Last Updated',
			'regex'	=> 'last updated on ([\d\/@ :]+)[&<]',
			'index'	=> '$1'
		}
	]
);

main->addcmd('stockquote', \&cmd_handler);

sub cmd_handler {
	my ($self, $event, $chan, $data, @to) = @_;

	return unless main->can_access($event->userhost);

	my ($data, $show_url) = split(/ /, $data);

	my $url = fetchquote($chan, $data);
	
	main->qmsg($chan, "[ $url ]") if $show_url;
}

sub fetchquote($$) {
	my $chan = shift;
	my $symbol = shift;
	
	my %returns = ();
	my $string = undef;
	my $i = 0;

	my $data = uc($symbol);

	my $url = sprintf($config{'baseurl'}, $data);

	main->doqueue($chan, "Getting Stock Quote for $data");

	my $fetch = fetchpage($url);

	unless($fetch) {
		main->qmsg($chan, "Unable to fetch data (from $url)");
		return 0;
	}

	for my $key (sort @{$config{'codes'}}) {
		my $regex = $key->{'regex'};

		main->debug("* Doing: $key->{name} with regex: $regex");

		if($fetch =~ m/$regex/is) {
			main->debug("Found: $1 : $2 : $3");
			eval {
				$returns{++$i} = $key->{'name'} . ': ' . eval $key->{'index'},
				$returns{$i} =~ s/\&nbsp\;/ /ig;
			};

			main->qmsg($chan, $@) if $@;
		}
	}

	$i = 0;
	my @final = ();
	for my $key (keys %returns) {
		if($i++ % 2) {
			$final[-1] .= '    [ '.$returns{$key} . ' ]';
		} else {
			push(@final, '    [ '.$returns{$key} . ' ]');
		}
	}

	if(@final <= 0) {
		main->qmsg($chan, "Unable to find any data for $data");
	} else {
		main->qmsg($chan, "[Stock Quote for $data]:");
		for (@final) {
			main->qmsg($chan, $_);
		}
	}

	return $url;
}

1;
__END__
