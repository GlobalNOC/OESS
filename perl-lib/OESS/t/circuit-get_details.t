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
use OESS::Database;
use OESS::Circuit;
use OESSDatabaseTester;

use Test::More tests => 3;
use Test::Deep;
use Data::Dumper;

my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );

my $ckt = OESS::Circuit->new( circuit_id => 101, db => $db);

my $details = $ckt->get_details();

ok(defined($details), "Circuit details was defined");

ok($details->{'circuit_id'} == 101, "Circuit id matched what we expected");
warn Dumper($details);
cmp_deeply($details,{
    'last_modified_by' => {
        'status' => 'active',
        'email' => 'user_1@foo.net',
        'is_admin' => '0',
        'type' => 'normal',
        'auth_id' => undef,
        'given_names' => 'User 1',
        'user_id' => undef,
        'family_name' => 'User 1',
        'auth_name' => undef
    },
            'state' => 'active',
            'backup_links' => [],
            'created_on' => '09/30/2012 00:41:54',
            'loop_node' => undef,
            'links' => [
                {
                    'interface_z' => 'e1/1',
                    'port_no_z' => '1',
                    'node_z' => 'Node 21',
                    'port_no_a' => '2',
                    'node_a' => 'Node 81',
                    'name' => 'Link 41',
                    'interface_z_id' => '31',
                    'interface_a_id' => '131',
                    'interface_a' => 'e1/2'
                }
            ],
    'circuit_id' => 101,
    'remote_url' => undef,
    'remote_requester' => undef,
    'static_mac' => '0',
    'workgroup_id' => '11',
    'name' => 'Circuit 101',
    'description' => 'Circuit 101',
    'endpoints' => [
        {
            'local' => 1,
            'node' => 'Node 21',
            'mac_addrs' => [],
            'interface_description' => 'e15/2',
            'port_no' => '674',
            'node_id' => '21',
            'urn' => undef,
            'interface' => 'e15/2',
            'tag' => '105',
            'role' => 'unknown'
        },
        {
            'local' => 1,
            'node' => 'Node 81',
            'mac_addrs' => [],
            'interface_description' => 'e15/2',
            'port_no' => '674',
            'node_id' => '81',
            'urn' => undef,
            'interface' => 'e15/2',
            'tag' => '105',
            'role' => 'unknown'
        }
        ],
    'workgroup' => {
        'workgroup_id' => '11',
        'name' => 'Workgroup 11',
        'max_circuit_endpoints' => '10',
        'status' => 'active',
        'description' => '',
        'max_circuits' => '44',
        'external_id' => undef,
        'type' => 'admin',
        'max_mac_address_per_end' => '10'
    },
            'active_path' => 'primary',
            'bandwidth' => '0',
            
            'internal_ids' => {
                'primary' => {
                    'Node 21' => {
                        '31' => '101'
                    },
                            'Node 81' => {
                                '131' => '100'
                        }
                },
        },
    'external_identifier' => undef,
    'last_edited' => '09/30/2012 00:41:54',
    'user_id' => '1',
    'restore_to_primary' => '0',
    'operational_state' => 'up',
    'created_by' => {
        'status' => 'active',
        'email' => 'user_201@foo.net',
        'is_admin' => '0',
        'auth_id' => '191',
        'type' => 'normal',
        'given_names' => 'User 201',
        'user_id' => '201',
        'family_name' => 'User 201',
        'auth_name' => 'user_201@foo.net'
    }
           }, "Circuit details match");

