#!/usr/bin/perl

# D(ynamic)LedBot!
# by Jon Coulter

use strict;
use FindBin qw($RealBin $RealScript);
use lib ($RealBin . '/lib');
use vars qw(%on_public %on_public_aliases);
use Net::IRC;
use POSIX qw(setsid);
use LedBot::Loop;
use LedBot::Special qw(:all);
use LedBot::VirtDaemon;
use LedBot::Events;
use LedBot::FifoEvent;
use LedBot::Users;
use LedBot::Timer;
use File::Copy;
use FileHandle;
use DirHandle;
use Storable;

# pid file
use constant PID_FILE => ($ENV{'HOME'} || (getpwuid($<))[7] ||
				'/var/run') . '/.ledbot.pid';

# readconf constant
use constant C_PER_LINE => 1;

# constants for the socket command
use constant BUFSIZE => 1024;
use constant TIMEOUT => 15;

my @nicks = qw(LedBot);

my $trigger = '.';
my $startup = time();
my $queuetime = 1;
my $lastqueue = time();
my $thisaction = undef;
my $nsid = 0;
my $pid = 0;
my @argv = @ARGV;
my %loads = ( );

my $logs = $RealBin . '/logs';
my $logarchive = $logs . '/archive';
my %FH = ( ); # filehandles stored here

# -f to not go into daemon mode (follow)
# -c /path/to/conf/dir -- conf dir path
# -s irc.foo.com -- irc server
# -p 6667 -- irc port
# -D -- turn on debugging
# -z -- allow everybody full access!
# -C -- running from cronjob
# -F -- remove pid file, if exists
getopts('DFfts:p:c:zC', \my %opts);

# -t -- test
if($opts{'t'}) {
	warn("Syntax OK\n");
	exit;
}

# -F flag
unlink(PID_FILE) if $opts{'F'};

# -C flag (not to be used with -F, of course)
exit if -f PID_FILE and $opts{'C'};

# main loop param
my $loop = LedBot::Loop->new;

# virtual daemon
my $daemon = LedBot::VirtDaemon->new;

# fifo loop
my $fifo = LedBot::FifoEvent->new;

# timer
my $timer = LedBot::Timer->new;

my $debug = ($opts{'D'} || $opts{'f'}) ? 1 : 0;

my $fullme = $RealBin.'/'.$RealScript;
my $me = $0;
$0 = $RealScript;
$0 =~ s|\.([^\.]+)$||;
chdir($RealBin);

my %config = (
	'basedir'	=> (defined $opts{'c'} ? $opts{'c'} : $RealBin .'/conf')
);

my %_config = ( );

my %dbms = (
	users		=> $RealBin . '/dbms/users',
	commands	=> $RealBin . '/dbms/commands'
);

my %bot = (
	nick		=> $nicks[0],
	ircname 	=> 'Ledjon Bot',
	username	=> 'LedjonsBot'
);

my %server = (
	server	=> $opts{'s'} || 'irc.gamesurge.net',
	port	=> $opts{'p'} || 6667,
);

# read in the config for the channels
my @chans = trim( readconf('chans.conf', C_PER_LINE) );

# array of queued messages
my @queue_messages = ( );

# array of queued adds
my %queued_users = ( );

# The info line
my $info_line = 'LedBot v1.29: http://www.ledscripts.com/';

# Setup the sig handlers
my $needhup = 0;

$SIG{'HUP'} = sub { $needhup++; };
# old method, now use fifo trigger
$SIG{'USR1'} = sub { debug("Use the rotate fifo instead of USR1 from now on!"); };
$SIG{'QUIT'} = $SIG{'INT'} = $SIG{'TERM'} = $SIG{'STOP'} = \&sig_die;
$SIG{'__DIE__'} = sub {
	my $d = $debug;
	$debug = 1;
	main->debug("Cought die signal: @_");
	$debug = $d;
};

debug("Attempting to fork and open filehandles, see you later!\n");

# pid stuff
{
	my $pid_fh = open_pid_file(PID_FILE);
	$pid = daemonize( );
	$pid_fh->print($pid);
	$pid_fh->close;
}

debug('My PID: ' . $$);

my $irc = Net::IRC->new;
$irc->debug(1) if $debug;
my $conn = timeout(10, sub {
			debug("going to connect to $server{server}");
			return $irc->newconn(
					Server		=> $server{'server'},
					Port		=> $server{'port'},
					Nick		=> $bot{'nick'},
					Ircname 	=> $bot{'ircname'},
					Username	=> $bot{'username'},
					LocalAddr	=> `/sbin/myip`
			) or die "Unable to connect to $server{server}!\n";
		}
	);

if($@) {
	if($@ =~ /Connect Timeout/i) {
		die "Connect timed out!\n";
	} else {
		die "Connection Error: $@\n";
	}
}

die "Unable to connect to $server{server}!\n" unless defined $conn;

debug("connected!\n");

# create our events handle
# do it right here, because this is right after connection is made
my $events = LedBot::Events->new( $conn );

# services get last shot at loading commands
debug("Loading services");
eval "use $_;" for LedBot::Special->load_services('./lib');

