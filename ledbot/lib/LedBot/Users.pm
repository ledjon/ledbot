package LedBot::Users;

# new user stuff
# by Jon Coulter

use strict;
use LedBot::Special qw(:sql);

# our database layout
my %schema = (
	'users'		=> "
			create table {table} (
				userid integer primary key,
				nick,
				is_god integer
			)
	",
	'hostmasks'	=> "
			create table {table} (
				userid integer,
				hostmask,
				primary key (userid, hostmask)
			)
	",
	'perms'		=> "
			create table {table} (
				userid integer,
				action,
				primary key (userid, action)
			)
	"
);

# get handle / create schema if needed
sql_create( my $dbh = sql_handle('users'), %schema )
	or die "Unable to connect to users table\n";

# pretty tricky, eh?
*main::userdb = \&userdb;

sub userdb { return bless({ }, __PACKAGE__); }

if($ENV{'DEBUG'}) {
	my $uid = main->userdb->adduser( 'ledjon', '*!*ledjon*@*.chcgil2.dsl-verizon.netttt' );

	print "Add user with id: $uid\n";
	print "ID from getid(): ", my $t = main->userdb->getid( '*!*ledjon*@*.chcgil2.dsl-verizon.netttt' ), $/;
	print "Do these match? ", ($uid == $t ? 'Yes' : 'No'), $/;
	print "Make god: ", main->userdb->make_god( $uid ), $/;
	print "Take god: ", main->userdb->make_nogod( $uid ), $/;
	print "Give access to commands: ", main->userdb->give_access( $uid, 'a'..'z' ), $/;

	my $hm = main->userdb->id2hostmask( $uid );

	print "Convert back to hostmask: ", $hm, $/;
	print "Can we now access `a'? ", main->userdb->can_access( $hm, 'a' ), $/;
	print "Take access to `a': ", main->userdb->take_access( $uid, 'a'..'g' ), $/;
	print "Can we now access `a'? ", main->userdb->can_access( $hm, 'a' ), $/;
	print "who are we dealing with? ", join(": ", main->userdb->who( $hm )), $/;
	print "remove user: ", main->userdb->deluser( $hm ), $/;
}

sub dbh { $dbh; }

sub can_access {
	my ($self, $hostmask, $action) = @_;

	return 1 if $self->is_god($hostmask);
	
	my $sth = $dbh->prepare("
				select count(*)
				from hostmasks h, perms p
				where h.userid = p.userid
					and action = ?
					and hostmask = ?
			"
	) or die $dbh->errstr;

	$sth->execute( lc($action), lc($hostmask) ) or die $dbh->errstr;
	my ($c) = $sth->fetchrow_array;

	my $can_access = ($c ? 1 : 0);

	$sth->finish or die $dbh->errstr;
	
	return $can_access;
}

sub is_god {
	my ($self, $hostmask) = @_;

	my $sth = $dbh->prepare("
			select count(*) 
			from hostmasks h, users u
			where h.userid = u.userid
				and u.is_god > 0 
				and h.hostmask = ?
			"
	) or die $dbh->errstr;

	$sth->execute( lc $hostmask ) or die $dbh->errstr;
	my ($c) = $sth->fetchrow_array;

	my $ret = ($c ? 1 : 0);

	$sth->finish or die $dbh->errstr;

	return $ret;
}

sub adduser {
	my ($self, $user, $hostmask, $is_god) = @_;

	# users table
	$dbh->do("insert into users (nick, is_god)
			values (?, ?)", undef, $user, int($is_god)
	) or die $dbh->errstr;

	# now get the userid
	my $uid = $dbh->func('last_insert_rowid') or die "Unable to get the userid insert value!\n";

	# insert hostmask now
	$dbh->do("insert into hostmasks (userid, hostmask)
			values (?, ?)", undef, 
			$uid, lc($hostmask)
	) or die $dbh->errstr;

	return $uid;
}

# remove a user now
sub deluser {
	my ($self, $hostmask) = @_;

	my $sth = $dbh->prepare("
			select u.userid
			from users u, hostmasks h
			where u.userid = h.userid
				and hostmask = ?
			"
	) or die $dbh->errstr;

	$sth->execute( lc $hostmask );

	return 0 unless $sth->rows;

	# loop and remove all parts
	while(my ($uid) = $sth->fetchrow_array) {
		$self->deluser_byid( $uid );
	}

	return 1;
}

sub deluser_byid {
	my ($self, $uid) = @_;
	# delete them all
	for (keys %schema) {
		$dbh->do("delete from $_ where userid = ?", undef, $uid)
			or die $dbh->errstr;
	}

	return 1;
}

