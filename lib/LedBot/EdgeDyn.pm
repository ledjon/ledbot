package LedBot::EdgeDyn;

# update ip address with edgedyn

use strict;
use Net::EdgeDyn;

use constant USER => 'ledbot';
use constant PASS => 'asdf';

main->addcmd('edgedyn-update', \&update);

# time-based wrapper for _update()
sub update {
	my ($self, $event, $chan, $data, @to) = @_;

	main->doqueue($chan, "Updating IP Address with EdgeDyn");
	
	main->time_trap(10, \&_update, @_);

	if($@) {
		main->qmsg($chan, "Error updating ip: " . $@);
	}
}

sub _update {
	my ($self, $event, $chan, $data, @to) = @_;

	my $dyn = Net::EdgeDyn->new(
			User	=> USER,
			Pass	=> PASS,
			Debug	=> 1
	) or die $!;

	$dyn->login or die $dyn->errstr;
	$dyn->update or die $dyn->errstr;
	$dyn->close;

	main->qmsg($chan, "EdgeDyn: " . $dyn->msg);
}

1;
__END__
