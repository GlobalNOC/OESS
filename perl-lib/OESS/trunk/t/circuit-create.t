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

use Test::More tests => 6;
use Test::Deep;
use Data::Dumper;


my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );

my $ckt = OESS::Circuit->new( circuit_id => 101, db => $db);

ok(defined($ckt), "Circuit object was defined");

ok($ckt->get_id() == 101, "Circuit object has correct id");

my $details = $db->get_circuit_details( circuit_id => 101 );

$ckt = OESS::Circuit->new( details => $details, db => $db);

ok(defined($ckt), "Circuit object was defined using details");

ok($ckt->get_id() == 101, "Circuit object has correct id");

$ckt = OESS::Circuit->new( db => $db);

ok(!defined($ckt), "Circuit object was not defined when no circuit_id or details were specified");

$ckt = OESS::Circuit->new(circuit_id => 101);

ok(!defined($ckt), "Circuit object was not defined when no db connection was specified");
