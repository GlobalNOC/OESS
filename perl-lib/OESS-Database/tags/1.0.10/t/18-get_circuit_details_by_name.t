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

my $res = $db->get_circuit_details_by_name();
ok(defined($res), "No value returned when no cirucuit name specified");

my $error = $db->get_error();
ok(!defined($error), "No Params were passed and we got an error back");

$res = $db->get_circuit_details_by_name( name => 'Circuit 101' );
ok(defined($res), "Ciruit found and details are listed");

$res = $db->get_circuit_details_by_name( name => 'Circuit 99999999' );
ok(defined($res), "fails to list details of  non-existng circuit");
