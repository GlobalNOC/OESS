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
use Test::More tests => 12;
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

my $error = OESS::DB::VRF::add_vrf_history();
ok($error eq 'Required argument "db" is missing', 'No database defined');

$error = OESS::DB::VRF::add_vrf_history(
    db => $db
);
ok($error eq 'Required argument "event" is missing', 'No event defined');

$error = OESS::DB::VRF::add_vrf_history(
    db => $db,
    event => 'fake'
);
ok($error eq 'Required argument "event" must be "create", "edit", or "decom"', 'Not a valid event');

$error = OESS::DB::VRF::add_vrf_history(
    db => $db,
    event => 'create'
);
ok($error eq 'Required argument "vrf" is missing', 'No vrf object defined');

$error = OESS::DB::VRF::add_vrf_history(
    db => $db,
    event => 'create',
    vrf => $vrf
);
ok($error eq 'Required argument "user_id" is missing', 'No user_id defined');

$error = OESS::DB::VRF::add_vrf_history(
    db => $db,
    event => 'create',
    vrf => $vrf,
    user_id => 1
);
ok($error eq 'Required argument "workgroup_id" is missing', 'No workgroup_id defined');

$error = OESS::DB::VRF::add_vrf_history(
    db => $db,
    event => 'create',
    vrf => $vrf,
    user_id => 1,
    workgroup_id => $workgroup_id
);
ok($error eq 'Required argument "state" is missing', 'No state defined');

$error = OESS::DB::VRF::add_vrf_history(
    db => $db,
    event => 'create',
    vrf => $vrf,
    user_id => 1,
    workgroup_id => $workgroup_id,
    state => 'fake'
);
ok($error eq 'Required argument "state" must be "active", "decom", "scheduled", "deploying", "looped", "reserved" or "provisioned"', 'Not a valid state');

$error = OESS::DB::VRF::add_vrf_history(
    db => $db,
    event => 'create',
    vrf => $vrf,
    user_id => 1,
    workgroup_id => $workgroup_id,
    state => 'active'
);
ok(!defined $error, "Created history entry when creating a new conneciton");

$error = OESS::DB::VRF::add_vrf_history(
    db => $db,
    event => 'edit',
    vrf => $vrf,
    user_id => 1,
    workgroup_id => $workgroup_id,
    state => 'active'
);
ok(!defined $error, "Created history entry when editing a conneciton");

$error = OESS::DB::VRF::add_vrf_history(
    db => $db,
    event => 'decom',
    vrf => $vrf,
    user_id => 1,
    workgroup_id => $workgroup_id,
    state => 'active'
);
ok(!defined $error, "Created history entry when decoming a conneciton");
