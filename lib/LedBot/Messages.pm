package LedBot::Messages;

# ledbot message keeper
use strict;
use LedBot::Special qw(getrange strftime gethostmask);
use Storable;

my $file = './dbms/messages';
#my $users = \%main::users;

# add our handlers
main->addcmd('msg-add', \&msg_add);
main->addcmd('mymessages', \&mymessages, 'msgs', 'mymsgs', 'mymsg');
main->addcmd('msg-rem', \&msg_rem, 'msg-remove', 'msg-del', 'msg-delete');
main->addcmd('mymessages-clear', \&mymessages_clear);
#main->addcmd('mymesssages-search', \&mymessages_search);

# special on_join action
main->events->add('join', \&on_join) unless main->checkload('join');

sub msg_add {
	my ($self, $event, $chan, $data, @to) = @_;
	
	my ($tochan, $to, $msg) = split(/\s+/, $data, 3);
	
	if($tochan !~ /^#/) {
		$msg = join(' ', ($to, $msg));
		$to = $tochan;
		$tochan = $chan;
	}
	
	$to = lc($to);
	$msg =~ s/^\s+//;
	
	if(!$to or !$msg) {
		main->qmsg($chan, "Usage: " . main->trigger . "msg-add [#channel] <nick> <message text here..>");
		return;
	}

	if(!user_exists($to)) {
		main->qmsg($chan, "No such user ($to)");
		return;
	}
	
	my $items = getmessages( );
	
	$items->{$to} ||= [];
	push(@{$items->{$to}},
		{
			'from'	=> $event->nick,
			'msg'	=> $msg,
			'chan'	=> $tochan,
			'time'	=> time
		}
	);
	
	#FileHandle->new('./tmp.out', 'w')->print(Dumper($items));
	savemessages($items);
	
	main->qmsg($chan, "Message Saved");
}

sub mymessages {
	my ($self, $event, $chan, $data, @to) = @_;
	
	my $user = lc $event->nick;
	my $to = (split(/\s+/, $data))[0] || $user;
	
	my $hm = gethostmask($event->userhost);
	#if(!exists $users->{$hm} or (lc($users->{$hm}{'user'}) ne $user)) {
	if(!main->userdb->getid( $hm ) or
		(lc((main->userdb->who($hm))[0]) ne $user)
	) {
		main->qmsg($to, "Not allowed (your name does not match your hostmask)");
		return;
	}
	
	my $items = getmessages( );
	
	if(defined $items->{$user} and scalar @{$items->{$user}}) {
		my $i = 0;
		show($to, ++$i, @{$_}{qw(time from msg)})
			for(@{$items->{$user}});
	} else {
		main->qmsg($to, "No Messages");
	}
}

sub msg_rem {
	my ($self, $event, $chan, $data, @to) = @_;
	
	my $user = lc $event->nick;
	
	my $hm = gethostmask($event->userhost);
	#if(!exists $users->{$hm} or (lc($users->{$hm}{'user'}) ne $user)) {
	if(!main->userdb->getid( $hm ) or
		(lc((main->userdb->who($hm))[0]) ne $user)
	) {
		main->qmsg($chan, "Not allowed (your name does not match your hostmask)");
		return;
	}
	
	my $items = getmessages( );
	
	if($data eq 'all') {
		delete $items->{$user};
		main->qmsg($chan, "All of your messages have been cleared.");
	} else {
		my @nums = map { int( ) - 1 } grep { /^\d+$/ } split(/[\s,]+/, $data);
		my %rem = ( );
		@rem{@nums} = (1) x @nums;
		
		my $i = 0;
		@{$items->{$user}} = grep { !$rem{$i++} } @{$items->{$user}};
		
		main->qmsg($chan, "Cleared: " . join(', ', map { $_ + 1 } @nums));
	}
	
	savemessages($items);
}

sub mymessages_clear {
	my ($self, $event, $chan, $data, @to) = @_;
	
	return unless main->can_access($event->userhost);

	main->debug("going to unlink $file");
	
	unlink $file;
	
	main->qmsg($chan, "All Messages Cleared");
}

sub on_join {
	my ($self, $event) = @_;
	my ($chan) = ($event->to)[0];
	my ($user, $hm) = ($event->nick, gethostmask($event->userhost));
	
	#return if !user_exists($user) or !exists($users->{$hm});
	return if !user_exists($user) or !main->userdb->getid( $hm ); 
	
	my $items = getmessages( );
	
	if(defined $items->{lc $user} and scalar @{$items->{lc $user}}) {
		main->conn->notice($user, "You have messages waiting. Type [" .
						main->trigger . "mymessages] to see them.");
	}
}

sub list_search {
	my ($self, $event, $chan, $data, @to) = @_;
	
	my $regex = $data;
	
	my $items = getmessages( );
	
	my %result = eval {
			map { $_ => $items->{$_} } 
				grep { $items->{$_} =~ /\Q$regex\E/i } keys %{$items};
	};
	
	if($@) {
		main->qmsg($chan, "Error: $@");
	}
	
	return main->qmsg($chan, "No Results matching '$regex'") unless keys %result;
	
	for my $k (sort { $a <=> $b } keys %result) {
		show($chan, $k, $result{$k});
	}
}

sub show {
	main->qmsg(shift, sprintf('[%02d][%s %s] %s', shift,
				strftime('%x', localtime(shift)), @_));
}

sub getmessages {
	return (-f $file ? retrieve($file) : { });
}

sub savemessages {
	return store(shift, $file);
}

sub user_exists {
	my $u = shift;
	#return scalar grep { lc($u) eq lc($users->{$_}{'user'}) } keys %{$users};

	return main->userdb->nick2id( $u );
}

1;
__END__
