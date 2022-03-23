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
use Test::More tests => 14;
use OESSDatabaseTester;
use OESS::DB;
use OESS::DB::ACL;
use OESS::ACL;
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

my $acl = OESS::ACL->new(
    db => $db,
    model => {
        workgroup_id => 31,
        interface_id => 1,
        allow_deny   => 'allow',
        eval_position => '1111',
        start       => 1025,
        end         => 1027,
        notes       => undef,
        entity_id   => 1,
        user_id     => 1
    }
);
$acl->create;

my $error = OESS::DB::ACL::add_acl_history();
ok($error eq 'Required argument "db" is missing', 'Got expected error: No database defined');

$error = OESS::DB::ACL::add_acl_history(
    db => $db
);
ok($error eq 'Required argument "event" is missing', 'Got expected error: No event defined');

$error = OESS::DB::ACL::add_acl_history(
    db => $db,
    event => 'fake'
);
ok($error eq 'Required argument "event" must be "create", "edit", or "decom"', 'Got expected error: Not a valid event');

$error = OESS::DB::ACL::add_acl_history(
    db => $db,
    event => 'create'
);
ok($error eq 'Required argument "acl" is missing', 'Got expected error: No acl object defined');

$error = OESS::DB::ACL::add_acl_history(
    db => $db,
    event => 'create',
    acl => $acl
);
ok($error eq 'Required argument "user_id" is missing', 'Got expected error: No user_id defined');

$error = OESS::DB::ACL::add_acl_history(
    db => $db,
    event => 'create',
    acl => $acl,
    user_id => 1
);
ok($error eq 'Required argument "workgroup_id" is missing', 'Got expected error: No workgroup_id defined');

$error = OESS::DB::ACL::add_acl_history(
    db => $db,
    event => 'create',
    acl => $acl,
    user_id => 1,
    workgroup_id => $workgroup_id,
    state => 'active'
);
ok(!defined $error, "Created history entry when creating a new acl");

$error = OESS::DB::ACL::add_acl_history(
    db => $db,
    event => 'edit',
    acl => $acl,
    user_id => 1,
    workgroup_id => $workgroup_id,
    state => 'active'
);
ok(!defined $error, "Created history entry when editing an acl");

$error = OESS::DB::ACL::add_acl_history(
    db => $db,
    event => 'decom',
    acl => $acl,
    user_id => 1,
    workgroup_id => $workgroup_id,
    state => 'decom'
);
ok(!defined $error, "Created history entry when deleting an acl");

my $events = OESS::DB::ACL::get_acl_history( db => $db, interface_acl_id => $acl->{interface_acl_id});
ok(defined $events, "No errors getting acl history events");
warn Dumper($events) if !defined $events;
ok(scalar(@$events) == 3, "Three history events created and stored");
ok($events->[0]->{event} eq 'create', "First event is a create");
warn Dumper($events->[0]) if $events->[0]->{event} ne 'create';
ok($events->[1]->{event} eq 'edit', "Second event is a edit");
warn Dumper($events->[1]) if $events->[1]->{event} ne 'edit';
ok($events->[2]->{event} eq 'decom', "Third event is a decom");
warn Dumper($events->[2]) if $events->[2]->{event} ne 'decom';
