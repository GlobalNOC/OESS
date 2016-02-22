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

use Test::More tests => 4;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

#my $res;
# try editing a circuit when acl rule will block you
my $res = $db->edit_circuit(
    'circuit_id' => 51,
    'description' => "Test",
    'bandwidth' => 1337,
    'provision_time' => 1377716981,
    'remove_time' => 1380308981,
    'links' => ['Link 181', 'Link 191', 'Link 531'],
    'backup_links' => [],
    'nodes' => ['Node 11', 'Node 51'], 
    'interfaces' => ['e15/1', 'e15/1'],
    'tags' => [1,1],
    'user_name' => 'aragusa',
    'workgroup_id' => 11,
    'external_id' => undef
);
ok(!$res, 'authorization check');
is($db->get_error(),'Interface "e15/1" on endpoint "Node 11" with VLAN tag "1" is not allowed for this workgroup.','correct error');

$res = $db->edit_circuit(
    'circuit_id' => 51,
    'description' => "Test",
    'loop_node' => undef,
    'bandwidth' => 1337,
    'provision_time' => 1377716981,
    'remove_time' => 1380308981,
    'links' => ['Link 181', 'Link 191', 'Link 531'],
    'backup_links' => [],
    'nodes' => ['Node 11', 'Node 51'], 
    'interfaces' => ['e1/1', 'e15/1'],
    'tags' => [3,3],
    'user_name' => 'aragusa',
    'workgroup_id' => 11,
    'external_id' => undef
);

ok($res->{'success'}, "circuit successfully edited");

$res = $db->get_circuit_details(
    circuit_id => $res->{'circuit_id'},
);


# delete the name since that's randomly generated
delete $res->{'name'};
# delete last edited since that changes
delete $res->{'last_edited'};
# delete internal ids
delete $res->{'internal_ids'};

my $correct_result = {
          'static_mac' => 0,
          'remote_requester' => undef,
          'remote_url' => undef,
          'external_identifier' => undef,
          'last_modified_by' => {
                                  'email' => 'user_11@foo.net',
                                  'is_admin' => '0',
                                  'auth_id' => 970,
                                  'type' => 'normal',
                                  'given_names' => 'User 11',
                                  'user_id' => 11,
                                  'family_name' => 'User 11',
                                  'auth_name' => 'aragusa',
                                  'status' => 'active'
                                },
          'state' => 'active',
          'loop_node' => undef,
          'backup_links' => [],
          'created_on' => '09/30/2012 00:11:09',
          'links' => [
                       {
                         'interface_z' => 'e3/2',
                         'port_no_z' => '98',
                         'node_z' => 'Node 11',
                         'port_no_a' => '97',
                         'node_a' => 'Node 61',
                         'name' => 'Link 181',
                         'interface_z_id' => '851',
                         'interface_a_id' => '161',
                         'interface_a' => 'e3/1'
                       },
                       {
                         'interface_z' => 'e1/1',
                         'port_no_z' => '1',
                         'node_z' => 'Node 51',
                         'port_no_a' => '1',
                         'node_a' => 'Node 61',
                         'name' => 'Link 191',
                         'interface_z_id' => '61',
                         'interface_a_id' => '171',
                         'interface_a' => 'e1/1'
                       },
                       {
                         'interface_z' => 'e3/2',
                         'port_no_z' => '98',
                         'node_z' => 'Node 51',
                         'port_no_a' => '97',
                         'node_a' => 'Node 5721',
                         'name' => 'Link 531',
                         'interface_z_id' => '71',
                         'interface_a_id' => '45781',
                         'interface_a' => 'e3/1'
                       }
                     ],
          'circuit_id' => 51,
          'workgroup_id' => '11',
          'description' => 'Test',
          'endpoints' => [
                           {
                             'local' => '1',
                             'node' => 'Node 11',
                             'interface_description' => 'e1/1',
                             'port_no' => '1',
                             'node_id' => '11',
                             'urn' => undef,
                             'interface' => 'e1/1',
                             'tag' => '3',
                             'role' => 'unknown',
                             'mac_addrs' => []
                           },
                           {
                             'local' => '1',
                             'node' => 'Node 51',
                             'interface_description' => 'e15/1',
                             'port_no' => '673',
                             'node_id' => '51',
                             'urn' => undef,
                             'interface' => 'e15/1',
                             'tag' => '3',
                             'role' => 'unknown',
                             'mac_addrs' => []
                           }
                         ],
          'workgroup' => {
                           'workgroup_id' => '11',
                           'external_id' => undef,
                           'name' => 'Workgroup 11',
                           'status' => 'active',
                           'type' => 'admin',
                           'description' => '',
                           'max_circuits' => 44,
                           'max_mac_address_per_end' => 10,
                           'max_circuit_endpoints' => 10
                         },
          'active_path' => 'primary',
          'bandwidth' => 1337,
          'user_id' => '11',
          'restore_to_primary' => '0',
          'operational_state' => 'unknown',
          'created_by' => {
                            'email' => 'user_201@foo.net',
                            'is_admin' => '0',
                            'auth_id' => '191',
                            'type' => 'normal',
                            'given_names' => 'User 201',
                            'user_id' => '201',
                            'family_name' => 'User 201',
                            'auth_name' => 'user_201@foo.net',
                            'status' => 'active'
                          }
};

warn Dumper($res);

cmp_deeply($res, $correct_result, "values for circuit matches");
