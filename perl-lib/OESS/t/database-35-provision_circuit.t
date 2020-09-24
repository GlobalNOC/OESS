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

use Test::More tests => 13;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

# Ensure user is active.
my $user = $db->edit_user(user_id => '11',
                          given_name => 'User 11',
                          family_name => 'User 11',
                          email_address => 'user_11@foo.net',
                          auth_names => ['aragusa'],
                          status => 'active');
ok(defined($user), "User updated");


#
# BEGIN Trunk: provision_circuit tests
#


my $valid_vlan = 99;
my $invalid_vlan = 150;

my $trunk_iface = 'e3/1';
my $trunk_iface_id = 51;
my $trunk_iface_node = 'Node 51';
my $trunk_iface_node_id = 51;
my $trunk_iface_workgroup_id = 11;

my $user_id = 11;
$user = $db->get_user_by_id(user_id => $user_id)->[0];

# Try provisioning a circuit when node VLAN rules block you
my $res = $db->provision_circuit('description' => "Trunk test",
                                 'bandwidth' => 1337,
                                 'provision_time' => -1,
                                 'remove_time' => -1,
                                 'links' => ['Link 181', 'Link 191', 'Link 531'],
                                 'backup_links' => [],
                                 'nodes' => ['Node 11', $trunk_iface_node], 
                                 'type' => 'openflow',
                                 'interfaces' => ['e1/1', $trunk_iface],
                                 'tags' => [1, $invalid_vlan],
                                 'user_name' => $user->{'auth_name'},
                                 'workgroup_id' => $trunk_iface_workgroup_id,
                                 'external_id' => undef);
my $err = $db->get_error();
ok(!$res, "Authorization check");
ok(defined $err, "Error: $err");

# Try provisioning a circuit when workgroup doesn't own trunk interface
$res = $db->provision_circuit('description' => "Trunk test",
                              'bandwidth' => 1337,
                              'provision_time' => -1,
                              'remove_time' => -1,
                              'links' => ['Link 181', 'Link 191', 'Link 531'],
                              'backup_links' => [],
                              'nodes' => ['Node 11', $trunk_iface_node], 
                              'type' => 'openflow',
                              'interfaces' => ['e1/1', $trunk_iface],
                              'tags' => [1, $valid_vlan],
                              'user_name' => $user->{'auth_name'},
                              'workgroup_id' => $trunk_iface_workgroup_id + 1,
                              'external_id' => undef);
$err = $db->get_error();
ok(!$res, "Authorization check");
ok(defined $err, "Error: $err");

$db->update_interface_owner(interface_id =>$trunk_iface_id,
                            workgroup_id => $trunk_iface_workgroup_id);

# Provision trunk circuit using valid VLANs and credentials
$res = $db->provision_circuit('description' => "Trunk test",
                              'bandwidth' => 1337,
                              'provision_time' => -1,
                              'remove_time' => -1,
                              'links' => ['Link 181', 'Link 191', 'Link 531'],
                              'type' => 'openflow',
                              'backup_links' => [],
                              'nodes' => ['Node 11', $trunk_iface_node], 
                              'interfaces' => ['e1/1', $trunk_iface],
                              'tags' => [1, $valid_vlan],
                              'user_name' => $user->{'auth_name'},
                              'workgroup_id' => $trunk_iface_workgroup_id,
                              'external_id' => undef);
$err = $db->get_error();
ok($res, "Trunk circuit provisioned. $err");

my $trunk_circuit_id = $res->{'circuit_id'};

$res = $db->get_circuit_details(circuit_id => $trunk_circuit_id);
ok($res, "Retreived trunk circuit.");

