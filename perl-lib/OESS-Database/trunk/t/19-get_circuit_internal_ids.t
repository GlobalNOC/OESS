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
use OESSDatabaseTester;

use Test::More tests => 4;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $res = $db->get_circuit_internal_ids();
ok(!defined($res), "No value returned when no cirucuit id specified");

my $error = $db->get_error();
ok(!defined($error), "No Params were passed and we got an error back");

$res = $db->get_circuit_internal_ids( circuit_id => 101 );
ok(defined($res), "Ciruit found and its internal ids are listed");

$res = $db->get_circuit_internal_ids( circuit_id => 99999999 );
ok(!defined($res), "failed to get internal ids of non-existng circuit");
