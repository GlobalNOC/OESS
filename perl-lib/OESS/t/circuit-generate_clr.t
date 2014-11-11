#!/usr/bin/perl -T

use strict;

use FindBin;
my $path;

BEGIN {
    if($FindBin::Bin =~ /(.*)/){
            $path = $1;
      }
}

use lib "$path";
use OESS::Database;
use OESS::Circuit;
use OESSDatabaseTester;

use Test::More tests => 2;
use Test::Deep;
use Data::Dumper;

my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );

my $ckt = OESS::Circuit->new( circuit_id => 101, db => $db);

my $clr = $ckt->generate_clr();

ok(defined($clr), "CLR was defined");

my $clr_raw = $ckt->generate_clr_raw();

warn "CLR RAW: " . $clr_raw . "\n";

ok(defined($clr_raw), "RAW CLR was defined");
