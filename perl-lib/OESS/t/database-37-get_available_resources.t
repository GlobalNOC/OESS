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

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

#my $res;
# try editing a circuit when acl rule will block you
my $res = $db->get_available_resources(
    'workgroup_id' => 21,
);
ok($res, 'query ok');
is(@$res, 4, 'count');

#warn Dumper($res);

my $correct_result = [
    {
            'interface_name' => 'e15/1',
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
            'remote_links' => [],
            'description' => 'e15/1',
            'is_owner' => 0,
            'vlan_tag_range' => '-1,1-100,201-4095',
            'node_id' => '21',
            'operational_state' => 'up'
    },
    {
            'interface_name' => 'e1/1',
            'node_name' => 'Node 11',
            'interface_id' => '321',
            'description' => 'e1/1',
            'remote_links' => [
                {
                    'vlan_tag_range' => undef,
                    'remote_urn' => 'urn:ogf:network:domain=ion.internet2.edu:node=rtr.losa:port=ae1:link=al2s'}
                ],
                'is_owner' => 1,
            'vlan_tag_range' => '1-4095',
            'node_id' => '11',
            'operational_state' => 'up'
    },
    {
            'interface_name' => 'e15/1',
            'node_name' => 'Node 11',
            'interface_id' => '391',
            'description' => 'e15/1',
            'remote_links' => [],
            'is_owner' => 1,
            'vlan_tag_range' => '1-4095',
            'node_id' => '11',
            'operational_state' => 'up'
    },
    {
            'interface_name' => 'e15/1',
            'node_name' => 'Node 51',
            'interface_id' => '511',
            'description' => 'e15/1',
            'remote_links' => [],
            'is_owner' => 1,
            'vlan_tag_range' => '1-4095',
            'node_id' => '51',
            'operational_state' => 'up'
    }
    ];

cmp_deeply($res, $correct_result, "values for resources matches");
