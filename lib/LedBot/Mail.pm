package LedBot::Mail;

# extends the user database
# to allow them to register email things
# to be checked, every once in a while

use strict;
use Net::IMAP::Simple;
use LedBot::Special qw(:sql shellwords gethostmask);
use LedBot::Users;

# how often to check
use constant INTERVAL => 60 * 5;

# schema to be added
my %schema = (
	'mailcheck'	=> "
		create table {table} (
			userid		integer primary key,
			host		varchar(50),
			username	varchar(50),
			password	varchar(50),
			enabled		varchar(100) NULL
		)
	"
);
# note about above, 'enabled' is the nick to msg data to
# or null to disable

# populate the schema
my $dbh = main->userdb->dbh;
sql_create( $dbh, %schema );

# hold queue'd data
my %data = ( );

# add to the top
# this is how we'll see if we've got the right user
main->events->add('userhost' => [\&reply, 1])
	unless main->checkload('userhost_reply');

# add our commands
main->addcmd('mail-config', \&mail_config, 'config-mail');
main->addcmd('mail-enable', \&mail_enable, 'email-mail');
main->addcmd('mail-disable', \&mail_disable, 'disable-mail');
main->addcmd('mail-delete', \&mail_delete);
#main->addcmd('mail', \&mail, 'checkmail', 'mail-check');

# add our timer, to check mail every x seconds
main->timer->add('docheck', INTERVAL, \&do_check);

# catch hosthost request, replies
sub reply {
	my ($self, $event, $chan, $data, @to) = @_;
	
	my ($user, $mask) = split(/=[+-]/, ($event->args)[1], 2);
	
	main->debug(
		sprintf("User: %s - %s [ %s ]",
			$user, $mask, my $hm = gethostmask($mask)
		)
	);

	#return -1;
	return 1;
}


sub mail_config {
	my ($self, $event, $chan, $data, @to) = @_;

	my $nick = lc $event->nick or return;
	my @parts = shellwords( $data );

	if(scalar @parts != 3) {
		main->qmsg( $chan,
			sprintf("Usage: %s"."mail-config <host> <username> <password>",
				main->trigger)
		);

		return;
	}

	my ($host, $user, $pass) = @parts;

	my $hm = gethostmask( $event->userhost );
	if(my $uid = main->userdb->getid( $hm )) {
		my $sql = "
			replace into mailcheck
				(userid, host, username, password, enabled)
			values
				(?, ?, ?, ?, NULL)
		";

		$dbh->do( $sql, undef,
				$uid, $host, $user, $pass
		) or die $dbh->errstr;

		main->qmsg( $chan,
				"Config saved. Please use " . main->trigger .
				"mail-enable to enable checking"
		);
	} else {
		main->qmsg( $chan, "Unable to find a user for you in the database." );
	}
}

sub mail_enable {
	my ($self, $event, $chan, $data, @to) = @_;

	my $hm = gethostmask( $event->userhost );
	
	if(my $uid = main->userdb->getid( $hm )) {
		my $sql = "select ifnull(enabled, 0) from mailcheck where userid = ?";
		my $sth = $dbh->prepare( $sql ) or die $dbh->errstr;
		$sth->execute( $uid ) or die $dbh->errstr;

		my $rows = $sth->rows;
		if(! $rows) {
			main->qmsg( $chan, "Unable to find a mailcheck entry for you " .
					"(use " . main->trigger . 'mail-config first)'
			);
		} else {
			my ($e) = $sth->fetchrow_array;
			main->debug("enabled: [$e]");
			unless($e) {
				# not enabled
				$dbh->do("
					update mailcheck set enabled = ? 
					where userid = ?
				", undef, $event->nick, $uid) or die $dbh->errstr;

				main->qmsg( $chan, "Mail check enabled for you, " .
							$event->nick );
			} else {
				main->qmsg( $chan, "Mail check already enabled for you, " .
							$event->nick );
			}
		}

		$sth->finish;
	} else {
		main->qmsg( $chan, "Unable to find a user for your hostmask" );
	}
}

sub mail_disable {
	my ($self, $event, $chan, $data, @to) = @_;

	my $hm = gethostmask( $event->userhost );
	
	if(my $uid = main->userdb->getid( $hm )) {
		my $sql = "select ifnull(enabled, 0) from mailcheck where userid = ?";
		my $sth = $dbh->prepare( $sql ) or die $dbh->errstr;
		$sth->execute( $uid ) or die $dbh->errstr;

		my $rows = $sth->rows;
		if(! $rows) {
			main->qmsg( $chan, "Unable to find a mailcheck entry for you " .
					"(use " . main->trigger . 'mail-config first)'
			);
		} else {
			my ($e) = $sth->fetchrow_array;
			main->debug("enabled: [$e]");
			if($e) {
				# enabled
				$dbh->do("
					update mailcheck set enabled = NULL 
					where userid = ?
				", undef, $uid) or die $dbh->errstr;

				main->qmsg( $chan, "Mail check disabled for you, " .
							$event->nick );
			} else {
				main->qmsg( $chan, "Mail check already disabled for you, " .
							$event->nick );
			}
		}
		$sth->finish;
	} else {
		main->qmsg( $chan, "Unable to find a user for your hostmask" );
	}
}

sub do_check { }

1;
__END__
