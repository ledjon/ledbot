package LedBot::Freshmeat;

use strict;
use vars qw($VERSION);
use LedBot::Special qw(:xmlcommon entities);

$VERSION = '1.03';

my %config = (
		cache	=> undef,
		updated	=> 0,
		url	=> 'http://freshmeat.net/backend/fm.rdf'
);

main->addcmd('freshmeat', \&handler);

sub handler {
	my ($self, $event, $chan, $data, @to) = @_;

	return unless main->can_access($event->userhost);

	return news($chan, $data);
}
			
sub news {
	my $chan = shift;
	my $range = shift || 5;
	
	if($config{'updated'} < (time() - 3600)) {
		$config{'updated'} = time();

		main->doqueue($chan, 'Refreshing freshmeat cache.');

		$config{'cache'} = fetchpage($config{'url'});

		main->doqueue($chan, "Unable to fetch headlines!"), return unless $config{'cache'};
	}

	return unless defined $config{'cache'};

	main->debug($config{'cache'});

	my $ref = xml_parse($config{'cache'});

	my ($start, $stop) = getrange($range);
	
	for(my $i = $start; $i < $stop && $ref->{'item'}->[$i]; $i++) {
		main->qmsg($chan, sprintf('[%02d] ', $i + 1) . entities($ref->{'item'}->[$i]->{'title'}) . ' [ ' .
					$ref->{'item'}->[$i]->{'link'} . ' ]');
	}
	
	return 1;
}

1;
__END__
