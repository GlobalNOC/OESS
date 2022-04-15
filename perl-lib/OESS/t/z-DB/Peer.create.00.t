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
use OESS::DB::Peer;

# PURPOSE:
#
# Verify peers are correctly populated into the database.

OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

my $db = new OESS::DB(
   config => "$path/../conf/database.xml"
);

my $model = {
    vrf_ep_id         => 2,
    ip_version        => 'ipv4',
    local_ip          => '192.168.2.2/21',
    peer_ip           => '192.168.2.3/21',
    peer_asn          => 65432,
    md5_key           => 'not a good key',
    bfd               => 1,
    operational_state => 'up'
};

my ($id, $err) = OESS::DB::Peer::create(db => $db, model => $model);
ok($id > 0, "vrf_ep_peer entry $id created.");
ok(!defined $err, "no error on standard creation");

my ($peers, $err2) = OESS::DB::Peer::fetch_all(db => $db, vrf_ep_id => 2);
ok(@$peers == 1, "expected number of peers retrieved from db.");
ok(!defined $err2, "no error on standard get");

foreach my $key (keys %$model) {
    ok($peers->[0]->{$key} eq $model->{$key}, "got expected $key from db");
}
