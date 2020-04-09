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
use Test::More tests => 13;

use OESSDatabaseTester;

use OESS::DB;
use OESS::DB::Interface;

# Purpose:
#
# Verify interface updates are correctly saved into the database.


OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

my $db = new OESS::DB(
   config => "$path/../conf/database.xml"
);

my $model = {
    name => 'e333/1',
    description => 'e333/1',
    node_id => 111,
    role => 'unknown'
};

my ($interface_id, $err) = OESS::DB::Interface::create(
    db => $db,
    model => $model
);
ok(!defined $err, 'Interface created');
warn $err if defined $err;

my $intf = OESS::DB::Interface::fetch(
    db => $db,
    interface_id => $interface_id
);

foreach my $key (keys %$model) {
    next if !defined $model->{$key}; # Ignore warnings
    ok($intf->{$key} eq $model->{$key}, "got expected $key from db");
}

my $err1 = OESS::DB::Interface::create(
    db => $db,
    model => undef
);
ok(defined $err1, "Got expected error $err1");


delete $model->{node_id};
my $err2 = OESS::DB::Interface::create(
    db => $db,
    model => $model
);
ok(defined $err2, "Got expected error $err2");
