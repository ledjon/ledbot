package LedBot::Translate;

use strict;
use LedBot::Special qw(trim);
use SOAP::Lite;

my $service = 'http://www.xmethods.net/sd/2001/BabelFishService.wsdl';

my %langs = (
	'en_fr' => 'English -> French',
	'en_de' => 'English -> German',
	'en_it' => 'English -> Italian',
	'en_pt' => 'English -> Portugese',
	'en_es' => 'English -> Spanish',
	'fr_en' => 'French -> English',
	'de_en' => 'German -> English',
	'it_en' => 'Italian -> English',
	'pt_en' => 'Portugese -> English',
	'ru_en' => 'Russian -> English',
	'es_en' => 'Spanish -> English'
);

# main method
main->addcmd('xlate', \&translate, 'translate');

# method to list them
main->addcmd('translate-list', \&list, 'xlate-list');

sub translate {
	my ($self, $event, $chan, $data, @to) = @_;

	my ($lang, $text) = split(/\s+/, $data, 2);
	$lang = lc $lang;

	if(!exists $langs{$lang}) {
		main->qmsg($chan, "'$lang' is not a supported translation type (type " .
				main->trigger ."translate-list to see list)");

		return;
	}

	if(split(/\s+/, $text)> 150) {
		main->qmsg($chan, "Text is too long, trimming to 150 words");
		$text = join(' ', (split(/\s+/, $text))[0..149]);
	}

	main->qmsg($chan, "[Starting Translator]");
	
	my $soap = SOAP::Lite->service( $service );

	my $result = $soap->BabelFish(
			SOAP::Data->type( string => $lang )->name('translationmode'),
			SOAP::Data->type( string => $text )->name('sourcedata')
	);

	main->debug("result: $result");

	if(ref($result) and $result->fault) {
		main->qmsg($chan, "SOAP Error: " . $result->faultstring);
	} else {
		main->qmsg($chan, "Translation [".$langs{$lang}."]: " . trim( $result ));
	}
}

sub list {
	my ($self, $event, $chan, $data, @to) = @_;

	my @tmp = %langs;

	main->qmsg($chan, "Translate Languages:");
	while(1) {
		my ($a, $b) = (shift @tmp, shift @tmp);
		my ($c, $d) = (shift @tmp, shift @tmp);

		last unless $a and $b;
		
		main->qmsg($chan, "[$a: $b]" . (($c && $d) ? " [$c: $d]" : undef));
	}
}

1;
__END__
