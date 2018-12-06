#!/usr/bin/perl -T

#use strict;

use warnings;
use Data::Dumper;
use GRNOC::Config;
use GRNOC::WebService::Client;
use Test::More tests=>7;
use Test::Deep;
use OESS::DB;
use Log::Log4perl;
use OESS::Interface;
use OESS::Endpoint;

# Initialize logging
Log::Log4perl->init("/etc/oess/logging.conf");
use JSON;

my $db = OESS::DB->new();
my $workgroup_id = 11;
my $config_path = "/etc/oess/database.xml";
my $config = GRNOC::Config->new(config_file=> $config_path);
my $url = ($config->get("/config"))[0][0]->{'base_url'};
my $username = ($config->get("/config/cloud"))[0][0]->{'user'};
my $password = ($config->get("/config/cloud"))[0][0]->{'password'};
my $svc =new  GRNOC::WebService::Client(
                        url     => $url."services/vrf.cgi",
                        uid     => $username,
                        passwd  => $password,
                        realm   => 'OESS',
                        debug   => 0
);

cmp_deeply($svc->get_vrf_details(vrf_id => 2),
{
          'results' => [
                         {
                           'name' => 'Test_2',
                           'last_modified_by' => {
                                                   'email' => 'user_881@foo.net',
                                                   'is_admin' => '0',
                                                   'user_id' => '881',
                                                   'type' => 'normal',
                                                   'workgroups' => [
                                                                     {
                                                                       'max_circuits' => '20',
                                                                       'workgroup_id' => '241',
                                                                       'external_id' => '',
                                                                       'interfaces' => undef,
                                                                       'name' => 'Workgroup 241',
                                                                       'type' => 'normal'
                                                                     }
                                                                   ],
                                                   'first_name' => 'User 881',
                                                   'last_name' => 'User 881'
                                                 },
                           'last_modified' => '0',
                           'vrf_id' => '2',
                           'description' => 'Test_2',
                           'state' => 'active',
                           'endpoints' => [],
                           'workgroup' => {
                                            'max_circuits' => '20',
                                            'workgroup_id' => '21',
                                            'external_id' => undef,
                                            'interfaces' => [
                                                              {
                                                                'cloud_interconnect_id' => undef,
                                                                'name' => 'e1/1',
                                                                'interface_id' => '321',
                                                                'description' => 'e1/1',
                                                                'node' => 'Node 11',
                                                                'cloud_interconnect_type' => undef,
                                                                'node_id' => '11',
                                                                'acls' => {
                                                                            'acls' => [
                                                                                        {
                                                                                          'workgroup_id' => '11',
                                                                                          'eval_position' => '10',
                                                                                          'entity_id' => undef,
                                                                                          'allow_deny' => 'allow',
                                                                                          'start' => '1',
                                                                                          'end' => '10'
                                                                                        }
                                                                                      ],
                                                                            'interface_id' => '321'
                                                                          },
                                                                'operational_state' => 'up'
                                                              },
                                                              {
                                                                'cloud_interconnect_id' => 'Test',
                                                                'name' => 'e15/1',
                                                                'interface_id' => '391',
                                                                'description' => 'e15/1',
                                                                'node' => 'Node 11',
                                                                'cloud_interconnect_type' => undef,
                                                                'node_id' => '11',
                                                                'acls' => {
                                                                            'acls' => [
                                                                                        {
                                                                                          'workgroup_id' => '11',
                                                                                          'eval_position' => '10',
                                                                                          'entity_id' => '7',
                                                                                          'allow_deny' => 'deny',
                                                                                          'start' => '1',
                                                                                          'end' => undef
                                                                                        },
                                                                                        {
                                                                                          'workgroup_id' => '11',
                                                                                          'eval_position' => '20',
                                                                                          'entity_id' => '7',
                                                                                          'allow_deny' => 'allow',
                                                                                          'start' => '1',
                                                                                          'end' => '4095'
                                                                                        }
                                                                                      ],
                                                                            'interface_id' => '391'
                                                                          },
                                                                'operational_state' => 'up'
                                                              },
                                                              {
                                                                'cloud_interconnect_id' => undef,
                                                                'name' => 'e15/1',
                                                                'interface_id' => '511',
                                                                'description' => 'e15/1',
                                                                'node' => 'Node 51',
                                                                'cloud_interconnect_type' => undef,
                                                                'node_id' => '51',
                                                                'acls' => {
                                                                            'acls' => [
                                                                                        {
                                                                                          'workgroup_id' => '11',
                                                                                          'eval_position' => '10',
                                                                                          'entity_id' => undef,
                                                                                          'allow_deny' => 'allow',
                                                                                          'start' => '1',
                                                                                          'end' => '10'
                                                                                        }
                                                                                      ],
                                                                            'interface_id' => '511'
                                                                          },
                                                                'operational_state' => 'up'
                                                              }
                                                            ],
                                            'name' => 'Workgroup 21',
                                            'type' => 'normal'
                                          },
                           'local_asn' => '7',
                           'created' => '1',
                           'prefix_limit' => 1000,
                           'created_by' => {
                                             'email' => 'user_881@foo.net',
                                             'is_admin' => '0',
                                             'user_id' => '881',
                                             'type' => 'normal',
                                             'workgroups' => [
                                                               {
                                                                 'max_circuits' => '20',
                                                                 'workgroup_id' => '241',
                                                                 'external_id' => '',
                                                                 'interfaces' => undef,
                                                                 'name' => 'Workgroup 241',
                                                                 'type' => 'normal'
                                                               }
                                                             ],
                                             'first_name' => 'User 881',
                                             'last_name' => 'User 881'
                                           },
                           'operational_state' => 'up'
                         }
                       ]
        }, "The method get_vrf_details() gives expected output when vrf exists (vrf_id = 1).");

