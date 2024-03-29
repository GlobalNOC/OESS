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
use Test::More tests => 17;
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
ok($error eq 'Required argument "db" is missing', 'Got expected error: No database defined');

$error = OESS::DB::VRF::add_vrf_history(
    db => $db
);
ok($error eq 'Required argument "event" is missing', 'Got expected error: No event defined');

$error = OESS::DB::VRF::add_vrf_history(
    db => $db,
    event => 'fake'
);
ok($error eq 'Required argument "event" must be "create", "edit", or "decom"', 'Got expected error: Not a valid event');

$error = OESS::DB::VRF::add_vrf_history(
    db => $db,
    event => 'create'
);
ok($error eq 'Required argument "vrf" is missing', 'Got expected error: No vrf object defined');

$error = OESS::DB::VRF::add_vrf_history(
    db => $db,
    event => 'create',
    vrf => $vrf
);
ok($error eq 'Required argument "user_id" is missing', 'Got expected error: No user_id defined');

$error = OESS::DB::VRF::add_vrf_history(
    db => $db,
    event => 'create',
    vrf => $vrf,
    user_id => 1
);
ok($error eq 'Required argument "workgroup_id" is missing', 'Got expected error: No workgroup_id defined');

$error = OESS::DB::VRF::add_vrf_history(
    db => $db,
    event => 'create',
    vrf => $vrf,
    user_id => 1,
    workgroup_id => $workgroup_id
);
ok($error eq 'Required argument "state" is missing', 'Got expected error: No state defined');

$error = OESS::DB::VRF::add_vrf_history(
    db => $db,
    event => 'create',
    vrf => $vrf,
    user_id => 1,
    workgroup_id => $workgroup_id,
    state => 'fake'
);
ok($error eq 'Required argument "state" must be "active", "decom", "scheduled", "deploying", "looped", "reserved" or "provisioned"', 'Got expected error: Not a valid state');

$error = OESS::DB::VRF::add_vrf_history(
    db => $db,
    event => 'create',
    vrf => $vrf,
    user_id => 1,
    workgroup_id => $workgroup_id,
    state => 'active'
);
ok(!defined $error, "Created history entry when creating a new connection");

$error = OESS::DB::VRF::add_vrf_history(
    db => $db,
    event => 'edit',
    vrf => $vrf,
    user_id => 1,
    workgroup_id => $workgroup_id,
    state => 'active'
);
ok(!defined $error, "Created history entry when editing a connection");

$error = OESS::DB::VRF::add_vrf_history(
    db => $db,
    event => 'decom',
    vrf => $vrf,
    user_id => 1,
    workgroup_id => $workgroup_id,
    state => 'active'
);
ok(!defined $error, "Created history entry when decoming a connection");

my $events = OESS::DB::VRF::get_vrf_history( db => $db, vrf_id => $vrf->{vrf_id});
ok(defined $events, "No errors getting vrf history events");
warn Dumper($events) if !defined $events;
ok(scalar(@$events) == 3, "Three history events created and stored");
ok($events->[0]->{event} eq 'create', "First event is a create");
warn Dumper($events->[0]) if $events->[0]->{event} ne 'create';
ok($events->[1]->{event} eq 'edit', "Second event is a edit");
warn Dumper($events->[1]) if $events->[1]->{event} ne 'edit';
ok($events->[2]->{event} eq 'decom', "Third event is a decom");
warn Dumper($events->[2]) if $events->[2]->{event} ne 'decom';
