package LedBot::UserManager;

# catch whois requests and such

# how it will work:
# um->queue( 'nick', um->ref('add,delete,...), ... );
#
use strict;
use LedBot::Special qw(gethostmask);

my %refs = (
	'add'		=> \&ref_add,
	'delete' 	=> \&ref_del,
	'addcmd'	=> \&ref_addcmd,
	'delcmd'	=> \&ref_delcmd
);

my $me = __PACKAGE__->new;

# add to the top
main->events->add('userhost' => [\&reply, 1]) unless main->checkload('userhost_reply');

sub um { $me }; 
*main::um = \&um;

sub reply {
	my ($self, $event, $chan, $data, @to) = @_;
	
	my ($user, $mask) = split(/=[+-]/, ($event->args)[1], 2);
	
	main->debug(
		sprintf("User: %s - %s [ %s ]",
			$user, $mask, my $hm = gethostmask($mask)
		)
	);

	if(defined $me->{$user}) {
		if(my $instance = shift @{$me->{$user}}) {
			main->debug("*** defined! $instance");

			# now execute it
			$instance->{'ref'}->( $user, $hm, @{$instance->{'other'}} );
		}
	}

	# don't do anymore actions
	#return -1;
	return 1;
}

sub new { bless( { }, shift @_ ); }

# add an item to the queue
#
# um->queue('user', um->ref('add'),
#	{
#		'inchan' => '#foo',
#		'commands' => ['a', 'b', 'c']
#	}
# );
#
sub queue {
	my ($self, $nick, $ref, @other) = @_;

	$me->{$nick} ||= [];

	push(@{$me->{$nick}}, {
		'ref'	=> $ref,
		'other' => \@other
	});
	
	main->conn->userhost($nick);
}

sub ref {
	my ($self, $tag) = @_;

	return $refs{lc $tag} || sub { };
}

sub ref_add {
	my $user = shift;
	my $hostmask = shift;
	my @other = @_;

	main->debug("ref-add reply with: @other");
	main->debug("attempting to adduser $user");
		
	my $addedcommands = undef;
	my $chan = $other[0]->{'inchan'};
		
	if(main->userdb->getid( $hostmask )) {
		main->qmsg($chan, "$user is already on my user list (well, the hostmask at least)");
	} else {
		my $uid = main->userdb->adduser( $user, $hostmask, 0 );

		for my $c (@{$other[0]->{'commands'}}) {
			if($c eq '*all*') {
				main->userdb->make_god( $uid );
			} else {
				main->userdb->give_access( $uid, $c );
			}
			$addedcommands .= ($addedcommands ? ' ' : undef) . $c;
		}
		
		main->qmsg($chan, "$user ($hostmask) added to user list!");
		main->qmsg($chan, "Added access to the following commands: $addedcommands") if $addedcommands =~ /\S/;
	}
	
	main->debug("user added?!");
	
	return 1;
}

# Subs to handle whois_replies to various things
sub ref_del {
	my $user = shift;
	my $hostmask = shift;
	my @other = @_;

	main->debug("ref-del reply with: @other");
	main->debug("attempting to deluser $user");
	
	my $chan = $other[0]->{'inchan'}; 
	
	if(main->userdb->getid( $hostmask )) {
		main->userdb->deluser( $hostmask );
		main->qmsg($chan, "$user ($hostmask) deleted!");
	} else {
		main->qmsg($chan, "$user ($hostmask) is not on the user list!");
	}
		
	main->debug("user deleted?");
	
	return 1;
}

# Subs to handle whois_replies to various things
sub ref_addcmd {
	my $user = shift;
	my $hostmask = shift;
	my @other = @_;

	main->debug("ref-addcmd reply with: @other");
	main->debug("queued new commands!");
	main->debug("attempting to add commands for $user");
	
	my $chan = $other[0]->{'inchan'};
	my @commands = @{$other[0]->{'commands'}};
	
	if(my $uid = main->userdb->getid( $hostmask )) {
		for my $c (@commands) {
			if($c eq '*all*') {
				main->userdb->make_god( $uid );
			} else {
				if( $c eq '-all-' ) {
					main->userdb->make_nogod( $uid );
				} else {
					main->userdb->give_access( $uid, $c );
				}
			}
		}
		main->qmsg($chan, "Added these commands for $user: " . join(', ', @commands));
	} else {
		main->qmsg($chan, "$user ($hostmask) is not on the user list!");
	}
	
	return 1;
}

sub ref_delcmd {
	my $user = shift;
	my $hostmask = shift;
	my @other = @_;

	main->debug("ref-addcmd reply with: @other");
	main->debug("attempting to delete commands for $user");
		
	my $chan = $other[0]->{'inchan'};
	my @commands = @{$other[0]->{'commands'}};
	
	if(my $uid = main->userdb->getid( $hostmask )) {
		for my $c (@commands) {
			if($c eq '*all*') {
				# remove all commands
				main->userdb->take_access( $uid, main->userdb->which_commands( $uid ));
			} else {
				main->userdb->take_access( $uid, $c );
			}
		}
		main->qmsg($chan, "Deleted these commands for $user: " . join(', ', @commands));
	} else {
		main->qmsg($chan, "$user ($hostmask) is not on the user list!");
	}
	
	return 1;
}

1;
__END__
