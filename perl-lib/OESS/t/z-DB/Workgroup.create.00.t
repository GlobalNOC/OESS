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
use Test::More tests => 8;

use OESSDatabaseTester;

use OESS::DB;
use OESS::DB::Workgroup;

# PURPOSE:
#
# Verify workgroups are correctly populated into the database.

OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

my $db = new OESS::DB(
   config => "$path/../conf/database.xml"
);

my $model = {
    name        => 'wg1',
    description => 'wg1 description',
    type        => 'normal',
    external_id => 'nan'
};

my ($id, $err) = OESS::DB::Workgroup::create(db => $db, model => $model);
ok($id > 0, "workgroup entry $id created.");
ok(!defined $err, "no error on standard creation");
die $err if defined $err;

my ($workgroup, $err2) = OESS::DB::Workgroup::fetch(db => $db, workgroup_id => $id);
ok(defined $workgroup, "workgroup retrieved from db.");
ok(!defined $err2, "no error on standard fetch");
die $err2 if defined $err2;

foreach my $key (keys %$model) {
    ok($workgroup->{$key} eq $model->{$key}, "got expected $key from db");
}
