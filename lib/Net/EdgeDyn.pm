package Net::EdgeDyn;

# perl module to talk to jonof's edgedyn server
# doesn't actually make use of Net::Cmd though, kind of unrelated
# by Jon Coulter

# Usage:
# my $dyn = Net::EdgeDyn->new([ opt => arg ]) or die $!;
# $dyn->login(['user', 'pass']) or die $dyn->errstr;
# $dyn->update([x.x.x.x]) or die $dyn->errstr;
# $dyn->close;

# edgedyn echos your ip back to you, so you can do:
# $dyn->update( $dyn->ip ) or die $dyn->errstr;
# if you want to be clever

# Example total usage:
#
# my $dyn = Net::EdgeDyn->new(
#			User	=> 'asdf',
#			Pass	=> 'password'
# ) or die $!;
#
# $dyn->login or die $dyn->errstr;
# $dyn->update or die $dyn->errstr;
# $dyn->close;

# Or:
#
# my $dyn = Net::EdgeDyn->new or die $!;
#
# $dyn->login('user', 'pass') or die $dyn->errstr;
# $dyn->update('2.3.4.5') or die $dyn->errstr;
# ... or
# $dyn->update( $dyn->ip ) or die $dyn->errstr;
# $dyn->close;

use strict;
use IO::Socket::INET;

# defaults
use constant SERVER => 'server.edgedyn.com';
use constant PORT => 14324;

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;

	my $self = bless( { }, $class );

	# get our args and map to lowercase
	my %args = @_;
	@args{map { lc } keys %args} = values %args;
	delete @args{grep { lc ne $_ } keys %args};

	$self->{'args'} = \%args;

	$self->server( $args{'server'} || SERVER );
	$self->port( $args{'port'} || PORT );

	$self->user( $args{'user'} ) if $args{'user'};
	$self->pass( $args{'pass'} ) if $args{'pass'};
	
	$self->debug( $args{'debug'} );

	unless($args{'noconnect'}) {
		$self->connect or return undef;
	}

	return $self;
}

sub _debug {
	my $self = shift;

	warn @_, $/ if $self->debug;
}

sub _method {
	my $self = shift;
	my $arg = shift;

	my $ret = $self->{$arg};

	if(my $val = shift) {
		$self->{$arg} = $val;
	}

	return $ret;
}

# could have used autoload, but oh well
# slightly less overhead this way, since they all get used anyway
sub server { shift->_method('server', @_); }
sub port { shift->_method('port', @_); }
sub user { shift->_method('user', @_); }
sub pass { shift->_method('pass', @_); }
sub sock { shift->_method('sock', @_); }
sub ip { shift->_method('ip', @_); }
sub errstr { shift->_method('errstr', @_); }
sub msg { shift->_method('msg', @_); }
sub debug { shift->_method('debug', @_); }

# connect to server
sub connect {
	my $self = shift;
	my $server = shift || $self->server;
	my $port = shift || $self->port;

	# if we get foo:123
	if(index($server, ':') > 0) {
		$self->port( int( (split(':', $server, 2))[1] ) );
	} else {
		$server = join(':', ($server, $port));
	}

	# connect!
	my $sock = IO::Socket::INET->new( $server ) or return undef;
	$self->sock( $sock );

	# should read in 3 lines:
	# Hello x.x.x.x, I am EdgeDyn Server v1.2
	# Send your edgeid and password and we can begin.
	# +OK
	my $header = $self->getdata;
	if($header =~ /Hello (\S+),/) {
		# save our ip address
		$self->ip( $1 );
	} else {
		$| = 'Bad header line from server';
		return undef;
	}

	# waste of a line
	$self->getdata;

	my $in = $self->getdata;
	unless($self->is_ok( $in )) {
		$| = 'Bad initial +OK line from server';
		return undef;
	}
	# else, we're ready to go!

	return 1;
}

# ->login('user', 'pass')
sub login {
	my $self = shift;
	my $user = shift || $self->user;
	my $pass = shift || $self->pass;

	$self->send('USER ' . $user);

	unless($self->is_ok( $self->getdata )) {
		return undef;
	}

	$self->send('PASS ' . $pass);
	
	unless($self->is_ok( $self->getdata )) {
		return undef;
	}

	return 1;
}

sub update {
	my $self = shift;
	my $ip = shift || 'AUTODETECT';

	$self->send('UPDATE IP ' . $ip);

	unless($self->is_ok( $self->getdata )) {
		return undef;
	}

	return 1;
}

sub send {
	my $self = shift;
	my $msg = shift;

	$self->_debug( $msg );
	return $self->sock->print( $msg . "\r\n" );
}

# read in until we get a new line
sub getdata {
	my $self = shift;

	my $return = undef;
	my $total = 0;
	while(my $rc = $self->sock->sysread(my $buf, 1)) {
		$return .= $buf;
		$total += $rc;

		last unless $rc;
		last if $buf =~ /\n/;
	}

	return undef unless $total;

	$return =~ s/\s+$//g;
	$self->_debug( $return );

	return $return;
}

sub is_ok {
	my $self = shift;
	my $msg = $self->{'msg'} = shift;

	if($msg =~ /^\+OK\s*(.*)$/i) {
		$self->msg($1 || '0E0');
		return $self->msg;
	} else {
		if($msg =~ /^[\+\-]ERROR\s*(.*)$/i) {
			$self->errstr( $1 || 'Unknown Error' );
			return undef;
		} else {
			$self->errstr( 'Bad In Line: ' . $msg );
			return undef;
		}
	}
}

sub quit {
	my $self = shift;

	$self->send('QUIT');
	$self->_debug( 'The quit return: ' . $self->getdata );

	return 1;
}

sub close {
	my $self = shift;

	if(defined $self->sock and $self->sock->opened) {
		$self->quit;
		$self->sock->close;
	}
	
	return 1;
}

sub DESTROY {
	shift->close;
}

1;
__END__
