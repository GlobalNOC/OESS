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

use Test::More tests => 5;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

ok(defined($db), "Was able to connect to db");

my $has_alternate_path = $db->circuit_has_alternate_path( circuit_id => 4011);

ok($has_alternate_path, "Out circuits has an alternate path");

$has_alternate_path = $db->circuit_has_alternate_path( circuit_id => 1501);

ok(!$has_alternate_path, "Circuit does not have an alternate path");

$has_alternate_path = $db->circuit_has_alternate_path();

ok(!defined($has_alternate_path), "When no param circuit is not defined");

$has_alternate_path = $db->circuit_has_alternate_path( circuit_id => 999999999);

ok(!defined($has_alternate_path), "When a circuit doesn't exist it returns undef");
