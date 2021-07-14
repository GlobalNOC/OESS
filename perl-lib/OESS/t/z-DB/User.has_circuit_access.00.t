#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
my $path;

BEGIN {
    if ($FindBin::Bin =~ /(.*)/) {
        $path = $1;
    }
}
use lib "$path/..";

use Data::Dumper;
use Test::More tests => 7;

use OESSDatabaseTester;

use OESS::DB;
use OESS::DB::User;
use OESS::DB::Workgroup;
use OESS::DB::Circuit;

OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

my $db = new OESS::DB(
    config => "$path/../conf/database.xml"
);


my ($result, $error) = OESS::DB::User::has_circuit_access(db => $db, username => 'aragusa', circuit_id => 11, role => 'admin');
ok($result == 1, "Got expected result '1'");

($result, $error) = OESS::DB::User::has_circuit_access(db => $db, user_id => 11, circuit_id => 11, role => 'admin');
ok($result == 1, "Got expected result '1'");

($result, $error) = OESS::DB::User::has_circuit_access(db => $db, user_id => 11, circuit_id => 11, role => 'normal');
ok($result == 1, "Got expected result '1'");

($result, $error) = OESS::DB::User::has_circuit_access(db => $db, user_id => 11, circuit_id => 11, role => 'read-only');
ok($result == 1, "Got expected result '1'");

($result, $error) = OESS::DB::User::has_circuit_access(db => $db, user_id => 901, circuit_id => 11, role => 'admin');
ok(defined $error, "Got expected error, $error");

($result, $error) = OESS::DB::User::has_circuit_access(db => $db, user_id => 901, circuit_id => 11, role => 'noraml');
ok(defined $error, "Got expected error, $error");

($result, $error) = OESS::DB::User::has_circuit_access(db => $db, user_id => 901, circuit_id => 11, role => 'read-only');
ok(defined $error, "Got expected error, $error");