delete $res->{'last_modified_by'};
delete $res->{'created_by'};
delete $res->{'name'};
delete $res->{'last_edited'};
delete $res->{'circuit_id'};
delete $res->{'created_on'};
delete $res->{'paths'};
my $correct_trunk_result = {
                            'remote_requester' => undef,
                            'external_identifier' => undef,
                            'state' => 'active',
                            'backup_links' => [],
                            'remote_url' => undef,
                            'loop_node' => undef,
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
                                         'interface_a' => 'e3/1',
                                         'ip_a' => undef,
                                         'ip_z' => undef,
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
                                         'interface_a' => 'e1/1',
                                         'ip_a' => undef,
                                         'ip_z' => undef,
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
                                         'interface_a' => 'e3/1',
                                         'ip_a' => undef,
                                         'ip_z' => undef,
                                        }
                                       ],
                            'static_mac' => '0',
                            'workgroup_id' => '11',
                            'description' => 'Trunk test',
                            'endpoints' => [
                                            {
                                             'local' => '1',
                                             'node' => 'Node 11',
					     'interface_id' => 321,
                                             'mac_addrs' => [],
                                             'interface_description' => 'e1/1',
                                             'port_no' => '1',
                                             'node_id' => '11',
                                             'urn' => undef,
                                             'interface' => 'e1/1',
                                             'unit' => '1',
                                             'inner_tag' => undef,
                                             'tag' => '1',
                                             'role' => 'unknown'
                                            },
                                            {
                                             'local' => '1',
                                             'node' => 'Node 51',
					     'interface_id' => 51,
                                             'mac_addrs' => [],
                                             'interface_description' => 'e3/1',
                                             'port_no' => '97',
                                             'node_id' => '51',
                                             'urn' => undef,
                                             'interface' => 'e3/1',
                                             'unit' => '99',
                                             'inner_tag' => undef,
                                             'tag' => '99',
                                             'role' => 'trunk'
                                            }
                                           ],
                            'workgroup' => {
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
                            'active_path' => 'primary',
                            'bandwidth' => '1337',
                            'internal_ids' => {
                                               'primary' => {
                                                             'Node 11' => {
                                                                           '851' => '104'
                                                                          },
                                                             'Node 5721' => {
                                                                             '45781' => '29'
                                                                            },
                                                             'Node 61' => {
                                                                           '161' => '107',
                                                                           '171' => '106'
                                                                          },
                                                             'Node 51' => {
                                                                           '71' => '102',
                                                                           '61' => '104'
                                                                          }
                                                            }
                                              },
                            'user_id' => '11',
                            'restore_to_primary' => '0',
                            'operational_state' => 'up',
                            'tertiary_links' => [],
                            'type' => 'openflow'
                           };
cmp_deeply($res, $correct_trunk_result, "Values for trunk circuit matches");

# Clean up trunk circuit
$res = $db->remove_circuit(circuit_id => $trunk_circuit_id,
                           remove_time => -1,
                           username => $user->{'auth_name'});
ok($res, "Trunk circuit removed.");


#
# BEGIN: provision_circuit tests
#


# try provisioning a circuit when acl rules block you 
$res = $db->provision_circuit(
    'description' => "Test",
    'bandwidth' => 1337,
    'provision_time' => -1,
    'remove_time' => -1,
    'links' => ['Link 181', 'Link 191', 'Link 531'],
    'backup_links' => [],
    'nodes' => ['Node 11', 'Node 51'], 
    'interfaces' => ['e15/1', 'e15/1'],
    'tags' => [1,1],
    'type' => 'openflow',
    'user_name' => 'aragusa',
    'workgroup_id' => 11,
    'external_id' => undef
);
ok(!$res, 'authorization check');
is($db->get_error(),'Interface "e15/1" on endpoint "Node 11" with VLAN tag "1" is not allowed for this workgroup.','correct error');

$res = $db->provision_circuit(
    'description' => "Test",
    'bandwidth' => 1337,
    'provision_time' => -1,
    'remove_time' => -1,
    'links' => ['Link 181', 'Link 191', 'Link 531'],
    'backup_links' => [],
    'nodes' => ['Node 11', 'Node 51'], 
    'interfaces' => ['e1/1', 'e15/1'],
    'type' => 'openflow',
    'tags' => [1,1],
    'user_name' => 'aragusa',
    'workgroup_id' => 11,
    'external_id' => undef
);

