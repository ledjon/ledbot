package LedBot::Authen;

use strict;
# auth with authserv (if needed)

#main->events->add([255, 376], [\&on_connect, 1]);
main->events->add(255, [\&on_connect, 1]);

sub on_connect {
	my $self = shift;
	
	main->debug("Hit the connection stage!");
	
	$self->sl('STATS u');
	$self->privmsg('AuthServ@Services.Gamesurge.net', 'auth LedBot asdf');
	#$self->privmsg('nickserv@services.edgegaming.net', 'auth LedBot asdf');
}

1;
__END__
