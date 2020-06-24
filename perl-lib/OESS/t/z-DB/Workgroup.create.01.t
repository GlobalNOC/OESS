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
use Test::More tests => 2;

use OESSDatabaseTester;

use OESS::DB;
use OESS::DB::Workgroup;

# PURPOSE:
#
# Verify workgroup creation errors when bad type specified.

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
    type        => 'badtype',
    external_id => 'nan'
};

my ($id, $err) = OESS::DB::Workgroup::create(db => $db, model => $model);
ok(!defined $id, "workgroup entry not created.");
ok(defined $err, "error on standard creation w bad type");
