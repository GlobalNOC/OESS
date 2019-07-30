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
use Test::More tests => 4;

use OESSDatabaseTester;

use OESS::DB;
use OESS::L2Circuit;


OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);


my $db = new OESS::DB(
    config  => "$path/../conf/database.xml"
);

my $c = new OESS::L2Circuit(db => $db, circuit_id => 4081);
$c->load_endpoints;

ok(@{$c->endpoints} == 2, 'expected number of endpoints found');

$c->reason('gotta test an edit');
$c->user_id(11);
$c->update;


my $c2 = new OESS::L2Circuit(db => $db, circuit_id => 4081);
$c2->load_endpoints;

ok(@{$c2->endpoints} == 2, 'expected number of endpoints found');
ok($c2->reason eq 'gotta test an edit', 'reason as expected');
ok($c2->user_id == 11, 'user_id as expected');
