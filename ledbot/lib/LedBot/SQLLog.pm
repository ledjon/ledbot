package LedBot::SQLLog;

# log channel text to an sqlite database
# by Jon Coulter

use strict;
use LedBot::Special qw(:sql);

my %schema = (
	'channels'	=> "
			create table {table} (
				chanid integer primary key,
				channame
			)
	",
	'text'		=> "
			create table {table} (
				lineid integer primary key,
				chanid,
				time,
				user,
				hostmask,
				message
			)
	",
	'topics'	=> "
			create table {table} (
				topicid integer primary key,
				chanid,
				time,
				user,
				hostmask,
				topic
			)
	"
);

# do it now
sql_create( my $dbh = sql_handle('chanlogs'), %schema )
	or die "Unable to get handle or create schema\n";

# often-used queries 
my $chanselect = $dbh->prepare("select chanid from channels where channame = ?") or die $dbh->errstr;
my $newtopic = $dbh->prepare("insert into topics (chanid, time, user, hostmask, topic) values (?, ?, ?, ?, ?)") or die $dbh->errstr;
my $newtext = $dbh->prepare("insert into text (chanid, time, user, hostmask, message) values (?, ?, ?, ?, ?)") or die $dbh->errstr;

main->events->add(
	'topic'		=> \&on_topic,
	'public'	=> \&on_public,
) unless main->checkload('package-events');

main->addcmd('logsql-raw', \&sql_raw);

*main::logsql = \&dbh;
sub dbh { $dbh }

sub on_topic {
	my ($self, $event) = @_;

	return if $event->type eq 'notopic';

	my @args = $event->args;
	my ($chan, $topic) = ($event->format eq 'server' ? (@args[1,2]) : (($event->to)[0], $args[0]));
	my $chanid = getchanid( getchan($event) );

	$newtopic->execute($chanid, time( ), $event->nick, $event->userhost, $topic) or die $dbh->errstr;
}

sub on_public {
	my ($self, $event) = @_;

	my $chanid = getchanid( getchan($event) );
	my $text = ($event->args)[0];

	# cleanup unneeded codes (a little)
	$text =~ s/\003(1[0-5]|\d)(,(1[0-5]|\d))?//g;
	$text =~ s/[\2\3]//g;

	$newtext->execute($chanid, time( ), $event->nick, $event->userhost, $text) or die $dbh->errstr;
}

sub sql_raw {
	my ($self, $event, $chan, $data, @to) = @_;
	
	return unless main->can_access($event->userhost);
	
	my $sth = $dbh->prepare($data);
	$sth->execute or die $dbh->errstr;
	
	my $i = 0;
	while(my @row = $sth->fetchrow_array) {
		main->qmsg($chan, (join(', ', @row) || 'No Results'));
		
		if(++$i > 15) {
			main->qmsg($chan, "I'm only going to dispaly 15 rows, stopping");
			last;
		}
	}
	
	main->qmsg($chan, "No row results") unless $i;
}

sub getchan {
	return (shift->to)[0];
}

sub getchanid {
	my $chan = shift or return;

	my $ret = $chanselect->execute($chan) or die $dbh->errstr;

	if($ret =~ /^\d+$/) {
		my $row = $chanselect->fetchrow_hashref;

		return ($row->{'chanid'} || 0);
	} else {
		$dbh->do("replace into channels (channame) values (?)", undef, $chan) or die $dbh->errstr;

		return ($dbh->func('last_insert_rowid') || 0);
	}
}

1;
__END__
