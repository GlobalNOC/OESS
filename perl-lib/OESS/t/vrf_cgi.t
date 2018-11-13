#!/usr/bin/perl

#use strict;

use warnings;
use Data::Dumper;
use GRNOC::Config;
use GRNOC::WebService::Client;
use Test::More tests=>23;
use Test::Deep;
use OESS::DB::Entity ;
use OESS::DB;
use Log::Log4perl;
use OESS::Interface;
# Initialize logging
Log::Log4perl->init("/etc/oess/logging.conf");

#OESS::DB::Entity->import(get_entities);

my $db = OESS::DB->new();
my $interface_id = 391;
my $workgroup_id = 11;
my $interface = OESS::Interface->new(interface_id=>$interface_id, db=>$db);
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


cmp_deeply($svc->get_vrf_details(vrf_id => 1),
{
          'results' => [
                         {
                           'name' => 'Test',
                           'last_modified_by' => {
                                                   'email' => 'user_1@foo.net',
                                                   'is_admin' => '0',
                                                   'user_id' => '1',
                                                   'type' => 'normal',
                                                   'workgroups' => [],
                                                   'first_name' => 'User 1',
                                                   'last_name' => 'User 1'
                                                 },
                           'last_modified' => '0',
                           'vrf_id' => '1',
                           'description' => 'Test',
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
                                                                'cloud_interconnect_id' => undef,
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
                                             'email' => 'user_1@foo.net',
                                             'is_admin' => '0',
                                             'user_id' => '1',
                                             'type' => 'normal',
                                             'workgroups' => [],
                                             'first_name' => 'User 1',
                                             'last_name' => 'User 1'
                                           },
                           'operational_state' => 'up'
                         }
                       ]
        }, "The method get_vrf_details() gives expected output when vrf exists (vrf_id = 1).");
#warn Dumper($db->execute_query("SELECT * FROM vrf LIMIT 2"));
ok ( undef == $svc->get_vrf_details(vrf_id => 9999), "The method get_vrf_details() returns expected value when vrf_id is not in database.");

cmp_deeply($svc->get_vrf_details(vrf_id => undef),
{
          'error_text' => 'get_vrf_details: input parameter vrf_id cannot be NULL ',
          'error' => 1,
          'results' => undef
        }, "The method get_vrf_details() returns expected output when parameter vvrf_id is undefined.");

#warn Dumper($db->execute_query("SELECT * FROM vrf_ep_peer LIMIT 1"));

#get_vrf_details

warn Dumper($svc->get_vrfs(workgroup_id => 21));
#get_vrfs
#provision
#remove

