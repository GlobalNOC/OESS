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
use Test::More tests => 5;

use OESSDatabaseTester;

use OESS::DB;
use OESS::DB::Interface;

# Purpose:
#
# Verify interface port number updates are correctly written to the
# database.


OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

my $db = new OESS::DB(
   config => "$path/../conf/database.xml"
);

my $model = {
    interface_id => 41,
    description => 'demodemodemo'
};

my $err = OESS::DB::Interface::update(
    db => $db,
    interface => $model
);
ok(!defined $err, 'Interface updated');
warn $err if defined $err;


my $intf = OESS::DB::Interface::fetch(
    db => $db,
    interface_id => 41
);

foreach my $key (keys %$model) {
    ok($intf->{$key} eq $model->{$key}, "got expected $key from db");
}


my $err1 = OESS::DB::Interface::update(
    db => $db,
    interface => undef
);
ok(defined $err1, "Got expected error $err1");


delete $model->{interface_id};
my $err2 = OESS::DB::Interface::update(
    db => $db,
    interface => $model
);
ok(defined $err2, "Got expected error $err2");
