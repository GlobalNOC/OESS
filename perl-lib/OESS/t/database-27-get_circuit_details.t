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

use Test::More tests => 6;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $res = $db->get_circuit_details();
ok(!defined($res), "No value returned when no cirucuit_id specified");

my $error = $db->get_error();
ok(!defined($error), "No Params were passed and we got an error back");

$res = $db->get_circuit_details( circuit_id => 3731 );
ok(defined($res), "Ciruit found and details are listed");
ok($res->{'circuit_id'} == 3731);

warn Dumper($res);

cmp_deeply($res,{
    'external_identifier' => undef,
    'last_modified_by' => {
                                  'email' => 'user_221@foo.net',
                                  'is_admin' => '0',
                                  'type' => 'normal',
                                  'auth_id' => '211',
                                  'given_names' => 'User 221',
                                  'user_id' => '221',
                                  'family_name' => 'User 221',
                                  'auth_name' => 'user_221@foo.net',
                                  'status' => 'active'
    },
          'static_mac' => 0,
          'state' => 'active',
          'backup_links' => [
              {
                  'interface_z' => 'e1/2',
                  'port_no_z' => '2',
                  'node_z' => 'Node 21',
                  'port_no_a' => '97',
                  'node_a' => 'Node 31',
                  'name' => 'Link 1',
                  'interface_z_id' => '21',
                  'interface_a_id' => '41',
                  'interface_a' => 'e3/1'
    },
              {
                  'interface_z' => 'e5/1',
                  'port_no_z' => '193',
                  'node_z' => 'Node 101',
                  'port_no_a' => '97',
                  'node_a' => 'Node 21',
                  'name' => 'Link 21',
                  'interface_z_id' => '221',
                  'interface_a_id' => '361',
                  'interface_a' => 'e3/1'
    },
              {
                  'interface_z' => 'e3/2',
                  'port_no_z' => '98',
                  'node_z' => 'Node 111',
                  'port_no_a' => '98',
                  'node_a' => 'Node 91',
                  'name' => 'Link 211',
                  'interface_z_id' => '271',
                  'interface_a_id' => '861',
                  'interface_a' => 'e3/2'
    },
              {
                  'interface_z' => 'e3/1',
                  'port_no_z' => '97',
                  'node_z' => 'Node 101',
                  'port_no_a' => '97',
                  'node_a' => 'Node 91',
                  'name' => 'Link 231',
                  'interface_z_id' => '231',
                  'interface_a_id' => '211',
                  'interface_a' => 'e3/1'
              }
          ],
    'loop_node' => undef,
    'links' => [
        {
            'interface_z' => 'e1/1',
            'port_no_z' => '1',
            'node_z' => 'Node 111',
            'port_no_a' => '1',
            'node_a' => 'Node 31',
            'name' => 'Link 221',
            'interface_z_id' => '281',
            'interface_a_id' => '871',
            'interface_a' => 'e1/1'
        }
        ],
          'circuit_id' => 3731,
          'workgroup_id' => '251',
    'remote_requester' => undef,
    'remote_url' => undef,
          'name' => 'Circuit 3731',
          'description' => 'Circuit 3731',
          'endpoints' => [
	      {
                             'local' => '1',
                             'node' => 'Node 111',
                             'interface_description' => 'e3/1',
                             'port_no' => '97',
                             'node_id' => '111',
                             'urn' => undef,
                             'interface' => 'e3/1',
                             'tag' => '104',
                             'role' => 'unknown',
                             'mac_addrs' => []
	      },
	      {
                             'local' => '1',
                             'node' => 'Node 31',
                             'interface_description' => 'e1/2',
                             'port_no' => '2',
                             'node_id' => '31',
                             'urn' => undef,
                             'interface' => 'e1/2',
                             'tag' => '2068',
                             'role' => 'unknown',
                             'mac_addrs' => []
	      }
                         ],
    'workgroup' => {
                           'max_circuits' => '20',
                           'workgroup_id' => '251',
                           'external_id' => '',
                           'status' => 'active',
                           'name' => 'Workgroup 251',
                           'type' => 'normal',
                           'description' => '',
                           'max_mac_address_per_end' => '10',
                           'max_circuit_endpoints' => '10'
    },
          'active_path' => 'primary',
                               'bandwidth' => '0',
                               'internal_ids' => {
                                   'primary' => {
                                       'Node 31' => {
                                           '871' => '108'
                                       },
                                               'Node 111' => {
                                                   '281' => '114'
                                           }
                                   },
                                   'backup' => {
                                       'Node 91' => {
                                           '861' => '114',
                                           '211' => '114'
                                       },
                                      'Node 31' => {
                                          '41' => '109'
                                  },
                                              'Node 101' => {
                                                  '231' => '125',
                                                  '221' => '125'
                                          },
                                                      'Node 111' => {
                                                          '271' => '115'
                                                  },
                                                              'Node 21' => {
                                                                  '21' => '120',
                                                                  '361' => '120'
                                                          }
                                   }

			   },
          'last_edited' => '02/22/2013 18:01:26',
          'user_id' => '221',
          'restore_to_primary' => '0',
          'operational_state' => 'up'
	   });

$res = $db->get_circuit_details_by_name( name => 999999999 );
ok(!defined($res), "fails to list details of  non-existng circuit");
