#!/usr/bin/perl

# become ledbot

use strict;
use IO::Handle;
use IO::Select;
use FileHandle;

my $file = shift or die "need log file to tail";
my $fifo = shift or die "need fifo!";

my $fh = IO::Handle->new;
open($fh, 'tail -s 1 -f ' . $file  . ' |') or die $!;
my $in = IO::Handle->new_from_fd(\*STDIN, 'r');

for($in, $fh) {
	$_->autoflush(1);
	$_->blocking(0);
}

my $s = IO::Select->new($fh, $in);

while(1) {
	for my $f ($s->can_read) {
		my $data;
		while($f->sysread(my $buf, 1024)) {
			$data .= $buf;
		}

		if($f == $in) {
			# print to our fifo
			my $h = FileHandle->new($fifo, 'w') or die $!;
			$h->print($data);
			$h->close;
		} else {
			print $data;
		}
	}
}

1;
__END__
