#!/usr/bin/perl -T

use strict;
use warnings;

use FindBin;
my $path;

BEGIN {
    if($FindBin::Bin =~ /(.*)/){
        $path = $1;
    }
}

use lib "$path";
use OESS::Database;
use OESS::Circuit;
use OESSDatabaseTester;

use Test::More tests => 6;
use Test::Deep;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $user_id = 11;
my $user = $db->get_user_by_id(user_id => $user_id)->[0];

my $ckt = OESS::Circuit->new(circuit_id => 4111, db => $db);
$ckt->{type} = 'mpls';


$db->_execute_query("update path_instantiation set end_epoch=unix_timestamp(now()) where path_instantiation.path_instantiation_id=9591");


# my $details = $db->get_circuit_details('circuit_id' => 4111);
# warn Dumper($details);

# my $tpaths = $db->get_circuit_paths(circuit_id => 4111);
# warn Dumper($tpaths);


my $r = $db->edit_circuit(
    'circuit_id' => 4111,
    'description' => 'Circuit 4111',
    'bandwidth' => '0',
    'workgroup_id' => '241',
    'provision_time' => -1,
    'restore_to_primary' => '0',
    'remove_time' => -1,
    'links' => [],
    'backup_links' => [],
    'nodes' => ['Node 21', 'Node 71'],
    'interfaces' => ['e15/5', 'e15/4'],
    'tags' => [4090, 2055],
    'static_mac' => '0',
    'state' => 'active',
    'user_name' => $user->{auth_name},
    'do_sanity_check' => 0
);

$ckt->update_mpls_path(
    reason => 'none',
    links  => [
        {
            'ip_z' => undef,
            'node_z' => 'Node 21',
            'node_a' => 'Node 31',
            'name' => 'Link 1',
            'interface_z' => 'e1/2',
            'port_no_a' => '97',
            'port_no_z' => '2',
            'ip_a' => undef,
            'interface_z_id' => '21',
            'interface_a' => 'e3/1',
            'interface_a_id' => '41',
            'link_id' => 1
          },
        {
            'ip_z' => undef,
            'node_z' => 'Node 111',
            'node_a' => 'Node 31',
            'name' => 'Link 221',
            'interface_z' => 'e1/1',
            'port_no_a' => '1',
            'port_no_z' => '1',
            'ip_a' => undef,
            'interface_z_id' => '281',
            'interface_a' => 'e1/1',
            'interface_a_id' => '871',
            'link_id' => 221
          }
    ]
);

my $response = $db->_execute_query("
    select * from path
    join path_instantiation on path.path_id=path_instantiation.path_id
    where path.circuit_id=? and path_instantiation.end_epoch=-1",
    [4111]
);

my $paths = {};
foreach my $r (@{$response}) {
    $paths->{$r->{path_type}} = $r;
}

ok($paths->{primary}->{end_epoch} == -1, "valid primary path instantiation exists");
ok($paths->{primary}->{path_state} eq 'decom', "primary path instantiation set as decom");

ok($paths->{backup}->{end_epoch} == -1, "valid backup path instantiation exists");
ok($paths->{backup}->{path_state} eq 'decom', "backup path instantiation set as decom");

ok($paths->{tertiary}->{end_epoch} == -1, "valid tertiary path instantiation exists");
ok($paths->{tertiary}->{path_state} eq 'active', "tertiary path instantiation set as active");
