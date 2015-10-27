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

use Test::More tests => 5;
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
                          status => 'active',
                          type => 'normal');
                        
ok(defined($user), "User updated");

#OESSDatabaseTester::workgroupLimits( workgroup_id => 11, 
#                                     db => $db,
#                                     circuit_num => 1);

#my $res;
# try provisioning a circuit when acl rules block you 
my $res = $db->provision_circuit(
    'state' => 'reserved',
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

$res = $db->provision_circuit(
    'state' => 'reserved',
    'description' => "Test",
    'bandwidth' => 1337,
    'provision_time' => 1377716981,
    'remove_time' => 1380308981,
    'links' => ['Link 181', 'Link 191', 'Link 531'],
    'backup_links' => [],
    'nodes' => ['Node 11', 'Node 51'], 
    'interfaces' => ['e1/1', 'e15/1'],
    'tags' => [10,10],
    'user_name' => 'aragusa',
    'workgroup_id' => 11,
    'external_id' => undef
);

ok($res->{'success'}, "circuit successfully added");
#print "Status: ".Dumper($res);

$res = $db->get_circuit_details(
    circuit_id => $res->{'circuit_id'},
);
delete $res->{'last_modified_by'};
my $correct_result =  {
          'external_identifier' => undef,
          'state' => 'reserved',
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
                             'tag' => '10',
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
                             'tag' => '10',
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
			   'max_circuits' => 144,
			   'max_mac_address_per_end' => 10,
               'max_circuit_endpoints' => 10
                         },
                   'active_path' => 'primary',
                   'bandwidth' => '1337',
                   'internal_ids' => {
                       'primary' => {
                           'Node 11' => {
                               '851' => '105'
                           },
                                   'Node 5721' => {
                                       '45781' => '29'
                               },
                                           'Node 61' => {
                                               '161' => '135',
                                               '171' => '108'
                                       },
                                                   'Node 51' => {
                                                       '71' => '102',
                                                       '61' => '105'
                                               }
                       }
               },
          'user_id' => '11',
          'restore_to_primary' => '0',
          'operational_state' => 'unknown'
};

# delete the name since that's randomly generated
delete $res->{'name'};
# delete last edited since that changes
delete $res->{'last_edited'};
# delete the circuit_id since that's liable to change with the addition of tests
warn $res->{'circuit_id'};
delete $res->{'circuit_id'};

warn Data::Dumper::Dumper($correct_result);
warn Data::Dumper::Dumper($res);
cmp_deeply($res, $correct_result, "values for circuit matches");
