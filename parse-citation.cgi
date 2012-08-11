#!/usr/bin/perl

use strict;

use lib "libs"; # ParaTool libraries

use JSON;
use CGI ':standard';
use CGI::Carp 'fatalsToBrowser';
use ParaTools::CiteParser::Jiao;

my $cgi = CGI->new();
my $cite = $cgi->param('text');

$cite =~ s/\s+/ /g;
$cite =~ s/et al(\.*)/;/ig;
$cite =~ s/\[.*?\]$//g;
$cite =~ s/(.*[a-z])(.*?)$/$1..$2/ig;
$cite =~ s/\.+/./g;

my $parser = new ParaTools::CiteParser::Jiao();
my $metadata = $parser->parse($cite, 0);

my @authors = split(/:/, $metadata->{authors});

my @authors_fixed;
foreach my $author (@authors){
	$author =~ s/(.*)\.(\w*)/$2 \U$1/;
	$author =~ s/\.//g;
	if (($author !~ m/-/) && ($author !~ m/_/) && ($author !~ m/van\s/i) && (length($1) < 4)){
		push @authors_fixed, $author;
	}
}

$metadata->{authors} = \@authors_fixed;

my $json = new JSON;

print header(-type=>'application/json', -charset=>'utf-8', -access_control_allow_origin => '*');
print $json->encode($metadata);