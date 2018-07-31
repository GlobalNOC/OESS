#!/usr/bin/perl -T

# tests of OESS::Entity's to_hash and save-to-DB functionality

use strict;

use FindBin;
my $path;

BEGIN {
    if($FindBin::Bin =~ /(.*)/){
        $path = $1;
    }
}

use lib "$path";
use OESS::DB;
use OESS::Entity;
use OESSDatabaseTester;

use Test::More tests => 2;
use Test::Deep;
use Data::Dumper;

my $db = OESS::DB->new( config => OESSDatabaseTester::getConfigFilePath() );

my $ent1 = OESS::Entity->new( entity_id => 2, db => $db );
ok(defined($db) && defined($ent1), 'Sanity check: can instantiate OESS::DB and OESS::Entity objects');

ok(&OESSDatabaseTester::resetOESSDB(), "Resetting OESS Database");
