#!/usr/bin/perl

use strict;
use lib './lib';
use LedBot::Special qw(:all);

my %tables = (
	'stories'	=> '
			create table {table} (
				sid 		varchar(20) primary key,
				title	 	varchar(50),
				url		varchar(50),
				time		datetime,
				author		varchar(20),
				department	varchar(20),
				topic		integer,
				comments	integer,
				section		varchar(10),
				image		varchar(10)
			)
	'
);

sql_create( my $dbh = sql_handle('slashdump'), %tables )
	or die "Unable to connect to sqlite database!\n";

while(my $file = <>) {
	chomp $file;
	next if !-f $file;

	warn sprintf("doing %s\n", $file);

	my $ref = xml_parse( $file ) or next;

	for my $story (@{ $ref->{'story'} }) {
		# get the key
		if($story->{'url'} =~ /sid=(.+)$/) {
			$story->{'sid'} = $1;
		} else {
			next;
		}
		
		my @elements = keys %{$story};
		
		my $sql = sprintf("insert or replace into stories (%s) values (%s)",
				join(', ', @elements),
				join(', ', ('?') x scalar @elements)
		);

		my $sth = $dbh->prepare( $sql ) or die $dbh->errstr;
		$sth->execute( @{ $story }{ @elements }) or die $dbh->errstr;
		$sth->finish;
	}
}

1;
__END__
