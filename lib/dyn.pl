#!/usr/bin/perl

use strict;
use Net::EdgeDyn;

my $dyn = Net::EdgeDyn->new(
		User	=> 'ledbot',
		Pass	=> 'asdf',
		Debug	=> 1
) or die $!;

$dyn->login or die $dyn->errstr;
$dyn->update or die $dyn->errstr;

$dyn->close;

1;
__END__