# by their nick (bad deal, d00d)
sub deluser_bynick {
	my ($self, $nick) = @_;

	my $sth = $dbh->prepare("
			select userid
			from users
			where nick = ?
	") or die $dbh->errstr;

	$sth->execute( $nick ) or die $dbh->errstr;

	my $i = $sth->rows;
	while(my ($uid) = $sth->fetchrow_array) {
		$self->deluser_byid( $uid );
	}

	$sth->finish;

	return ($i > 0 ? $i : '0E0');
}

# get the uid of a hostmask (user)
sub getid {
	my ($self, $hostmask) = @_;

	my $sth = $dbh->prepare("
			select u.userid
			from users u, hostmasks h
			where u.userid = h.userid
				and h.hostmask = ?
	") or die $dbh->errstr;

	$sth->execute( lc $hostmask ) or die $dbh->errstr;

	return 0 unless $sth->rows;

	my ($uid) = $sth->fetchrow_array;

	$sth->finish or die $dbh->errstr;

	return $uid;
}

sub uids {
	my ($self) = @_;

	my $sth = $dbh->prepare("
			select userid 
			from users
			order by userid 
	") or die $dbh->errstr;

	$sth->execute or die $dbh->errstr;

	my @ret = ( );
	while(my ($uid) = $sth->fetchrow_array) {
		push(@ret, $uid);
	}
	$sth->finish or die $dbh->errstr;

	return @ret;
}

sub nick2id {
	my ($self, $nick) = @_;

	my $sth = $dbh->prepare("
			select userid 
			from users
			where nick = ?
	") or die $dbh->errstr;

	$sth->execute( $nick );

	my @ret = ( );
	while(my ($uid) = $sth->fetchrow_array) {
		push(@ret, $uid);
	}
	$sth->finish or die $dbh->errstr;

	return (wantarray) ? @ret : shift(@ret);
}

# return the first hostmask we have for the uid
sub id2hostmask {
	my ($self, $uid) = @_;

	my $sth = $dbh->prepare("
			select h.hostmask
			from users u, hostmasks h
			where h.userid = u.userid
				and u.userid = ?
			limit 1
		"
	) or die $dbh->errstr;

	$sth->execute( $uid ) or die $dbh->errstr;

	return undef unless $sth->rows;

	my ($hm) = $sth->fetchrow_array;

	$sth->finish or die $dbh->errstr;

	return $hm;
}

sub which_commands {
	my ($self, $uid) = @_;

	my $sth = $dbh->prepare("
			select action
			from perms p
			where p.userid = ?
	") or die $dbh->errstr;

	$sth->execute( $uid ) or die $dbh->errstr;

	my @ret = ( );
	while(my ($a) = $sth->fetchrow_array) {
		push(@ret, $a);
	}
	$sth->finish or die $dbh->errstr;

	return @ret;
}

sub who {
	my ($self, $hostmask) = @_;

	my $sth = $dbh->prepare("
			select nick, hostmask
			from hostmasks h, users u
			where u.userid = h.userid
				and h.hostmask = ?
	") or die $dbh->errstr;

	$sth->execute( lc $hostmask ) or die $dbh->errstr;

	return undef unless $sth->rows;

	my @ret = $sth->fetchrow_array;

	$sth->finish or die $dbh->errstr;

	return (wantarray) ? @ret : $ret[0];
}

sub add_hostmask {
	my ($self, $uid, $hostmask) = @_;

	$dbh->do("replace into hostmasks (userid, hostmask)
			values (?, ?)", undef,
			$uid, lc($hostmask)
	) or die $dbh->errstr;

	return 1;
}

sub del_hostmask {
	my ($self, $uid, $hostmask) = @_;

	$dbh->do("delete from hostmasks where userid = ? and hostmask = ?",
		undef, $uid, lc($hostmask)
	) or die $dbh->errstr;

	return 1;
}

sub give_access {
	my ($self, $uid, @actions) = @_;

	for my $action (@actions) {
		$dbh->do("replace into perms (userid, action)
				values (?, ?)", undef,
				$uid, lc($action)
		) or die $dbh->errstr;
	}

	return 1;
}

sub take_access {
	my ($self, $uid, @actions) = @_;

	for my $action (@actions) {
		$dbh->do(
			"
			delete from perms
			where userid = ?
				and action = ?
			",
			undef, $uid, lc($action)
		) or die $dbh->errstr;
	}

	return 1;
}

sub make_god {
	shift->_update_god( shift @_, 1 );
}

sub make_nogod {
	shift->_update_god( shift @_, 0 );
}

sub _update_god {
	my ($self, $uid, $is_god) = @_;

	$dbh->do("
		update users
		set is_god = ?
		where userid = ?
		", undef, int($is_god), $uid
	) or die $dbh->errstr;

	return 1;
}

END {
	$dbh->disconnect if defined $dbh;
}

1;
__END__
