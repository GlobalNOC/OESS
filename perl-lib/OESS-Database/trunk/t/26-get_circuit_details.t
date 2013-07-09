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

cmp_deeply($res,{
    'last_modified_by' => {
                                  'email' => 'user_221@foo.net',
                                  'is_admin' => '0',
                                  'auth_id' => '211',
                                  'given_names' => 'User 221',
                                  'user_id' => '221',
                                  'family_name' => 'User 221',
                                  'auth_name' => 'user_221@foo.net'
    },
          'state' => 'active',
          'backup_links' => [
	      {
                                'interface_z' => 'e1/2',
                                'port_no_z' => '2',
                                'node_z' => 'Node 21',
                                'port_no_a' => '97',
                                'node_a' => 'Node 31',
                                'name' => 'Link 1',
                                'interface_a' => 'e3/1'
	      },
	      {
                                'interface_z' => 'e5/1',
                                'port_no_z' => '193',
                                'node_z' => 'Node 101',
                                'port_no_a' => '97',
                                'node_a' => 'Node 21',
                                'name' => 'Link 21',
                                'interface_a' => 'e3/1'
	      },
	      {
                                'interface_z' => 'e3/2',
                                'port_no_z' => '98',
                                'node_z' => 'Node 111',
                                'port_no_a' => '98',
                                'node_a' => 'Node 91',
                                'name' => 'Link 211',
                                'interface_a' => 'e3/2'
	      },
	      {
                                'interface_z' => 'e3/1',
                                'port_no_z' => '97',
                                'node_z' => 'Node 101',
                                'port_no_a' => '97',
                                'node_a' => 'Node 91',
                                'name' => 'Link 231',
                                'interface_a' => 'e3/1'
	      }
                            ],
          'links' => [
	      {
                         'interface_z' => 'e1/1',
                         'port_no_z' => '1',
                         'node_z' => 'Node 111',
                         'port_no_a' => '1',
                         'node_a' => 'Node 31',
                         'name' => 'Link 221',
                         'interface_a' => 'e1/1'
	      }
                     ],
          'circuit_id' => 3731,
          'workgroup_id' => '251',
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
                             'role' => 'unknown'
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
                             'role' => 'unknown'
	      }
                         ],
    'workgroup' => {
                           'workgroup_id' => '251',
                           'external_id' => '',
                           'name' => 'Workgroup 251',
                           'type' => 'normal',
                           'description' => ''
    },
          'active_path' => 'primary',
          'bandwidth' => '0',
			       'internal_ids' => {
				   'primary' => {
                                             'Node 31' => '108',
                                             'Node 111' => '114'
				   },
						 'backup' => {
                                            'Node 91' => '114',
                                            'Node 31' => '109',
                                            'Node 101' => '125',
                                            'Node 111' => '115',
                                            'Node 21' => '120'
					     }
			   },
          'last_edited' => '2/22/2013 18:1:26',
          'user_id' => '221',
          'restore_to_primary' => '0',
          'operational_state' => 'unknown'
	   });

$res = $db->get_circuit_details_by_name( name => 999999999 );
ok(!defined($res), "fails to list details of  non-existng circuit");
