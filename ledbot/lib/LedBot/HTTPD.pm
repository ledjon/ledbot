package LedBot::HTTPD;

# VERY Simple HTTPD to run with ledbot

use strict;
use Socket;
use FindBin;
#use Config;
use DirHandle;
use Getopt::Std;
use HTTP::Daemon;
use HTTP::Status;
use Text::ParseWords;
use LedBot::Special qw(strftime);

# default port
use constant PORT => 2222;

my $dir = $FindBin::RealBin . '/htdocs';
my $OBJ = 0;
my %events = ( );

#$LedBot::HTTPD::usethread = 0;
$LedBot::HTTPD::DONE = 1;

#{
#	if(!$Config{'userthreads'}) {
#		$LedBot::HTTPD::usethread = 0;
#	} else {
#		local $SIG{'__DIE__'} = 'DEFAULT';
#		eval "use threads";
#		if($@) {
#			main->debug("Disabling threads");
#			$LedBot::HTTPD::usethread = 0;
#		} else {
#			eval "use threads::shared";
#		}
#	}
#}

#*main::httpd_event = \&httpd_ctl;

main->addcmd('httpd', \&handler);

sub handler {
	my ($self, $event, $chan, $data, @to) = @_;
	
	return unless main->can_access($event->userhost);
	
	return cmd($chan, $data);
}

sub httpd_ctl {
	my ($opt, $cmd, $action) = @_;
	
	if($opt eq 'del') {
		delete $events{$cmd};
	} else {
		ref($action) or die "Usage: httpd_ctl('add', 'cmd', \&foo)\n";
		
		$events{$cmd} = $action;
	}
}

# handle the whole command
sub cmd {
	my ($chan, $data) = @_;

	local @ARGV = shellwords($data);
	getopts('sp:', \my %opts);
	
	$data = shift @ARGV;
	
	if($opts{'s'}) {
		main->qmsg($chan, "httpd status: " . (ref($OBJ) ? 'Running ( '.$OBJ->url.' )' : 'Stopped'));
		return;
	}
	
	if($data eq 'start') {
		if($LedBot::HTTPD::DONE == 0 && ref($OBJ)) {
			main->qmsg($chan, "httpd already running (try -s to see the status)");
		} else {
			my $port = int($opts{'p'}) || PORT;
			LedBot::HTTPD->new($port);
			main->qmsg($chan, "httpd started ( " . $OBJ->url . " )");
		}
	} else {
		if($data eq 'stop') {
			$LedBot::HTTPD::DONE++;
			main->qmsg($chan, "Stopping httpd");
		} else {
			main->qmsg($chan, "Usage: httpd [-p <port>] start|stop");
		}
	}
}

sub new {
	my $proto = shift; # probably never use this
	my $port = shift || PORT;
	
	$LedBot::HTTPD::DONE = 0;
	
	# remove threading code
	#if($LedBot::HTTPD::usethread) {
	#	threads->new(\&daemon, $port, \&callback, \&done, \&shutdown);
	#} else {
		$OBJ = handle($port);
		if(main->daemon->add($OBJ, \&callback, \&done, \&shutdown)) {
			main->debug("URI: " . $OBJ->url);
		} else {
			main->debug("Unable to start httpd server!");
		}
	#}
	
	return $OBJ;
}

# for a threaded daemon
sub daemon {
	my ($port, $callback, $done, $shutdown) = @_;
	my $OBJ = handle($port);
	
	while (!$done->($OBJ)) {
		next unless my $c = $OBJ->accept;
		
		$callback->($c);
	}
	
	$shutdown->($OBJ);
	
	$LedBot::HTTPD::DONE = 0;
}

sub handle {
	my $d = HTTP::Daemon->new(LocalPort => shift(@_)) or die "Unable to get socket: $!\n";
	main->debug("Please contact me at: <URL:" . $d->url . ">");
	
	return $d;
}

sub callback {
	my $c = shift;
	
	main->debug("httpd callback!");
	# we only use one connection at a time
	if(my $r = $c->get_request) {
		if ($r->method eq 'GET') {
			my $path = $r->url->path;
			$path =~ s!^/+!!;
			$path =~ s!\.\./!!g;
			1 while($path =~ s#/$##);
			
			main->debug("Path is $path ($dir/$path)");
			
			if($path eq '/dynlib') {
				dynlib($c, $r);
				return;
			}
			
			if($path eq '' && -f $dir . '/index.html') {
				$path = $dir . '/index.html';
			} else {
				$path = $dir . '/' . $path;
				
				if(-d $path && -f $path . '/index.html') {
					main->debug("*** found index page!");
					$path .= '/index.html';
					main->debug("\t-> $path");
				}
			}

			# log the request
			eval {
				main->logevent(main->gethandle('httpd-access_log'),
					sprintf('%s "%s" "%s" %d',
						inet_ntoa((sockaddr_in($c->peername))[1]), 
						$r->url->path,
						$path,
						(-s $path)
					)
				);
			};

			$c->send_file_response($path);
		} else {
			$c->send_error(RC_FORBIDDEN)
		}
	}
	main->debug("finished callback!");
	$c->close;
	main->debug("returning!");
}

# clean shutdown of the socket
sub shutdown {
	my $sock = shift;

	main->debug("httpd server socket shutdown");

	$sock->shutdown(2);
	$sock->close;
	$OBJ = 0;
	
	main->debug("--- shutdown finished!");
}

sub done { $LedBot::HTTPD::DONE; }

sub dynlib {
#	main->debug(
}

# redefine this to an existing setting
sub HTTP::Daemon::ClientConn::send_dir {
	my($self, $path) = @_;

	main->debug("$path is a directory?: " . int(-d $path));

	$self->send_error(RC_NOT_FOUND) unless -d $path;

	my $reldir = $path;
	$reldir =~ s/^\Q$dir\E//;
	1 while($reldir =~ s#/$##);
    
	$self->send_basic_header;
	$self->print("Content-Type: text/html" . $/);
	$self->print($/);

	$self->print("<h2>Index of " . ($reldir || '/') . "</h2>");
	$self->print("<hr><pre>");
    
	my $d = DirHandle->new($path);
	while(my $file = $d->read) {
		next if $file eq '.';
		$file .= '/' if (-d $path . '/' . $file);
		my $link = '<a href="' . $reldir . '/' . $file . '">' .
				substr($file, 0, 30) . '</a>' .
				(' ' x (30 - length($file)));
		
		my ($size, $mtime) = (stat _)[7,9];
		$self->print($link . '  ' .
			strftime('%c', localtime($mtime)) .
			'  ' . $size . ' bytes' . $/
		);
	}
	$d->close;

	$self->print("</pre><hr>");
	$self->print("<i><a href='http://www.ledscripts.com'>LedBot Webserver Extension by LedScripts.com</a></i>");

	main->debug("finished sending directory!");

	return RC_OK;
}

1;
__END__
