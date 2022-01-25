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
use Test::More tests => 9;
use OESSDatabaseTester;
use OESS::DB;
use OESS::VRF;
use OESS::Config;

OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

my $test_config = new OESS::Config(config_filename => "$path/../conf/database.xml");
my $workgroup_id = 31;

my $db = new OESS::DB(
    config  => "$path/../conf/database.xml"
);

my $vrf = new OESS::VRF(
    config => $test_config,
    db     => $db,
    model  => {
        name           => 'Test',
        description    => 'Test',
        local_asn      =>  1,
        workgroup_id   =>  $workgroup_id,
        provision_time => -1,
        remove_time    => -1,
        created_by_id  => 11,
        last_modified_by_id => 11
    }
);

my ($id, $err) = $vrf->create;
ok(defined $id, "Created vrf $vrf->{vrf_id}.");
ok(!defined $err, "Created vrf $vrf->{vrf_id} without error.");

($id, $err) = $db->execute_query("select * from vrf_history");
ok(defined $id, "Created entry in vrf_history table");

($id, $err) = $db->execute_query("select * from history");
ok(defined $id, "Created entry in history table");
ok(@$id[0]->{'event'} eq 'Connection Creation', "Check history creation event matches");

my $loaded_vrf = new OESS::VRF(config => $test_config, db => $db, vrf_id => $vrf->vrf_id);
$loaded_vrf->name('bahahaha');
$loaded_vrf->update;
($id, $err) = $db->execute_query("select * from history where event = 'User requested connection edit'");
ok(defined $id, "Created edit history entry");
ok(@$id[0]->{'event'} eq 'User requested connection edit', "Check history update event matches");

$loaded_vrf = new OESS::VRF(config => $test_config, db => $db, vrf_id => $vrf->vrf_id);
$loaded_vrf->decom(user_id => 11);
($id, $err) = $db->execute_query("select * from history where state = 'decom'");
ok(defined $id, "Created decom history event");
ok(@$id[0]->{'event'} eq "Connection Deletion",  "Check history decom event matches");
