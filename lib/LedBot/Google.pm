package LedBot::Google;

use strict;
use Net::Google;
use constant GOOGLE_KEY => 'xUF5L/xKAAbh6WKg/HEunZDfqj0rQxxq';

main->addcmd('google', \&search, 'search');
main->addcmd('spell', \&spell);

sub search {
	my ($self, $event, $chan, $data, @to) = @_;

	main->time_trap(10, \&_search, @_);
	
	if($@) {
		main->qmsg($chan, "Unable to do search (timeout)");
	}
}

sub spell {
	my ($self, $event, $chan, $data, @to) = @_;

	main->time_trap(10, \&_spell, @_);

	if($@) {
		main->qmsg($chan, "Unable to check spelling (timeout)");
	}
}

sub _search {
	my ($self, $event, $chan, $data, @to) = @_;
	
	return unless main->can_access($event->userhost);
	
	my $google = Net::Google->new(key => GOOGLE_KEY) or die $!;

	my $search = $google->search;

	$search->query($data);
	$search->lr(qw(en));
	$search->max_results(5);

	main->qmsg($chan, "Search Results for [$data]:");
	for my $r (@{$search->response}) {
		my @relements = @{$r->resultElements};
		unless(scalar @relements) {
			main->qmsg($chan, "[ No search results found for `$data' ]");
		} else {
			main->qmsg($chan, '[ ' . _clean( $_->title ) . ' ] [ ' . $_->URL . ' ]') for (@relements); 
		}
	}
}

sub spell {
	my ($self, $event, $chan, $data, @to) = @_;

	return unless main->can_access($event->userhost);

	my $google = Net::Google->new(key => GOOGLE_KEY) or die $!;

	if(my $ret = $google->spelling(phrase => $data)->suggest) {
		main->qmsg($chan, "Google suggests spelling [$data] as [$ret]");
	} else {
		main->qmsg($chan, "No result for spelling of [$data]");
	}
}

sub _clean($) {
	my $in = shift;
	$in =~ s/<[^>]+>//g;

	return $in;
}

1;
__END__
