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

use OESS::Config;
use OESS::DB;
use OESS::VRF;

# PURPOSE:
#
# Verify that calling OESS::VRF->create with an entire VRF model will
# all child elements only creates the base record. Child instantiation
# is the responsibility of the child objects.

OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

my $test_config = new OESS::Config(config_filename => "$path/../conf/database.xml");

my $db = new OESS::DB(
   config => "$path/../conf/database.xml"
);

my $workgroup_id = 31;
my $model = {
    name           => 'Test_4',
    description    => 'Test_4',
    local_asn      =>  1,
    workgroup_id   =>  $workgroup_id,
    provision_time => -1,
    remove_time    => -1,
    created_by_id  => 11,
    last_modified_by_id => 11,
    endpoints => [
        {
            bandwidth => 0,
            mtu => 1500,
            tag => 2007,
            peerings => [
                { peer_asn => 7, md5_key => '', local_ip => '192.168.7.2/31', peer_ip => '192.168.7.3/31', version => 4 }
            ],
            entity => 'B University-Metropolis'
        },
        {
            bandwidth => 0,
            mtu => 1500,
            tag => 2008,
            peerings => [
                { peer_asn => 8, md5_key => '', local_ip => '192.168.8.2/31', peer_ip => '192.168.8.3/31', version => 4 }
            ],
            entity => 'Big State TeraPOP'
        }
    ]
};

my $vrf = new OESS::VRF(config => $test_config, db => $db, model => $model);

my ($id, $err) = $vrf->create;
ok(defined $id, "Created vrf $vrf->{vrf_id}.");
ok(!defined $err, "Created vrf $vrf->{vrf_id} without error.");

ok(!defined $vrf->{endpoints}, 'VRF->{endpoints} is undef pre-load.');
ok(@{$vrf->endpoints} == 0, 'VRF->endpoints is empty pre-load.');

$vrf->load_endpoints;
ok(defined $vrf->{endpoints}, 'VRF->{endpoints} is defined post-load.');
ok(@{$vrf->endpoints} == 0, 'VRF->endpoints is empty post-load.');

ok($vrf->workgroup_id == 31, 'Correct workgroup_id loaded.');

ok($vrf->{created_by_id} == 11, 'Correct created_by_id loaded.');
ok($vrf->{last_modified_by_id} == 11, 'Correct last_modified_by_id loaded.');

ok(!defined $vrf->created_by, 'Correct created_by pre-load.');
ok(!defined $vrf->last_modified_by, 'Correct last_modified_by pre-load.');

$vrf->load_users;
ok(defined $vrf->created_by, 'Correct created_by post-load.');
ok(defined $vrf->last_modified_by, 'Correct last_modified_by post-load.');

ok($vrf->created_by->{usernames}->[0] eq 'aragusa', 'Correct created_by username loaded.');
ok($vrf->last_modified_by->{usernames}->[0] eq 'aragusa', 'Correct last_modified_by username loaded.');

ok($vrf->name eq 'Test_4', 'Correct name loaded.');
ok($vrf->description eq 'Test_4', 'Correct description loaded.');
