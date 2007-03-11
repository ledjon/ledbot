package LedBot::VirtDaemon;

# this allows virtual daemonizing stuff
# works by use select() call on sockets
# use LedBot::Loop if you want something to
# get checked every loop (that isn't a socket)

use strict;
use IO::Handle;
use IO::Select;

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	
	return bless({
		'_socks'	=> {},
		'select'	=> IO::Select->new
	}, $class);
}

sub select { shift->{'select'}; }

# damon->add($io_socket, \&callback, \&done_callback, \&shutdown_callback);
sub add {
	my $self = shift;
	my ($handle, $callback, $dcallback, $shutdown) = @_;
	
	die "Need a valid call back!\n" unless ref($callback);
	$dcallback = sub { 0; } unless ref $dcallback;
	$shutdown = sub { 0; } unless ref $shutdown;
	
	$self->{'_socks'}{$handle->fileno} = {
			'handle'	=> $handle,
			'callback'	=> $callback,
			'dcallback'	=> $dcallback,
			'shutdown'	=> $shutdown
	};
	
	$self->select->add($handle);
	
	main->debug("new socket added!");
	
	return 1;
}

sub remove {
	my $self = shift;
	
	for my $s (@_) {
		$self->select->remove($s);
		delete $self->{'_socks'}{$s->fileno};
		main->debug("Removed socket!");
	}
	
	return 1;
}

sub loop {
	my $self = shift;
	
	local $SIG{'PIPE'} = 'IGNORE';
	
	# check for handles that need to be moved
	for my $id (keys %{$self->{'_socks'}}) {
		my $sock = $self->{'_socks'}{$id};
		
		# allow for stop
		if($sock->{'dcallback'}->($sock->{'handle'})) {
			$self->remove($sock->{'handle'});
			
			$sock->{'shutdown'}->($sock->{'handle'});
		}
	}
	
	my $i = 0;
	for my $sock ($self->select->can_read(0)) {
		$i++;
		main->debug("Testing accept");
		
		if(my $client = $sock->accept) {
			main->debug("got it, going on!");
			
			$self->{'_socks'}{$sock->fileno}->{'callback'}->($client);
			
			main->debug("finished with that callback!");
		} else {
			main->debug("Oh no! Got here for some reason!");
		}
	}
	
	main->debug("returning from loop( ) ($i)") if $i;
	
	return 1;
}

1;
__END__