# defined $um real quick
my $um = &LedBot::UserManager::um;

##############
# Event subs #
##############

# New method here! set up all the on_public stuff into subs
{
	my %public = (
	'uptime'	=> sub {
		my ($self, $event, $chan, $data, @to) = @_; # <-- goes in all

		qmsg($chan, q{Uptime: } . timediff($startup, time()) . q{. (Started: } .
						strftime('%c', localtime($startup)) . ')');

		return;
	},
	'c2f' 		=> sub {
		my ($self, $event, $chan, $data, @to) = @_;

		my $f = (($data * 9) / 5) + 32;
		qmsg($chan, qq[$data C -> $f F]);

		return;
	},
	'f2c' 		=> sub {
		my ($self, $event, $chan, $data, @to) = @_;

		my $c = (($data - 32) * 5) / 9;

		qmsg($chan, qq[$data F -> $c C]);
	},
	'date'		=> sub {
		my ($self, $event, $chan, $data, @to) = @_; # <-- goes in all

		qmsg($chan, q"Today's Date is: " . strftime('%D', localtime()));

		return;
	},
	'datetime'	=> sub {
		my ($self, $event, $chan, $data, @to) = @_; # <-- goes in all

		qmsg($chan, strftime(
				(trim($data) || '%D @ %X'), localtime()
			)
		);

		return;
	},
	'restart' 	=> sub {
		my ($self, $event, $chan, $data, @to) = @_; # <-- goes in all

		if(can_access($event->userhost)) {
			my $reason = trim($data) || 'No Reason';

			debug("*** Restarting (".$event->userhost.")");
			qmsg($chan, "Restarting ($reason)");
			$self->quit($reason);

			if($data eq '--noargv') {
				@argv = ( );
			}

			sig_hup( );
		} else {
			$self->notice($event->nick, "You don't have access!");
		}

		return;
	},
	'chgtrig' 	=> sub {
		my ($self, $event, $chan, $data, @to) = @_; # <-- goes in all

		if(can_access($event->userhost)) {
			$trigger = trim($data);

			$trigger =~ s/\s/_/g;

			qmsg($chan, qq[Trigger is now '$trigger']);
		}
	},
	'eval'		=> sub {
		my ($self, $event, $chan, $data, @to) = @_; # <-- goes in all

		return unless can_access($event->userhost);

		debug("*** Evaling: $data");
		my $eval = eval $data;
		if(defined($eval)) {
			qmsg($chan, $eval);
		} else {
			qmsg($chan, "Cannot do evaluation: $data [$@]") if $@;
		}

		return 1;
	},
	'join'		=> sub {
		my ($self, $event, $chan, $data, @to) = @_; # <-- goes in all

		return unless can_access($event->userhost);

		my @joinchans = split(/ /, $data);

		# Pick out password chans
		for(my $i = 0; $i < @joinchans; $i++) {
			if($joinchans[$i] !~ /^#/ && $i != 0) {
				$joinchans[$i-1] .= ' '.$joinchans[$i];
			} else {
				if($joinchans[$i] !~ /^#/) {
					$joinchans[$i] = '#'.$joinchans[$i];
				}
			}
		}

		for (@joinchans) {
			# This takes care of my lazy no-splice stuff above
			next unless /^#/;
			if(joinchan($self, $_)) {
				debug("Joining Channel $_");
				push(@chans, $_);
			}
		}
	},
	'part'		=> sub {
		my ($self, $event, $chan, $data, @to) = @_; # <-- goes in all

		return unless can_access($event->userhost);

		if($data ne '') {
			for (split(/ /, $data)) {
				next if (trim($_) eq '');
				/^#/ or $_ = '#'.$_;
				partchan($self, $_);
			}
		} else {
			partchan($self, $chan);
		}
	},
	'sysuptime'	=> sub {
		my ($self, $event, $chan, $data, @to) = @_; # <-- goes in all

		qmsg($chan, qq{System Uptime: } . (`uptime`)[0]);
	},
	'nick'		=> sub {
		my ($self, $event, $chan, $data, @to) = @_; # <-- goes in all

		my $newnick = $data;

		if(can_access($event->userhost)) {
			debug("*** Changing nick to $newnick\n");
			#$self->nick($newnick);
			# abstracted for fifo use
			change_nick( $self, $newnick );
		} else {
			$self->notice($event->nick, "You don't have access to chage my nick!");
		}
	},
	'topic'		=> sub {
		my ($self, $event, $chan, $data, @to) = @_; # <-- goes in all

		my $in = $data;

		my ($tchan, $topic) = split(/ /, $in, 2);

		if($tchan !~ /^#/) {
			$topic = $tchan . ' ' . $topic;
			$tchan = $chan;
		}

		if(can_access($event->userhost)) {
			$self->topic($tchan, trim($topic));
		}
	},
	'about'		=> sub {
		my ($self, $event, $chan, $data, @to) = @_; # <-- goes in all

		qmsg($chan, $info_line);
	},
	'a2b' 		=> sub {
		my ($self, $event, $chan, $data, @to) = @_; # <-- goes in all

		return unless can_access($event->userhost);

		my $string;
		my @dat = split(//, $data);
		for (@dat) {
			chomp;
			$string .= unpack('B8', $_);
		}

		qmsg($chan, '[ ' . $string . ' ]');
	},
	'b2a' 		=> sub {
		my ($self, $event, $chan, $data, @to) = @_; # <-- goes in all

		return unless can_access($event->userhost);

		my $string;
		my $return = $data;

		$return =~ s/([01]{8})/pack('B8', $1)/ge;

		$return =~ s/\r//ig;
		$return =~ s/\n/ /ig;

		qmsg($chan, '[ ' . $return . ' ]');
	},
	'h2a' 		=> sub {
		my ($self, $event, $chan, $data, @to) = @_; # <-- goes in all

		return unless can_access($event->userhost);										
		my $string = $data;
		   $string =~ s/(..)/pack("H2", $1)/ige;

		   $string =~ s/[\r\n]//ig;

		qmsg($chan, '[ ' . $string . ' ]');
	},
	'a2h' 		=> sub {
		my ($self, $event, $chan, $data, @to) = @_; # <-- goes in all

		return unless can_access($event->userhost);										
		my $string = $data;
		   $string =~ s/(.)/unpack("H2", $1)/ige;

		   $string =~ s/[\r\n]//ig;

		qmsg($chan, '[ ' . $string . ' ]');
	},
	'ledop'		=> sub {
		my ($self, $event, $chan, $data, @to) = @_; # <-- goes in all

		return unless can_access($event->userhost);

		my $nicks = $data || $event->nick;
		my @ops = split(/\s+/, $nicks);
		my $opcount = scalar @ops;

		my $needoped = join(' ', @ops); 

		my $opstring = '+';
		   $opstring .= ('o' x $opcount);

		$self->mode($chan, $opstring, $needoped);
	},
	'leddeop' 	=> sub {
		my ($self, $event, $chan, $data, @to) = @_; # <-- goes in all

		return unless can_access($event->userhost);

		my $nicks = $data;
		my @ops = split(/ /, $nicks);
		my $opcount = scalar @ops;

		my $needoped = join(' ', @ops); 

		my $opstring = '-';
		   $opstring .= ('o' x $opcount);

		$self->mode($chan, $opstring, $needoped);
	},
	'die' 		=> sub {
		my ($self, $event, $chan, $data, @to) = @_; # <-- goes in all

		return unless can_access($event->userhost);

		my $reason = $data || 'No Reason';

		if(can_access($event->userhost)) {
			debug("*** Quitting (".$event->userhost.")");
			$self->quit($reason);

			exit 0;
		} else {
			$self->notice($event->nick, "You don't have access!");
		}
	},
	'uname'		=> sub { 
		my ($self, $event, $chan, $data, @to) = @_;

		qmsg($chan, trim((`uname -a`)[0]));
	},
	'listfunctions'	=> sub {
		my ($self, $event, $chan, $data, @to) = @_;

		my @cmds = sort {$a cmp $b} keys %on_public;

		qmsg($chan, '[' . scalar @cmds . ' commands]');

		for(my $i = 0; $i < @cmds; $i += 10) {
			my $top = ($i + 10 > (scalar @cmds) - 1) ? (scalar @cmds - 1) : $i + 10;
			qmsg($chan, join(', ', @cmds[$i..($top - 1)]));
		}
	},
	'stats'		=> sub {
		my ($self, $event, $chan, $data, @to) = @_;

		my $stats = trim(`ps -p$$ -opid,user,group,pcpu,pmem,vsize,nice,time,tty,args, | grep -v PID`);

		my ($pid, $user, $group, $cpu, $mem, $vsize,
			$ni, $time, $tt, $command)
				= split(/\s+/, $stats, 8);

		qmsg($chan,
			qq{My Stats: [Memory: $mem% (} .
				addcommas($vsize) .
			qq{ kbytes)] [CPU: $cpu] [User: $user] [PID: $pid]}
		);
	},
	'addcommand'	=> sub {
		my ($self, $event, $chan, $data, @to) = @_;

		return unless can_access($event->userhost);

		my $commands = retrieve($dbms{'commands'});

		my ($command, $data) = split(/\s+/, $data, 2);

		$data =~ s/\r//g;										
		if(ref $commands) {
			# see if we have that command already
			if(defined $commands->{$command}) {
				qmsg($chan, qq([$command] already exists! Use ) .
					$trigger .
					qq(readdcommand to overwrite the current one!)
				);

				return;
			}

			# do it
			eval {
				$commands->{$command} = $data;

				store($commands, $dbms{'commands'});
			};

			if($@) {
				qmsg($chan, q[Error adding \[] . $command . ']:' . join(' ', split(/\n/, $@)));
			} else {
				qmsg($chan, qq([$command] successfully added!));

				rehash_commands($chan);
			}
		} else {
			qmsg($chan, q[$commands not defined!]);
		}
	},
	'readdcommand'	=> sub {
		my ($self, $event, $chan, $data, @to) = @_;

		return unless can_access($event->userhost);

		my $commands = retrieve($dbms{'commands'});

		my ($command, $data) = split(/\s+/, $data, 2);

		if(ref $commands) {
			unless(defined $commands->{$command}) {
				qmsg($chan, qq([$command] does not exist.));

				return;
			}

			# do it
			eval {
				$commands->{$command} = $data;

				store($commands, $dbms{'commands'});
			};

			if($@) {
				qmsg($chan, q[Error adding \[] . $command . ']:' . join(' ', split(/\n/, $@)));
			} else {
				qmsg($chan, qq([$command] successfully added!));

				rehash_commands($chan);
			}
		} else {
			qmsg($chan, "$commands not defined!");
		}
	},
	'delcommand'	=> sub {
		my ($self, $event, $chan, $data, @to) = @_;

		return unless can_access($event->userhost);

		my $commands = retrieve($dbms{'commands'});

		my ($command, $data) = split(/\s+/, $data, 2);

		if(ref $commands) {
			unless(defined $commands->{$command}) {
				qmsg($chan, qq([$command] does not exist.));

				return;
			} else {
				delete $commands->{$command};
				delete $on_public{$command};

				store($commands, $dbms{'commands'});
				qmsg($chan, qq([$command] deleted!));

				rehash_commands($chan);
			}
		} else {
			qmsg($chan, q[$commands not defined!]);
		}
	},
	'socket'	=> sub {
		my ($self, $event, $chan, $data, @to) = @_;

		return unless can_access($event->userhost);

		require IO::Socket;

		my %opts = ();										
		local @ARGV = shellwords($data);

		getopts('h:p:d:', \%opts);

		for (qw/h p d/) {
			unless($opts{$_}) {
				qmsg($chan, "Usage: $trigger" . "socket -h <host> -p <port> -d <data>");

				return;
			}
		}

		my $return = timeout(TIMEOUT, sub {
				my $sock = IO::Socket::INET->new("$opts{h}:$opts{p}");
				if(defined $sock) {
					syswrite($sock, $opts{d});
					sysread($sock, my $return, BUFSIZE);

					return $return;
				} else {
					qmsg($chan, "Unable to make socket connetion: $@");

					return;
				}
			}
		);

		qmsg($chan, "Socket Returned: $return") if $return;

		if($@) {
			qmsg($chan, "Socket Connction error or proccessing took longer then " . TIMEOUT . " seconds. [$@]");
		}
	},
	'adduser' 	=> sub {
		my ($self, $event, $chan, $data, @to) = @_;

		return unless can_access($event->userhost);

		my ($user, $mask, @commands) = split(/\s+/, $data);

		if($mask !~ /^\*\!\*.+/) {
			push(@commands, $mask);

			$um->queue( $user, $um->ref('add'),
				{
					'inchan'	=> $chan,
					'commands'	=> [@commands]
				}
			);
		} else {
			my $uid = userdb->adduser( $user, $mask, 0 );
			userdb->give_access( $uid, @commands );

			qmsg($chan, "$user added!");
		}

		return 1;
	},
	'deluser' 	=> sub {
		my ($self, $event, $chan, $data, @to) = @_;

		return unless can_access($event->userhost);

		my ($user, $mask, @nothing) = split(/ /, $data);

		if($user =~ /\@/) {
			$mask = ($user =~ /\*\!\*/) ? $mask : lc(gethostmask($user));

			if(my $uid = userdb->getid( $mask )) {
				#delete $users{$mask};
				userdb->deluser( $mask );
				qmsg($chan, "$user ($mask) deleted!");
			} else {
				qmsg($chan, "Unable to find user with mask: $mask");
			}

			return;
		} else {
			if(userdb->deluser_bynick( $user ) >= 1) {
				qmsg($chan, "$user (all instances of) deleted!");
				return;
			}
		}

		$um->queue( $user, $um->ref('del'),
			{
				'inchan'	=> $chan,
			}
		);

		return 1;
	},
	'addmask'	=> sub {
		my ($self, $event, $chan, $data, @to) = @_;
		
		my ($nick, $mask) = split(/\s+/, $data, 2);

		if($mask) {
			return unless can_access($event->userhost);
			$mask = gethostmask( $mask ) unless $mask =~ /\*/;

			if(my $uid = userdb->nick2id($nick)) {
				userdb->add_hostmask( $uid, $mask );
				qmsg($chan, "Added $mask to " . $nick . "'s list of hostmasks.");
			} else {
				qmsg($chan, "Unable to find uid for `$nick'");
			}
		} else {
			unless($nick) {
				qmsg($chan, "You need to specify the new hostmask!");
				return;
			}
			$mask = ($nick =~ /\*/ ? $nick : gethostmask( $nick ));

			if(my $uid = userdb->getid( gethostmask( $event->userhost ) )) {
				userdb->add_hostmask( $uid, $mask );
				qmsg($chan, "Added $mask to your list of hostmasks.");
			} else {
				qmsg($chan, "Unable to find any data for you.");
			}
		}
	},
	'delmask'	=> sub {
		my ($self, $event, $chan, $data, @to) = @_;
		
		my ($nick, $mask) = split(/\s+/, $data, 2);

		if($mask) {
			return unless can_access($event->userhost);
			$mask = gethostmask( $mask ) unless $mask =~ /\*/;

			if(my $uid = userdb->nick2id($nick)) {
				userdb->del_hostmask( $uid, $mask );
				qmsg($chan, "Removed $mask from " . $nick . "'s list of hostmasks.");
			} else {
				qmsg($chan, "Unable to find uid for `$nick'");
			}
		} else {
			unless($nick) {
				qmsg($chan, "You need to specify the hostmask to delete!");
				return;
			}
			$mask = ($nick =~ /\*/ ? $nick : gethostmask( $nick ));

			if(my $uid = userdb->getid( gethostmask( $event->userhost ) )) {
				userdb->del_hostmask( $uid, $mask);
				qmsg($chan, "Delete $mask from your list of hostmasks.");
			} else {
				qmsg($chan, "Unable to find any data for you.");
			}
		}
	},
	'usercommands'	=> sub {
		my ($self, $event, $chan, $data, @to) = @_;

		return unless can_access($event->userhost);

		for my $user (split(/\s+/, $data)) {
			if(my $uid = userdb->nick2id( $user )) {
				qmsg($chan,
					sprintf("Commands for user %s: %s",
							$user, 
							(join(' ', userdb->which_commands( $uid )) || '[ None ]')
					)
				);
			} else {
				qmsg($chan, "No data found for `$user'");
			}
		}

		return 1;
	},
	'useraddcommand'	=> sub {
		my ($self, $event, $chan, $data, @to) = @_;

		return unless can_access($event->userhost);

		my ($user, @commands) = split(/ /, $data);

		$um->queue( $user, $um->ref('addcmd'),
			{
				'inchan'	=> $chan,
				'commands'	=> [@commands]
			}
		);

		return 1;
	},
	'userdelcommand'	=> sub {
		my ($self, $event, $chan, $data, @to) = @_;

		return unless can_access($event->userhost);

		my ($user, @commands) = split(/ /, $data);

		$um->queue( $user, $um->ref('delcmd'),
			{
				'inchan'	=> $chan,
				'commands'	=> [@commands]
			}
		);

		return 1;
	}
	);
			 
	my %public_aliases	= (
		'utime' 	=> 'uptime',
		'calc'		=> 'eval',
		'rehash'	=> 'restart',
		'lbrestart'	=> 'restart',
		'changetrigger'	=> 'chgtrig',
		'changetrig'	=> 'chgtrig',
		'datetime:' 	=> 'datetime',
		'op'		=> 'ledop',
		'deop'		=> 'leddeop',
		'addcmd'	=> 'addcommand',
		'delcmd'	=> 'delcommand',
		'readdcmd'	=> 'readdcommand',
		'uaddcmd'	=> 'useraddcommand',
		'udelcmd'	=> 'userdelcommand',
		'ucmds'		=> 'usercommands'
	);

	$on_public{$_} = $public{$_} for(keys %public);
	$on_public_aliases{$_} = $public_aliases{$_} for keys(%public_aliases);
}
# }}} #

# reload the user commands
rehash_commands( );

###############################################################
sub rehash_commands {
	my ($chan, $commands) = @_;

	$commands ||= retrieve($dbms{'commands'});
	 
	for my $key (keys %{$commands}) {
			my $row = {
				name => $key,
				data => $commands->{$key}
			};

			debug($row->{name} . ' being added');
			eval(q[$on_public{'].$row->{name}.q['}
					= sub { my ($self, $event, $chan, $data, @to) = @_; ]. $row->{data} .q[};]);

			if($@) {
				qmsg($chan, "Error adding command [$row->{name}]: " . $@) if $chan;
				debug("Unable to load Function: $row->{name} | Reason: $@");
			} else {
				debug($row->{'name'}, ' added!');
			}
	}
	 
	return 1;
}

# this returns the $daemon handle
sub daemon { $daemon; }
# loop
sub loop { $loop; }
# just return the $fifo handle
sub fifo { $fifo; }
# timer
sub timer { $timer; }

# what do we do on connection?
sub on_connect {
	my $self = shift;

	for (@chans) {
		chomp;
		# Clean the clannel
		my $chan = (/^#/) ? $_ : '#'.$_;
		
		debug("Joining $chan...");
		joinchan($self, $chan);
	}
	
	return 1;
}

# Reconnect to the server when we die.
sub on_disconnect {
	my ($self, $event) = @_;
	
	if($event->dump =~ /throttle/) {
		sleep 15;
	}
	
	sig_hup( );
}

sub on_join {
	my ($self, $event) = @_;
	my ($chan) = ($event->to)[0];

	if($chan !~ /^#/) {
		if($chan =~ /(.+)!~([^\@]+)@.*/) {
			$chan = $1;
		} else {
			# not a real channel
			return;
		}
	}
	
	debug(sprintf("*** %s (%s) has joined channel %s", 
			$event->nick, $event->userhost, $chan));

	logevent(gethandle($chan), sprintf("*** %s (%s) has joined channel",
			$event->nick, $event->userhost));

	my $mask = lc gethostmask($event->userhost);

	if(my $uid = userdb->getid( $mask )) {
		if(userdb->is_god( $mask )) {
			$self->mode($chan, '+o', $event->nick);
		}
	}
}


# What to do when someone leaves a channel the bot is on.
sub on_part {
	my ($self, $event) = @_;
	my ($channel) = ($event->to)[0];

	debug(sprintf("*** %s has left channel %s", $event->nick, $channel));
	
	logevent(gethandle($channel),
			sprintf("*** %s has left channel [%s]", $event->nick, $channel)
	) if $channel =~ /^#/;
	
	return 1;
}

# Change our nick if someone stole it.
sub on_nick_taken {
	my ($self) = shift;

	$self->nick(substr($self->nick, -1) . substr($self->nick, 0, 8));
}

# Look at the topic for a channel you join.
sub on_topic {
	my ($self, $event) = @_;
	my @args = $event->args;

	my $in = {};

	if($event->format eq 'server') {
		$in = {
			'channel'	=> $args[1],
			'topic'		=> $args[2]
		};
	} else {
		$in = {
			'channel'	=> $event->to,
			'topic'		=> $args[0]
		};
	}

	return if $event->type eq 'notopic';

	debug(sprintf("Topic for %s is now '%s'", @{$in}{qw(channel topic)}));
}

# Display formatted CTCP ACTIONs.
sub on_action {
	my ($self, $event) = @_;
	my ($nick, @args) = ($event->nick, $event->args);

	debug("* $nick @args");
}

# What to do when we receive a private PRIVMSG.
sub on_msg {
	my ($self, $event) = @_;
	my ($nick) = $event->nick;
	
	debug("*** $nick *** ", ($event->args), ' ', $event->from);
	
	on_public(@_, $nick);
}

# Handles some messages you get when you connect
sub on_init {
	my ($self, $event) = @_;
	my (@args) = ($event->args);
	shift (@args);
	
	debug("*** @args");
}

# Yells about incoming CTCP PINGs.
sub on_ping {
	my ($self, $event) = @_;
	my $nick = $event->nick;

	$self->ctcp_reply($nick, join (' ', ($event->args)));
	debug("*** CTCP PING request from $nick received");
}

# Gives lag results for outgoing PINGs.
sub on_ping_reply {
	my ($self, $event) = @_;
	my ($args) = ($event->args)[1];
	my ($nick) = $event->nick;

	$args = time - $args;
	debug("*** CTCP PING reply from $nick: $args sec.");
}

# What to do when we receive channel text.
sub on_public {
	my $self = shift;
	my $event = shift;
	my @to = $event->to;
	my $chan = shift || shift @to;
	my ($nick, $mynick) = ($event->nick, $self->nick);
	my ($arg) = ($event->args);

	# Note that $event->to() returns a list (or arrayref, in scalar
	# context) of the message's recipients, since there can easily be
	# more than one.
	
	logevent(gethandle($chan), "[-> $chan] <$nick> $arg");

	# cleanup unneeded codes (a little)
	$arg =~ s/\003(1[0-5]|\d)(,(1[0-5]|\d))?//g;
	$arg =~ s/[\2\3]//g;
	
	if(substr($arg, 0, length($trigger)) eq $trigger) {
		my @params = split(/ /, $arg);
		my $action = trim(substr($arg, length($trigger), (length(shift(@params)) - length($trigger))));
		
		my $data = join(' ', @params);
		
		# Alaises
		if(defined($on_public_aliases{$action}) && !defined($on_public{$action})) {
			$action = $on_public_aliases{$action};
		}
		
		if(defined($on_public{$action})) {
			$thisaction = $action;
			eval {
				$on_public{$action}->($self, $event, $chan, trim($data), @to);
			};
			$thisaction = undef;
			
			if($@) {
				qmsg($chan, "$action failed: " . join(' ', split(/\n/, $@)));
			}
		}
	}
	
	return 1;
}

############
# Misc Subs
############
sub can_access {
	return 1 if $opts{'z'};
	@_ = self_or_default(@_);
	my $host = shift;
	my $action = shift || $thisaction;
	
	debug("*** Checking host ($host)...");
	
	my $tmask = lc(gethostmask($host));
	
	return 1 if userdb->can_access( $tmask, $action );
	
	debug("$host ($tmask) tried to access [$action] (but I stopped (him|her)!)\n");
	
	return 0;
}

# hup sig
sub sig_hup {
	my $scriptself = $fullme;

	end_routine();

	$conn->quit("Restart... I Hope");

	# close connections/handles
	$irc = undef;
	$conn = undef;

	if(-x $scriptself) {
		exec($scriptself, @argv);
	} else {
		exec($^X, $scriptself, @argv);
	}

	die "Unable to restart ($!)!\n";

	# shouldn't make it this far!
	return 1;
}

# die sig
sub sig_die {
	my $sig = shift;
	
	debug("Sent $sig, quitting.");
	
	exit 0;
}

sub nothing {
	my($self, $event) = @_;
	
	debug($event->dump);
	
	return 1;
}

# queue messages
*queuemessage = \&qmsg;
sub qmsg {
	@_ = self_or_default(@_);
	my $chan = shift;

	# now allow for multiple que's in one send
	while(my $msg = shift @_) {
		push(@queue_messages, [$chan, $msg]);
	}
	
	return 1;
}

# do a queue. Usually just called in the main loop
sub doqueue {
	my ($chan, $msg) = self_or_default(@_);
	
	$conn->privmsg($chan, $msg);
	logevent(gethandle($chan), "[<- $chan] <-self-> $msg");
	
	return 1;
}

# this allows for logging
sub joinchan {
	@_ = self_or_default(@_);
	my ($self, $chan) = @_;

	if($self->join($chan)) {
		($chan) = split(/\s+/, $chan);
		my $name = $chan;
		$name =~ s/[#\s]//g;
		
		# add fifo event
		fifo->add('talk_to_' . $name =>
			sub {
				for(split(/\n/, trim(shift))) {
					qmsg($chan, trim($_))
				} 
			}
		); 
		
		return logevent(gethandle($chan), "<--- Joined $chan");
	} else {
		return 0;
	}
}

sub partchan {
	@_ = self_or_default(@_);
	my ($self, $chan) = @_;
	
	if($self->part($chan)) {
		my $handle = gethandle($chan);
		logevent($handle, "<--- Parted $chan");
		closehandle($handle);

		$chan =~ s/[#\s]//g;
		fifo->remove( 'talk_to_' . $chan );
		
		return 1;
	} else {
		return 0;
	}
}

# more irc - specific things
sub change_nick {
	@_ = self_or_default( @_ );
	my ($self, $nick) = @_;

	$self->nick( $nick );
}

# fifi events!
sub _fifo_nick {
	# data comes before $self, because
	# '$self' is a callback extra var here
	my ($data, $self) = @_;

	($data) = split(/\s+/, trim( $data ));
	
	change_nick( $self, $data );
}

# send raw data to channel
sub _fifo_raw {
	my ($data, $self) = @_;

	$self->sl(trim( $data ));
}

# add a user 
sub _fifo_adduser {
	my ($data, $self) = @_;

	my ($nick, $hm, @c) = split(/\s+/, trim( $data ));

	my $hostmask = ($hm =~ /\*/ ? $hm : gethostmask( $hm )) or return;

	if(my $uid = userdb->nick2id( $nick )) {
		userdb->add_hostmask( $uid, $hostmask );
	} else {
		if(my $uid = userdb->adduser( $nick, $hostmask, 0 )) {
			userdb->give_access( $uid, @c );
		}
	}
}

sub gethandle {
	@_ = self_or_default(@_);
	my $handle = lc(shift @_);
	$handle =~ s/^(\S+) .*$/$1/g;

	my $file = $logs.'/'.$handle.'.log';
	
	unless(defined $FH{$handle} and fileno($FH{$handle})) {
		debug("Going to open a log for [$handle]");
		$FH{$handle} = FileHandle->new($file, (-f $file ? 'a' : 'w')) or die $!;
		$FH{$handle}->autoflush(1);
		
		logevent($FH{$handle}, "<--- event handle for [$handle] opened");
	}
	
	return $FH{$handle};
}

# close a filehandle
sub closehandle($) {
	return eval { shift->close };
}

sub logevent {
	@_ = self_or_default(@_);
	my ($handle, $event) = @_;
	
	$event =~ s/\r//g;
	$event =~ s/\n/<:newline:>/g;
	$event =~ s/\003(1[0-5]|\d)(,(1[0-5]|\d))?//g;
	
	# make sure we have a filehandle
	$handle = gethandle($handle) unless fileno($handle);
	
	my $date = strftime('%D@%X', localtime( ));
	
	return $handle->print('['.$date.'] '.$event . "\n");
}

sub readconf {
	@_ = self_or_default(@_);
	my $file = shift;
	my $flags = shift;
	$file = $config{'basedir'} . '/' . $file unless -f $file;
	
	return unless -f $file;
	
	my $fh = FileHandle->new($file) or die "Unable to read config file: $file : $!\n";
		if($flags & C_PER_LINE) {
			# read all lines
			return $fh->getlines;
		} else {
			while(<$fh>) {
				next if /^#/ || trim($_) eq '';
				my ($name, $value) = split(/\s+/, $_, 2);
				$_config{$name} = $value;
			}
		}
	$fh->close if $fh;
	
	return 1;
}

sub self_or_default {
	shift @_ while($_[0] eq __PACKAGE__);
	return @_;
}

sub config {
	return @_ > 1 ?
		$_config{shift()} = shift()
		: $_config{shift()};
}

sub getcwd { $RealBin }

sub debug {
	@_ = self_or_default(@_);
	return unless $debug;
	
	warn(join("\n", map { localtime(time) . ": " . $_ } @_) . "\n");
}

sub open_pid_file($) {
	my $file = shift;

	if(-e $file) {
		warn("File $file exists!");
		my $fh = FileHandle->new($file);
		my $pid = <$fh>;
		chomp($pid);

		if($pid) {
			if(kill 0 => $pid) {
				die "Kill server with PID: $pid\n";
			} else {
				die "PID File Exists. Recommend deleting $file. (exiting) (use -F)\n";
			}
		}
	}

	unlink($file) if -f $file;
	
	my $fh = FileHandle->new($file, O_WRONLY|O_CREAT|O_EXCL, 0644)
		or die "Can't create $file: $!\n";
	
	return $fh;
}

sub daemonize {
	# Daemonize
	unless($opts{'f'}) {
		die "Unable to fork.\n" unless defined(my $pid = fork());
		if($pid) {
			debug('Forked PID: '.$pid);
			exit 0;
		}

		## Adding logging, so it doesn't print to the screen
		##	Forget about old logs. they're not important yet
		close(STDOUT); close(STDERR);
		unless( open(STDOUT, '>>'.getcwd().'/ledbot.log') && open(STDERR, '>>'.getcwd().'/ledbot.log') ) {
			debug('Unable to open output file, going on...');
		}

		$nsid = setsid();
	}

	umask(022);

	# flush the buffers
	$| = 1;
	select((select(STDERR), $|=1)[0]);

	return $$;
}

sub rotate_logs {
	debug("Rotating logs at " . scalar localtime( ));
	
	mkpath($logarchive, 0, 0777) unless -d $logarchive;
	
	# close all open files
	map { closehandle($FH{$_}); delete $FH{$_}; } keys %FH;
	
	my $d = DirHandle->new($logs) or return;
	for my $file ($d->read) {
		my $path = $logs . '/' . $file;
		next if $file =~ /^\./;
		next if -d $path;
		
		my $backup = $logarchive . '/' . $file;
		my $i = 1;
		
		# get a unique name
		++$i while(-f $backup . '.' . $i);
		$backup .= '.' . $i;
		
		move($path, $backup);
	}
	# handles re-open as needed
	
	debug("Finished rotating logs!");
}

# register a new action
sub addcmd {
	@_ = self_or_default(@_);
	my $cmd = shift;
	my $code = shift;
	
	debug("adding $cmd to on_public from: " . caller);
	
	$on_public{$cmd} = $code;
	
	# rest have to be aliases
	$on_public_aliases{$_} = $cmd for(@_);
}

# timeout an action
sub time_trap {
	return timeout( self_or_default( @_ ) );
}

sub conn { $conn }
sub events { $events }
sub users { die "You need to use userdb() now, fool!\n" }
sub checkload { $loads{caller( )}->{shift @_}++; }

sub trigger {
	@_ = self_or_default(@_);
	my $ret = $trigger;
	$trigger = shift || $trigger;
	return $ret;
}

sub end_routine {
	if($$ == $pid) {
		fifo->DESTROY();
		unlink PID_FILE;
	}
}

END {
	end_routine( );
}

### Rewritten or fixed Net::IRC subs

# fix net::irc::start to allow proper hup
# and queues
# and now virtual daemoning
#sub Net::IRC::start {

# irc loop event
sub irc_loop {
	my $self = shift;
	
	sig_hup( ) if $needhup;
		
	unless($conn->connected) {
		sleep(5);
		sig_hup( );
	}
		
	$self->do_one_loop;
		
	if(scalar @queue_messages > 0) {
		if((time( ) - $queuetime) >= $lastqueue) {
			my $queue = shift @queue_messages;

			$lastqueue = time( ) if doqueue( @{$queue} );
		}
	}
}

# should get passed $daemon
sub daemon_loop {
	shift->loop;
}

sub fifo_check {
	shift->trigger;
}

sub timer_check {
	shift->trigger;
}

#############
# Define Events
#############
debug("Defining Events.... ");

# these are events triggered by $irc events
events->add(
	'public'	=> [\&on_public, 1],
	[qw(part quit)]	=> \&on_part,
	'caction'	=> \&on_action,
	'msg'		=> \&on_msg,
	'cping'		=> \&on_ping,
	'crping'	=> \&on_ping_reply,
	'topic'		=> \&on_topic,
	'311'		=> \&on_whois_reply,
	[251..254, 302]	=> \&on_init,
	[255]		=> \&on_connect,
	'433'		=> \&on_nick_taken,
	'join'		=> \&on_join,
	'disconnect'	=> \&on_disconnect,
	[qw(
	cerrmsg caction
	cerror other
	version
	)]		=> \&nothing
);
debug(" done.");

debug("Registering fifo events");
fifo->add( 'rotate_logs', \&rotate_logs );
fifo->add( 'nick' => \&_fifo_nick, $conn );
fifo->add( 'raw' => \&_fifo_raw, $conn );
fifo->add( 'joinchan' => sub { joinchan( pop, trim( shift ) ) }, $conn );
fifo->add( 'partchan' => sub { partchan( pop, trim( shift ) ) }, $conn );
fifo->add( 'adduser' => \&_fifo_adduser, $conn );
fifo->add( 'exit' => sub { exit; });
fifo->add( 'restart' => sub { $needhup++ });
debug(" done.");

# add things to the bot
# these are top-level event loop
loop->add(
	\&irc_loop 	=> [$irc],
	\&daemon_loop	=> [$daemon],
	\&fifo_check	=> [$fifo],
	\&timer_check	=> [$timer]
);

# add our timer now
# ask for version info every 2 minutes
timer->add('connnect_check', 120, sub { main->conn->sl('version'); });

debug("Starting Bot.");

# go now
while(1) {
	last if loop->loop == -1;
}

1;
__END__