ok($res->{'success'}, "circuit successfully added");

$res = $db->get_circuit_details(
    circuit_id => $res->{'circuit_id'},
                               );
warn Dumper($res);
delete $res->{'last_modified_by'};
delete $res->{'created_on'};
delete $res->{'paths'};
my $correct_result =  {
          'external_identifier' => undef,
          'state' => 'active',
          'remote_requester' => undef,
          'remote_url' => undef,
          'static_mac' => 0,
          'backup_links' => [],
          'loop_node' => undef,
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
                         'interface_a' => 'e3/1',
                         'ip_a' => undef,
                         'ip_z' => undef,
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
                         'interface_a' => 'e1/1',
                         'ip_a' => undef,
                         'ip_z' => undef,
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
                         'interface_a' => 'e3/1',
                         'ip_a' => undef,
                         'ip_z' => undef,
                       }
                     ],
          'workgroup_id' => '11',
          'description' => 'Test',
          'endpoints' => [
                           {
                             'local' => '1',
                             'node' => 'Node 11',
			     'interface_id' => 321,
                             'interface_description' => 'e1/1',
                             'port_no' => '1',
                             'node_id' => '11',
                             'urn' => undef,
                             'unit' => '1',
                             'inner_tag' => undef,
                             'interface' => 'e1/1',
                             'tag' => '1',
                             'role' => 'unknown',
                             'mac_addrs' => []
                           },
                           {
                             'local' => '1',
                             'node' => 'Node 51',
			     'interface_id' => 511,
                             'interface_description' => 'e15/1',
                             'port_no' => '673',
                             'node_id' => '51',
                             'urn' => undef,
                             'interface' => 'e15/1',
                             'unit' => '1',
                             'inner_tag' => undef,
                             'tag' => '1',
                             'role' => 'unknown',
                             'mac_addrs' => []
                           }
                         ],
          'workgroup' => {
                           'workgroup_id' => '11',
                           'external_id' => undef,
                           'status' => 'active',
                           'name' => 'Workgroup 11',
                           'type' => 'admin',
                           'description' => '',
			   'max_circuits' => 44,
			   'max_mac_address_per_end' => 10,
               'max_circuit_endpoints' => 10
                         },
          'active_path' => 'primary',
          'bandwidth' => '1337',
          'internal_ids' => {
                              'primary' => {
                                  'Node 11' => {
                                      '851' => '104'
                                  },
                                          'Node 5721' => {
                                              '45781' => '29'
                                      },
                                                  'Node 61' => {
                                                      '161' => '107',
                                                      '171' => '106'
                                              },
                                                          'Node 51' => {
                                                              '71' => '102',
                                                              '61' => '104'
                                                      }
                              }
      },

          'user_id' => '11',
          'restore_to_primary' => '0',
          'operational_state' => 'up',
          'created_by' => {
                                  'status' => 'active',
                                  'auth_id' => '962',
                                  'family_name' => 'User 11',
                                  'email' => 'user_11@foo.net',
                                  'is_admin' => '0',
                                  'user_id' => '11',
                                  'given_names' => 'User 11',
                                  'auth_name' => 'aragusa'
                                },
          'tertiary_links' => [],
          'type' => 'openflow'
};

# delete the name since that's randomly generated
delete $res->{'name'};
# delete last edited since that changes
delete $res->{'last_edited'};
# delete the circuit_id since that's liable to change with the addition of tests
warn $res->{'circuit_id'};
delete $res->{'circuit_id'};

#warn Data::Dumper::Dumper($correct_result);
#warn Data::Dumper::Dumper($res);
cmp_deeply($res, $correct_result, "values for circuit matches");