ok ( undef eq  $svc->get_vrf_details(vrf_id => 9999), "The method get_vrf_details() returns expected value when vrf_id is not in database.");

cmp_deeply($svc->get_vrf_details(vrf_id => undef),
{
          'error_text' => 'get_vrf_details: input parameter vrf_id cannot be NULL ',
          'error' => 1,
          'results' => undef
        }, "The method get_vrf_details() returns expected output when parameter vrf_id is undefined.");

my $temp_env_remote =  $ENV{'REMOTE_USER'};
$ENV{'REMOTE_USER'} = 'user_881@foo.net';
cmp_deeply($svc->get_vrfs(workgroup_id => 21),
[
          {
            'name' => 'Test_2',
            'last_modified_by' => {
                                    'email' => 'user_881@foo.net',
                                    'is_admin' => '0',
                                    'user_id' => '881',
                                    'type' => 'normal',
                                    'workgroups' => [
                                                      {
                                                        'max_circuits' => '20',
                                                        'workgroup_id' => '241',
                                                        'external_id' => '',
                                                        'interfaces' => undef,
                                                        'name' => 'Workgroup 241',
                                                        'type' => 'normal'
                                                      }
                                                    ],
                                    'first_name' => 'User 881',
                                    'last_name' => 'User 881'
                                  },
            'last_modified' => '0',
            'vrf_id' => '2',
            'description' => 'Test_2',
            'state' => 'active',
            'endpoints' => [],
            'workgroup' => {
                             'max_circuits' => '20',
                             'workgroup_id' => '21',
                             'external_id' => undef,
                             'interfaces' => [
                                               {
                                                 'cloud_interconnect_id' => undef,
                                                 'name' => 'e1/1',
                                                 'interface_id' => '321',
                                                 'description' => 'e1/1',
                                                 'node' => 'Node 11',
                                                 'cloud_interconnect_type' => undef,
                                                 'node_id' => '11',
                                                 'acls' => {
                                                             'acls' => [
                                                                         {
                                                                           'workgroup_id' => '11',
                                                                           'eval_position' => '10',
                                                                           'entity_id' => undef,
                                                                           'allow_deny' => 'allow',
                                                                           'start' => '1',
                                                                           'end' => '10'
                                                                         }
                                                                       ],
                                                             'interface_id' => '321'
                                                           },
                                                 'operational_state' => 'up'
                                               },
                                               {
                                                 'cloud_interconnect_id' => 'Test',
                                                 'name' => 'e15/1',
                                                 'interface_id' => '391',
                                                 'description' => 'e15/1',
                                                 'node' => 'Node 11',
                                                 'cloud_interconnect_type' => undef,
                                                 'node_id' => '11',
                                                 'acls' => {
                                                             'acls' => [
                                                                         {
                                                                           'workgroup_id' => '11',
                                                                           'eval_position' => '10',
                                                                           'entity_id' => '7',
                                                                           'allow_deny' => 'deny',
                                                                           'start' => '1',
                                                                           'end' => undef
                                                                         },
                                                                         {
                                                                           'workgroup_id' => '11',
                                                                           'eval_position' => '20',
                                                                           'entity_id' => '7',
                                                                           'allow_deny' => 'allow',
                                                                           'start' => '1',
                                                                           'end' => '4095'
                                                                         }
                                                                       ],
                                                             'interface_id' => '391'
                                                           },
                                                 'operational_state' => 'up'
                                               },
                                               {
                                                 'cloud_interconnect_id' => undef,
                                                 'name' => 'e15/1',
                                                 'interface_id' => '511',
                                                 'description' => 'e15/1',
                                                 'node' => 'Node 51',
                                                 'cloud_interconnect_type' => undef,
                                                 'node_id' => '51',
                                                 'acls' => {
                                                             'acls' => [
                                                                         {
                                                                           'workgroup_id' => '11',
                                                                           'eval_position' => '10',
                                                                           'entity_id' => undef,
                                                                           'allow_deny' => 'allow',
                                                                           'start' => '1',
                                                                           'end' => '10'
                                                                         }
                                                                       ],
                                                             'interface_id' => '511'
                                                           },
                                                 'operational_state' => 'up'
                                               }
                                             ],
                             'name' => 'Workgroup 21',
                             'type' => 'normal'
                           },
            'local_asn' => '7',
            'created' => '1',
            'prefix_limit' => 1000,
            'created_by' => {
                              'email' => 'user_881@foo.net',
                              'is_admin' => '0',
                              'user_id' => '881',
                              'type' => 'normal',
                              'workgroups' => [
                                                {
                                                  'max_circuits' => '20',
                                                  'workgroup_id' => '241',
                                                  'external_id' => '',
                                                  'interfaces' => undef,
                                                  'name' => 'Workgroup 241',
                                                  'type' => 'normal'
                                                }
                                              ],
                              'first_name' => 'User 881',
                              'last_name' => 'User 881'
                            },
            'operational_state' => 'up'
          }
        ], "The method get_vrfs() returns expected value for workgroup 21");
