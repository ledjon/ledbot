package LedBot::FifoEvent;

# fifo queue package for ledbot
# by Jon Coulter

use strict;
use FileHandle;
use FindBin;
use Fcntl;
use POSIX qw(mkfifo);
use IO::Select;
use constant BASE => $FindBin::RealBin . '/fifo';

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;

	my $self = {
			'_select' => IO::Select->new
	};

	bless($self, $class);

	$self->add( @_ ) if @_;
	
	return $self;
}

sub select { shift->{'_select'} }

sub add {
	my $self = shift;
	my $f = shift;
	my $event = shift;

	ref($event) eq 'CODE' or die "Need to send 'code' to ->add";

	my $file = BASE . '/' . $f;

	unlink($file) if -e $file;
	mkfifo($file, 0666) or die "Unable to make fifo ($file): $!\n";

	main->debug("** going to open $f");
	my $fh = $self->openit( $f ) or die "Unable to open fifo: $!\n";
	main->debug("++ opened");
	$self->{$fh} = [$f, $event, @_];
	$self->select->add( $fh );

	return 1;
}

sub remove {
	my $self = shift;

	for my $f (@_) {
		for my $fh (keys %{$self}) {
			next if $fh =~ /^_/; # skip internal vars

			if($self->{$fh}->[0] eq $f) {
				main->debug("going to remove $fh");
				$self->select->remove( $fh );
				delete $self->{$fh};

				# remove the file
				my $file = BASE . '/' . $f;
				unlink($file);
			}
		}
	}

	return 1;
}

# trigger an attept to read all the fifo's
sub trigger {
	my $self = shift;

	for my $fh ($self->select->can_read(0)) {
		unless(defined $self->{$fh} and $fh->opened) {
			$self->select->remove( $fh );
			next;
		}

		my ($f, $event, @other) = @{$self->{$fh}};
		
		my $file = BASE . '/' . $f;
		my $data = undef;

		while($fh->sysread(my $buf, 1) > 0) {
			$data .= $buf;
		}

		if($data) {
			# get this far, trigger event
			$event->($data, @other);
		}

		# remove old handle, add new one
		#$self->remove( $f );
		$self->select->remove($fh);
		delete $self->{$fh};
		
		# now open/add it
		$self->add( $f, $event, @other );

		main->debug("\tend of loop cycle");
	}

	return 1;
}

sub openit {
	my ($self, $f) = @_;

	my $file = BASE . '/' . $f;

	return FileHandle->new($file, O_NONBLOCK|O_RDONLY);
}

sub DESTROY {
	my ($self) = @_;

	main->debug("self: $self");

	for my $fh (keys %{$self}) {
		next if $fh =~ /^_/;

		my $file = BASE . '/' . $self->{$fh}->[0];

		delete $self->{$fh};

		main->debug("going to remove $file");
		unlink($file) if -e $file;
	}

}

1;
__END__
