package LedBot::ToDo;

# ledbot todo list keeper
# by Jon Coulter

use strict;
use LedBot::Special qw(getrange);
use Storable;

my $file = './dbms/todo';

# add our handlers
main->addcmd('todo', \&list);
main->addcmd('todo-add', \&list_add);
main->addcmd('todo-rem', \&list_rem, 'todo-remove', 'todo-del', 'todo-delete');
main->addcmd('todo-clear', \&list_clear);
main->addcmd('todo-search', \&list_search);
main->addcmd('todo-modify', \&list_modify);

sub list {
	my ($self, $event, $chan, $data, @to) = @_;
	
	my $items = getlist( );
	
	my ($start, $stop) = getrange($data);
	$stop ||= scalar keys %{$items};
	
	my $x = 0;
	for(my $i = ($start + 1); $i < ($stop + 1) && defined $items->{$i}; $i++) {
		$x++;
		show($chan, $i, $items->{$i});
	}
	
	main->qmsg($chan, "No items on todo list") unless $x;
}

sub list_add {
	my ($self, $event, $chan, $data, @to) = @_;

	return unless main->can_access($event->userhost);
	
	my $items = getlist( );
	
	$items->{highkey($items) + 1} = $data;
	
	savelist($items);
	
	main->qmsg($chan, "'$data' added to list");
}

sub list_rem {
	my ($self, $event, $chan, $data, @to) = @_;
	
	return unless main->can_access($event->userhost);
	
	my $items = getlist( );
	
	my @msg = ( );
	for my $k (split(/\s+/, $data)) {
		$k = int $k;
		delete $items->{$k};
		push(@msg, $k);
	}
	
	my $i = 0;
	%{$items} = map { ++$i => $items->{$_} }
			sort { $a <=> $b } keys %{$items};
	
	savelist($items);
	
	if(@msg > 0) {
		main->qmsg($chan, "Removed " . join(', ', @msg));
	}
}

sub list_clear {
	my ($self, $event, $chan, $data, @to) = @_;
	
	return unless main->can_access($event->userhost);
	
	savelist({ });
	
	main->qmsg($chan, "List Clearned");
}

sub list_search {
	my ($self, $event, $chan, $data, @to) = @_;
	
	my $regex = $data;
	
	my $items = getlist( );
	
	my %result = eval {
		map { $_ => $items->{$_} } 
			grep { $items->{$_} =~ /\Q$regex\E/i }
				keys %{$items};
	};
	
	if($@) {
		main->qmsg($chan, "Error: $@");
	}
	
	return main->qmsg($chan, "No Results matching '$regex'") unless keys %result;
	
	for my $k (sort { $a <=> $b } keys %result) {
		show($chan, $k, $result{$k});
	}
}

sub list_modify {
	my ($self, $event, $chan, $data, @to) = @_;
	
	my ($key, $data) = split(/\s+/, $data, 2);
	
	my $items = getlist( );
	
	if(defined $items->{$key}) {
		$items->{$key} = $data;
		main->qmsg($chan, "$key updated to: $data");
	} else {
		main->qmsg($chan, "No items for '$key'");
	}
	
	savelist($items);
}

sub show {
	main->qmsg(shift, sprintf('[%02d] %s', @_));
}

sub getlist {
	return (-f $file ? retrieve($file) : { });
}

sub savelist {
	return store(shift, $file);
}

sub highkey {
	my $items = shift;
	for my $k (sort { $b <=> $a } keys %{$items}) {
		return $k
	}
}

1;
__END__
