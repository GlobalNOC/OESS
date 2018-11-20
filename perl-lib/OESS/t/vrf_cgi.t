#!/usr/bin/perl

#use strict;

use warnings;
use Data::Dumper;
use GRNOC::Config;
use GRNOC::WebService::Client;
use Test::More tests=>23;
use Test::Deep;
use OESS::DB::User ;
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
        }, "The method get_vrf_details() returns expected output when parameter vrf_id is undefined.");


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
#warn Dumper($db->execute_query("SELECT * FROM vrf_ep_peer LIMIT 1"));
cmp_deeply($svc->get_vrfs(workgroup_id=>4444),
{
          'error_text' => 'User is not in workgroup',
          'error' => 1,
          'results' => undef
        }, "Method get_vrfs() gives expected results when a workgroup is out of range");


my $temp_env_remote =  $ENV{'REMOTE_USER'};
$ENV{'REMOTE_USER'} = 'user_881@foo.net';
warn Dumper($svc->get_vrfs(workgroup_id=>21));
#warn Dumper($db->execute_query("select *  from remote_auth order by auth_id desc limit 1"));
my $user = OESS::DB::User::find_user_by_remote_auth( db => $db, remote_user => $ENV{'REMOTE_USER'} );
#warn Dumper($user);
$user = OESS::User->new(db => $db, user_id =>  $user->{'user_id'} );
warn Dumper($user->{'user_id'});
warn Dumper("Condition !user->in_workgroup(241) && !user->is_admin()");
warn Dumper(!$user->in_workgroup(241) && !$user->is_admin());
ok(!$user->in_workgroup(241) && !$user->is_admin(), "!user->in_workgroup(241) && !user->is_admin()");
warn Dumper(OESS::DB::VRF::get_vrfs( db => $db, workgroup_id => 241, state => 'active'));
#warn Dumper($db->execute_query("select * FROM user_workgroup_membership where user_id = 881"));
warn Dumper($db->execute_query("select * FROM user WHERE user_id = 881"));
#warn Dumper(OESS::DB::User::find_user_by_remote_auth( db => $db, remote_user => $ENV{'REMOTE_USER'} ));
warn Dumper("get_vrfs()");
#warn Dumper($svc->get_vrfs(workgroup_id => 21));
#warn Dumper($db->execute_query("SELECT * FROM vrf "));
#warn Dumper(OESS::DB::VRF::get_vrfs(db => $db, workgroup_id => 21, state => 'active'));
#warn Dumper(OESS::DB::Interface::get_interfaces(db => $db, workgroup_id => 21));
#$db->execute_query("INSERT INTO vrf VALUES (3,'Test_3', 'Test_3 get_vrfs', 241, 1, 1, 881,'".localtime()."', 881, 7 )");
#$db->execute_query("INSERT INTO vrf_ep VALUES (3, 3, 3, 3, 3, 3, 1, 1 )");
warn Dumper($db->execute_query("select distinct(vrf.vrf_id) from vrf join vrf_ep on vrf_ep.vrf_id = vrf.vrf_id where vrf.state = 'active' and workgroup_id = 241"));
#$db->execute_query("UPDATE vrf SET last_modified_by = 1, created_by= 1 where vrf_id = 1");
warn Dumper($db->execute_query("select * from vrf"));
$ENV{'REMOTE_USER'} = $temp_env_remote;
#get_vrfs
#provision
#remove

