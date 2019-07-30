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
use OESS::DB::Path;

use OESS::Path;


OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);


my $db = new OESS::DB(
    config  => "$path/../conf/database.xml"
);


my ($links, $err) = OESS::DB::Path::get_links(
    db => $db,
    path_id => 71
);
warn $err if (defined $err);

ok(@$links == 2, 'Links loaded.');


my ($p, $p_err) = OESS::DB::Path::fetch(db => $db, path_id => 71);

ok($p->{path_id} == 71, 'loaded path from db');
ok($p->{state} eq 'active', 'expected state found');


my ($res, $res_err) = OESS::DB::Path::update(
    db => $db,
    path => { path_id => 71, state => 'decom' }
);
warn $res_err if (defined $res_err);

($p, $p_err) = OESS::DB::Path::fetch(db => $db, path_id => 71);
warn $p_err if (defined $p_err);

ok($p->{state} eq 'decom', 'state updated to correct value');
