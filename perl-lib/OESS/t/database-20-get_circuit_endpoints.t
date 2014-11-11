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

my $res = $db->get_circuit_endpoints();
ok(!defined($res), "No value returned when no cirucuit id specified");

my $error = $db->get_error();
ok(!defined($error), "No Params were passed and we got an error back");

$res = $db->get_circuit_endpoints( circuit_id => 101 );
ok(defined($res), "Ciruit endpoints found are found for the specified ciruit id");

$res = $db->get_circuit_endpoints( circuit_id => 99999999 );
ok(!defined($res), "There are no endpoints for the specified circuit id");