cmp_deeply($svc->get_vrfs(workgroup_id=>4444),
{
          'error_text' => 'User is not in workgroup',
          'error' => 1,
          'results' => undef
        }, "Method get_vrfs() gives expected results when a workgroup is out of range");


# Test permissions for provisioning
my $peer1 = OESS::Peer->new(vrf_peer_id =>1, db => $db,  asn=>1, key=>"3", oessPeerIP=>"1.1.1.1", yourPeerIP=>1000);
my $peer2 = OESS::Peer->new(vrf_peer_id =>1, db => $db,  asn=>1, key=>"3", oessPeerIP=>"1.1.1.2", yourPeerIP=>2000);
 my $json = {
        inner_tag           => undef,      # Inner VLAN tag (qnq only)
        tag                 => 391,       # Outer VLAN tag
        cloud_account_id    => '',         # AWS account or GCP pairing key
        cloud_connection_id => '',         # Probably shouldn't exist as an arg
        entity              => 'Big State TeraPOP', # Interfaces to select from
        bandwidth           => 100,        # Acts as an interface selector and validator
        workgroup_id        => 11,         # Acts as an interface selector and validator
        peerings            => [ $peer1, $peer2 ]
    };

my $ep = OESS::Endpoint->new(db=>$db, type=>'vrf', model=>$json);
$ep = $ep->to_hash();

## Altered interface and node as only interface name and node name are required while re-generating the Endpoint
$ep->{'interface'} = $ep->{'interface'}->{'name'};
$ep->{'node'} = $ep->{'node'}->{'name'}; 
$ep = encode_json($ep);

cmp_deeply($svc->provision(vrf_id=>100, name=>"Test_provision", workgroup_id=>9999, description=>"Test_provision",endpoint=>[$ep, $ep], local_asn=>2 ),
{
          'error_text' => 'User is not in workgroup',
          'error' => 1,
          'results' => undef
        },"The method provision() provides expected output when workgroup_id is not valid (workgroup_id = 9999)");

## Testingrif interface is blessed in ep
cmp_deeply($svc->provision( name=>"Test_provision", workgroup_id=>11, description=>"Test_provision",endpoint=>[$ep, $ep], local_asn=>2),
{
          'error_text' => 'error creating VRF: VLAN: 391 is not allowed for workgroup on interface: e15/1',
          'error' => 1,
          'results' => undef
       }, "The method provision performs in a expected manner when the VLAN is not available for given endpoint.");

$ENV{'REMOTE_USER'} = $temp_env_remote;

