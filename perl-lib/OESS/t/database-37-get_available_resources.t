#!/usr/bin/perl -T

use strict;

use FindBin;
my $path;

BEGIN {
    if($FindBin::Bin =~ /(.*)/){
        $path = $1;
    }
}

use lib "$path";
use OESSDatabaseTester;

use Test::More tests => 3;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $cpath = OESSDatabaseTester::getConfigFilePath();
warn "$cpath";
my $db = OESS::Database->new(config => $cpath);

#my $res;
# try editing a circuit when acl rule will block you
my $res = $db->get_available_resources(
    'workgroup_id' => 21,
);
ok($res, 'query ok');
is(@$res, 6, 'count');

my $correct_result = [
    {
            'interface_name' => 'e15/1',
            'remote_links' => [],
            'node_name' => 'Node 21',
            'owning_workgroup' => {
                                    'workgroup_id' => '1',
                                    'status' => 'active',
                                    'name' => 'Workgroup 1',
                                    'max_circuit_endpoints' => '10',
                                    'description' => '',
                                    'max_circuits' => '20',
                                    'external_id' => undef,
                                    'type' => 'normal',
                                    'max_mac_address_per_end' => '10'
            },
            'interface_id' => '45901',
            'description' => 'e15/1',
            'is_owner' => 0,
            'vlan_tag_range' => '1-100,201-4095',
            'node_id' => '21',
            'operational_state' => 'up'
    },
{                                                                                                               
            'interface_name' => 'e3/1',
            'remote_links' => [],
            'node_name' => 'Node 51',
            'owning_workgroup' => {
                                    'workgroup_id' => '11',
                                    'status' => 'active',
                                    'name' => 'Workgroup 11',
                                    'max_circuit_endpoints' => '10',
                                    'description' => '',
                                    'max_circuits' => '44',
                                    'external_id' => undef,
                                    'type' => 'admin',
                                    'max_mac_address_per_end' => '10'
            },
            'interface_id' => '51',
            'description' => 'e3/1',
            'is_owner' => 0,
            'vlan_tag_range' => '1-99,4095',
            'node_id' => '51',
            'operational_state' => 'up'
},
{                                                                                                               
            'interface_name' => 'e15/7',
            'remote_links' => [],
            'node_name' => 'Node 81',
            'owning_workgroup' => {
                                    'workgroup_id' => '1',
                                    'status' => 'active',
                                    'name' => 'Workgroup 1',
                                    'max_circuit_endpoints' => '10',
                                    'description' => '',
                                    'max_circuits' => '20',
                                    'external_id' => undef,
                                    'type' => 'normal',
                                    'max_mac_address_per_end' => '10'
            },
            'interface_id' => '45571',
            'description' => 'e15/7',
            'is_owner' => 0,
            'vlan_tag_range' => '1-4095',
            'node_id' => '81',
            'operational_state' => 'up'
},
{                                                                                                              
            'interface_name' => 'e1/1',
            'remote_links' => [
                {
                                  'vlan_tag_range' => undef,
                                  'remote_urn' => 'urn:ogf:network:domain=ion.internet2.edu:node=rtr.losa:port=ae1:link=al2s'
                }
                              ],
            'node_name' => 'Node 11',
            'interface_id' => '321',
            'description' => 'e1/1',
            'cloud_interconnect_id' => undef,
            'cloud_interconnect_type' => undef,
            'is_owner' => 1,
            'vlan_tag_range' => '1-4095',
            'node_id' => '11',
            'operational_state' => 'up'
},
{
            'interface_name' => 'e15/1',
            'remote_links' => [],
            'node_name' => 'Node 11',
            'interface_id' => '391',
            'description' => 'e15/1',
            'is_owner' => 1,
            'cloud_interconnect_id' => undef,
            'cloud_interconnect_type' => undef,
            'vlan_tag_range' => '1-4095',
            'node_id' => '11',
            'operational_state' => 'up'
},
{
            'interface_name' => 'e15/1',
            'remote_links' => [],
            'node_name' => 'Node 51',
            'interface_id' => '511',
            'description' => 'e15/1',
            'is_owner' => 1,
            'cloud_interconnect_id' => undef,
            'cloud_interconnect_type' => undef,
            'vlan_tag_range' => '1-4095',
            'node_id' => '51',
            'operational_state' => 'up'
}
    ];

warn Dumper($res);
warn "---";
warn Dumper($correct_result);

my ($ok, $stack) = Test::Deep::cmp_details($res, $correct_result);
if (!$ok) {
    my $err = Test::Deep::deep_diag($stack);
    warn "$err";
}

ok($ok, "Values for resources match.");
