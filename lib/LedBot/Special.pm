package LedBot::Special;

# contained often-used functions
# that various packages can import

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
use DBI;
use POSIX qw(strftime);
use Exporter;
use DirHandle;
use FileHandle;
use File::Path;
use LWP::Simple;
use XML::Simple;
use Getopt::Std;
use Text::ParseWords qw(shellwords);

$VERSION = '1.05';

@ISA = qw(Exporter Getopt::Std Text::ParseWords);

# we'll force this one method onto everybody :)
@EXPORT = qw(strftime);

@EXPORT_OK = qw( 
	getrange gethostmask timediff fetchpage
	xml_parse addcommas trim entities strftime
	getopts shellwords execute sql_handle sql_create
	mkpath fh timeout
);
			
%EXPORT_TAGS = (
	all		=> [@EXPORT_OK],
	xmlcommon	=> [qw(fetchpage xml_parse getrange)],
	sql		=> [qw(sql_handle sql_create)]
);

sub entities {
	my $in = shift;
	
	my %rep = (
		'&(quote|#34);?'	=> '"',
		'&(amp|#38);?'		=> '&',
		'&(lt|#60);?'		=> '<',
		'&(gt|#62);?'		=> '>',
		'&(nbsp|#160);?'	=> ' ',
		'&(iexcl|#161);?'	=> chr(161),
		'&(cent|#162);?'	=> chr(162),
		'&(pound|#163);?'	=> chr(163),
		'&(copy|#169);?'	=> chr(169)
	);
	
	$in =~ s/$_/$rep{$_}/g for(keys %rep);
	
	return $in;
}

sub getrange {
	my $range = shift;
	
	my ($start, $stop) = split(/-/, $range);

	unless($stop) {
		$stop = $start;
		$start = 0;
	}
	
	# fix because of zero base
	$start-- if $start;
	
	# another option?
	if($range =~ /^#(\d+)/) {
		$start = $1 - 1;
		$stop = $1;
	}
	
	return (wantarray) ? ($start, $stop) : $stop;
}

sub gethostmask($) {
	my $tag = shift;
	$tag =~ s/~//g;

	if($tag =~ m|^([^@]+)@(.+)$|) {
		my $user = $1;
		my $mask = $2;
		my $chopmask;

		if($mask =~ m|^\d+\.\d+\.\d+\.\d+$|) {
			# is ip address
			$chopmask = join('.', (split(/\./, $mask))[0..2]);
			$chopmask .= '.*';
		} else {
			# real mask
			my @parts = split(/\./, $mask);
			if(scalar(@parts) <= 4) {
				my $sub = scalar(@parts) - 1;
				$sub = ($sub < 2) ? 2 : $sub;
				$chopmask = join('.', @parts[(scalar(@parts) - $sub)..(scalar(@parts) - 1)]);
			} else {
				$chopmask = join('.', @parts[(scalar(@parts) - 4)..(scalar(@parts) - 1)]);
			}

			$chopmask = '*.' . $chopmask;
		}

		my $hostmask = '*!*'.$user.q[*@].$chopmask;
		
		return $hostmask;
	} else {
		warn("Not a valid mask ($tag)");
		return 0;
	}
}

sub timediff {
	my $low = shift;
	my $high = shift || time();
	
	my $seconds = $high - $low;

	my $days = my $hours = my $mins = 0;

	# Fingure out the days
	while($seconds >= 86400) {
		$days++;
		$seconds -= 86400;
	}

	# Now hours
	while($seconds >= 3600) {
		$hours++;
		$seconds -= 3600;
	}

	# Mins
	while($seconds >= 60) {
		$mins++;
		$seconds -= 60;
	}
	
	return $days . ' day' . ($days != 1 ? 's' : undef) . ', ' .
			$hours . ' hour' . ($hours != 1 ? 's' : undef) . ', ' .
			$mins  . ' minute' . ($mins != 1 ? 's' : undef) . ' and ' .
			$seconds . ' second' . ($seconds != 1 ? 's' : undef);
}

# timeout an action
sub timeout {
	my $time = int(shift) || 10;
	my $sub = shift;
	
	ref($sub) eq 'CODE' or die "`$sub' is not a code reference\n";

	return eval {
		local $SIG{'ALRM'} = sub { die "timeout\n"; };
		alarm($time);
		my $ret = $sub->(@_);
		alarm(0);
		return $ret;
	};
}

sub fetchpage {
	return unless @_;
	my ($page, $time) = @_;
	$time ||= 20;

	my $ret = timeout($time, \&LWP::Simple::get, $page);
	
	return $ret;
}

sub xml_parse {
	return unless @_;

	# catch and ignore (don't even debug) warnings form this
	#local $SIG{'__WARN__'} = sub { 1 };
	return eval { return XMLin(@_); };
}

sub addcommas($) {
	my $value = shift;
	
	1 while ( $value =~ s/^(-?\d+)(\d{3})/$1,$2/ );
	
	return $value;
}

# Trim sub
sub trim {
	my @text = @_;
	
	for (@text) {
		while(/\s$/) {
			chop;
		}
		
		while(/^\s/) {
			$_ = substr($_, 1);
		}
	}
	
	return (wantarray) ? @text : ((@text > 1) ? join('', @text) : $text[0]);
}

sub execute {
	my @in = map { quotemeta } @_;
	
	return `@in`;
}

sub urlencode {
	my $in = shift;
	$in =~ s/([^a-z0-9])/'%' . unpack("H2", $1)/egi; 

	return $in;
}

# just craw into a directory and load services
sub load_services {
	shift @_;
	my $dir = shift;
	my @return = ( );
	
	my $d = DirHandle->new($dir) or die $!;
	while(my $f = $d->read) {
		next if $f =~ /^\./;
		my $path = $dir . '/' . $f;
		
		if(-d $path) {
			my @rec = __PACKAGE__->load_services( $path );
			push(@return, join('::', ($f, $_))) for @rec;
		} else {
			if($f =~ /^(.+)\.pm$/) {
				push(@return, $1);
			}
		}
	}
	$d->close;
	
	return @return;
}

# get an sql database handle
sub sql_handle($) {
	my $name = shift or die "Need database name!\n";

	my $dbh = DBI->connect('DBI:SQLite:'.($FindBin::RealBin || '.').'/dbms/' . $name, '', '')
			or die $DBI::errstr;

	return $dbh;
}

# create the database schema
# if needed
sub sql_create {
	my ($dbh, %schema) = @_;

	my $sth = $dbh->prepare("select count(*) from sqlite_master where name = ?");

	# {table} -> name
	$schema{$_} =~ s/\{table\}/$_/isg for (keys %schema);
	
	for my $table (keys %schema) {
		$sth->execute( $table );
		my ($count) = $sth->fetchrow_array;

		unless($count > 0) {
			$dbh->do( $schema{$table} )
				or die $dbh->errstr;
		}
	}

	return 1;
}

sub fh {
	return FileHandle->new( @_ );
}

1;
__END__
