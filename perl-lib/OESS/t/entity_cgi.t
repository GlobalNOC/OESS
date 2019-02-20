#!/usr/bin/perl -T 

#use strict;

use warnings;
use GRNOC::Config;
use GRNOC::WebService::Client;
use Test::More skip_all => "Need to setup apache test";
use Test::Deep;
use OESS::DB::Entity ;
use OESS::DB;
use Log::Log4perl;
use OESS::Interface;
use FindBin;
# Initialize logging
Log::Log4perl->init("/etc/oess/logging.conf");

my $cwd;

BEGIN {
    if($FindBin::Bin =~ /(.*)/){
    $cwd = $1;
    }
}

my $interface_id = 391;
my $workgroup_id = 11;
my $interface = OESS::Interface->new(interface_id=>$interface_id, db=>$db);
my $config_path = "$cwd/conf/database.xml";
my $config = GRNOC::Config->new(config_file=> $config_path);
my $db = OESS::DB->new(config=>$config_path);
my $url = ($config->get("/config"))[0][0]->{'base_url'};
my $username = ($config->get("/config/cloud"))[0][0]->{'user'};
my $password = ($config->get("/config/cloud"))[0][0]->{'password'};
my $svc =new  GRNOC::WebService::Client(
                        url     => $url."services/entity.cgi",
                        uid     => $username,
                        passwd  => $password,
                        realm   => 'OESS',
                        debug   => 0 
);
my $root_entities = OESS::DB::Entity::get_root_entities(db => $db);
    
my @entities;
foreach my $ent (@$root_entities){
    push(@entities,$ent->to_hash());
}
cmp_deeply ($svc->get_root_entities() , 
{
          'results' => [
                         {
                           'contacts' => [],
                           'name' => 'Connectors',
                           'children' => [
                                           {
                                             'entity_id' => 8,
                                             'name' => 'Small State MilliPOP',
                                             'url' => 'https://smst.millipop.net/',
                                             'description' => undef,
                                             'logo_url' => undef
                                           },
                                           {
                                             'entity_id' => 7,
                                             'name' => 'Big State TeraPOP',
                                             'url' => 'https://terapop.example.net/',
                                             'description' => 'The R&E networking hub for Big State',
                                             'logo_url' => 'https://terapop.example.net/favicon.ico'
                                           }
                                         ],
                           'logo_url' => undef,
                           'description' => 'Those that are included in this classification',
                           'interfaces' => [],
                           'entity_id' => 2,
                           'url' => undef,
                           'parents' => [
                                          {
                                            'entity_id' => 1,
                                            'name' => 'root',
                                            'url' => 'ftp://example.net/pub/',
                                            'description' => 'The top of the hierarchy blah blah blah',
                                            'logo_url' => undef
                                          }
                                        ]
                         },
                         {
                           'contacts' => [],
                           'name' => 'Universities',
                           'children' => [
                                           {
                                             'entity_id' => 5,
                                             'name' => 'University of A',
                                             'url' => undef,
                                             'description' => undef,
                                             'logo_url' => 'https://a.example.edu/logo.png'
                                           },
                                           {
                                             'entity_id' => 6,
                                             'name' => 'B University',
                                             'url' => 'gopher://b.example.edu/',
                                             'description' => 'mascot: Wally B. from the 1980s short',
                                             'logo_url' => undef
                                           }
                                         ],
                           'logo_url' => undef,
                           'description' => 'Fabulous ones',
                           'interfaces' => [],
                           'entity_id' => 3,
                           'url' => undef,
                           'parents' => [
                                          {
                                            'entity_id' => 1,
                                            'name' => 'root',
                                            'url' => 'ftp://example.net/pub/',
                                            'description' => 'The top of the hierarchy blah blah blah',
                                            'logo_url' => undef
                                          }
                                        ]
                         },
                         {
                           'contacts' => [],
                           'name' => 'Cloud Providers',
                           'children' => [
                                           {
                                             'entity_id' => 9,
                                             'name' => 'Blue Cloud',
                                             'url' => 'http://bluecloud.com/special/custom-networking',
                                             'description' => '*Totally* not a parody of an actual cloud provider',
                                             'logo_url' => 'http://bluecloud.com/logo-anim.gif'
                                           },
                                           {
                                             'entity_id' => 10,
                                             'name' => 'Elasticloud',
                                             'url' => 'https://elasticloud.com/r-and-e-landing',
                                             'description' => 'It\'s elastic!',
                                             'logo_url' => undef
                                           }
                                         ],
                           'logo_url' => undef,
                           'description' => 'Those that belong to the emperor',
                           'interfaces' => [],
                           'entity_id' => 4,
                           'url' => undef,
                           'parents' => [
                                          {
                                            'entity_id' => 1,
                                            'name' => 'root',
                                            'url' => 'ftp://example.net/pub/',
                                            'description' => 'The top of the hierarchy blah blah blah',
                                            'logo_url' => undef
                                          }
                                        ]
                         }
                       ]
        }, "The method get_root_entities gives desired results.");

cmp_deeply($svc->get_entity_children(entity_id=>7),
{
          'results' => [
                         {
                           'contacts' => [],
                           'name' => 'EC Utopia',
                           'children' => [],
                           'logo_url' => undef,
                           'description' => 'Guess where this region is?',
                           'interfaces' => [],
                           'entity_id' => '16',
                           'url' => undef,
                           'parents' => [
                                          {
                                            'entity_id' => '10',
                                            'name' => 'Elasticloud',
                                            'url' => 'https://elasticloud.com/r-and-e-landing',
                                            'description' => 'It\'s elastic!',
                                            'logo_url' => undef
                                          },
                                          {
                                            'entity_id' => '7',
                                            'name' => 'Big State TeraPOP',
                                            'url' => 'https://terapop.example.net/',
                                            'description' => 'The R&E networking hub for Big State',
                                            'logo_url' => 'https://terapop.example.net/favicon.ico'
                                          }
                                        ]
                         }
                       ]
        } , "The method get_entity children returns expected results.");
cmp_deeply(
{
          'error_text' => 'Unable to find entity: 1231 in the Database',
          'error' => 1,
          'results' => undef
        }, $svc->get_entity_children(entity_id=>1231), "The method get_entity_children retuens expeced results when entity_id is out of range.");

cmp_deeply($svc->get_entity_children(entity_id=>undef),
{
          'error_text' => 'get_entity_children: input parameter entity_id cannot be NULL ',
          'error' => 1,
          'results' => undef
        }, "The method get_entity_children behaves in expected manner when the input in not defined.");

cmp_deeply( $svc->get_entity_interfaces(entity_id=>7),
{
          'results' => [
                         {
                           'cloud_interconnect_id' => 'Test',
                           'name' => 'e15/1',
                           'interface_id' => 391,
                           'description' => 'e15/1',
                           'node' => 'Node 11',
                           'cloud_interconnect_type' => undef,
                           'node_id' => 11,
                           'acls' => {
                                       'acls' => [
                                                   {
                                                     'workgroup_id' => 11,
                                                     'eval_position' => '10',
                                                     'entity_id' => 7,
                                                     'allow_deny' => 'deny',
                                                     'start' => 1,
                                                     'end' => undef
                                                   },
                                                   {
                                                     'workgroup_id' => 11,
                                                     'eval_position' => '20',
                                                     'entity_id' => 7,
                                                     'allow_deny' => 'allow',
                                                     'start' => 1,
                                                     'end' => 4095
                                                   }
                                                 ],
                                       'interface_id' => 391
                                     },
                           'operational_state' => 'up'
                         },
                         {
                           'cloud_interconnect_id' => 'Test',
                           'name' => 'e15/1',
                           'interface_id' => 391,
                           'description' => 'e15/1',
                           'node' => 'Node 11',
                           'cloud_interconnect_type' => undef,
                           'node_id' => 11,
                           'acls' => {
                                       'acls' => [
                                                   {
                                                     'workgroup_id' => 11,
                                                     'eval_position' => '10',
                                                     'entity_id' => 7,
                                                     'allow_deny' => 'deny',
                                                     'start' => 1,
                                                     'end' => undef
                                                   },
                                                   {
                                                     'workgroup_id' => 11,
                                                     'eval_position' => '20',
                                                     'entity_id' => 7,
                                                     'allow_deny' => 'allow',
                                                     'start' => 1,
                                                     'end' => 4095
                                                   }
                                                 ],
                                       'interface_id' => 391
                                     },
                           'operational_state' => 'up'
                         },
                         {
                           'cloud_interconnect_id' => undef,
                           'name' => 'fe-4/0/2',
                           'interface_id' => 14081,
                           'description' => 'fe-4/0/2',
                           'node' => undef,
                           'cloud_interconnect_type' => undef,
                           'node_id' => undef,
                           'acls' => {
                                       'acls' => [
                                                   {
                                                     'workgroup_id' => 31,
                                                     'eval_position' => 1,
                                                     'entity_id' => 7,
                                                     'allow_deny' => 'allow',
                                                     'start' => -1,
                                                     'end' => 4095
                                                   }
                                                 ],
                                       'interface_id' => 14081
                                     },
                           'operational_state' => 'unknown'
                         }
                       ]
        }, "The method get_entity_interfaces gives expected results when entity_id is valid.");

cmp_deeply(
{
          'error_text' => undef,
          'error' => 1,
          'results' => undef
        },$svc->get_entity_interfaces(entity_id=>345), "The method get_entity_interfaces gives expected result when entity_id is out of range.");

cmp_deeply($svc->get_entity(entity_id=>7, workgroup_id=>11),
{
          'results' => {
                         'contacts' => [],
                         'name' => 'Big State TeraPOP',
                         'children' => [
                                         {
                                           'entity_id' => '16',
                                           'name' => 'EC Utopia',
                                           'url' => undef,
                                           'description' => 'Guess where this region is?',
                                           'logo_url' => undef
                                         }
                                       ],
                         'logo_url' => 'https://terapop.example.net/favicon.ico',
                         'description' => 'The R&E networking hub for Big State',
                         'interfaces' => [
                                           {
                                             'cloud_interconnect_id' => 'Test',
                                             'available_vlans' => [
                                                                    2,
                                                                    3,
                                                                    4,
                                                                    5,
                                                                    6,
                                                                    7,
                                                                    8,
                                                                    9,
                                                                    10
                                                                  ],
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
                                           }
                                         ],
                         'allowed_vlans' => [
                                              '6',
                                              '3',
                                              '7',
                                              '9',
                                              '2',
                                              '8',
                                              '4',
                                              '10',
                                              '5'
                                            ],
                         'entity_id' => '7',
                         'url' => 'https://terapop.example.net/',
                         'parents' => [
                                        {
                                          'entity_id' => '2',
                                          'name' => 'Connectors',
                                          'url' => undef,
                                          'description' => 'Those that are included in this classification',
                                          'logo_url' => undef
                                        }
                                      ]
                       }
        }, "The method get_entity gives expected output when entity_id is 7 and workgroup is 11.");

cmp_deeply($svc->get_entity(entity_id=>234),
{
          'error_text' => 'Entity was not found in the database',
          'error' => 1,
          'results' => undef
        }, "The method get_entity() returns expected results when entity is out of range.");

cmp_deeply($svc->get_entity(entity_id=>undef),
{
          'error_text' => 'Entity was not found in the database',
          'error' => 1,
          'results' => undef
        }, "The method get_entity() gives expected results when entity is not defined.");

## Not sure about test cases from vrf_id and circuit_id as vrf_table is empty
cmp_deeply($svc->update_entity(entity_id=>123, name=>"Ok", url=>"Ok", logo_url=>"ok", description=>"Ok"),
{
          'results' => [
                         {
                           'success' => 1
                         }
                       ]
        }, "The method update_entity() is successful in updating the entity.");

cmp_deeply($svc->update_entity(entity_id=>234, name=>"Ok", url=>"Ok", logo_url=>"ok", description=>"Ok"),
{
          'error_text' => 'Unable to find entity: 234 in the Database',
          'error' => 1,
          'results' => undef
        }, "The method update_entity() gives expected output in case where entity does not exist.");

# Testing add_interface()

cmp_deeply($svc->add_interface(entity_id=>123, interface_id=>391),
{
          'results' => [
                         {
                           'success' => 1
                         }
                       ]
        }, "The method add_interface gives desired result when entity_id is 123 and interface_id is 391.");

cmp_deeply($svc->add_interface(entity_id=>123, interface_id=>444),
{
          'error_text' => 'Unable to find interface 444 in the db.',
          'error' => 1,
          'results' => undef
        }, "The method add_interface() gives desired result when interface_id is out of range.");

cmp_deeply($svc->add_interface(entity_id=>333, interface_id=>444),
{
          'error_text' => 'Unable to find entity 333 in the db',
          'error' => 1,
          'results' => undef
        }, "The method add_interface() returns desired result when entity is not present in DB.");


cmp_deeply($svc->remove_interface(entity_id=>7, interface_id=>391),
{
          'results' => [
                         {
                           'success' => 1
                         }
                       ]
        }, "The method remove_interface gives desired result when entity_id and interface_id are valid");
cmp_deeply($svc->remove_interface(entity_id=>345, interface_id=>4444),
{
          'error_text' => 'Unable to find entity 345 in the db',
          'error' => 1,
          'results' => undef
        }, "The method remove_interface() gives expected results when the entity_id is not in the DB."
);
cmp_deeply($svc->remove_interface(entity_id=>123, interface_id=>4444),
{
          'error_text' => 'Unable to find interface 4444 in the db',
          'error' => 1,
          'results' => undef
        }, "The method remove_interface() gives expected results when the entity_id is not in the DB."
);
# Not Sure of case when interface has already been removed

cmp_deeply($svc->add_user(entity_id=>123, user_id =>1),
{
          'results' => [
                         {
                           'success' => 1
                         }
                       ]
        }, "The method add_user() gives expected result when entity_id is 123 and user_id is 1.");

cmp_deeply($svc->add_user(entity_id=>456, user_id=>1),
{
          'error_text' => 'Unable to find entity 456 in the db',
          'error' => 1,
          'results' => undef
        },"The method add_user() gives expected result when entity_id is not in the DB.");	

cmp_deeply($svc->add_user(entity_id=>123, user_id=>4444),
{
          'error_text' => 'Unable to find user 4444 in the db.',
          'error' => 1,
          'results' => undef
        }, "The method add_user() gives expeceted result when user is out of range.");

cmp_deeply($svc->remove_user(entity_id=>123, user_id=>1),
{
          'results' => [
                         {
                           'success' => 1
                         }
                       ]
        }                       , "The method remove_user() gives expected reqult for entity_id = 123 and user_id = 1");

cmp_deeply($svc->remove_user(entity_id=>444, user_id=>4567),
{
          'error_text' => 'Unable to find entity 444 in the db',
          'error' => 1,
          'results' => undef
        }, "The method remove_user() returns expected result when entity is not in the DB.");
cmp_deeply($svc->remove_user(entity_id=>123, user_id=>4567),
{
          'error_text' => 'Unable to find user 4567 in the db',
          'error' => 1,
          'results' => undef
        },"The method remove_user() returns expected result when user_id is invalid." );
cmp_deeply($svc->get_entities(workgroup_id=>undef),
{
          'error_text' => 'get_entities: input parameter workgroup_id cannot be NULL ',
          'error' => 1,
          'results' => undef
        }, " The method get_entities() gives expected resut when parameter workgroup_id is null.");

cmp_deeply($svc->get_entities(),
{
          'error_text' => 'get_entities: required input parameter workgroup_id is missing ',
          'error' => 1,
          'results' => undef
        },"The method get_entities() retuens expected results when parameter workgroup_id is missing.");

cmp_deeply($svc->get_entities(workgroup_id=>11, name=>"Big State TeraPOP"),
{
          'results' => [
                         {
                           'contacts' => [],
                           'name' => 'Big State TeraPOP',
                           'children' => [
                                           {
                                             'entity_id' => '16',
                                             'name' => 'EC Utopia',
                                             'url' => undef,
                                             'description' => 'Guess where this region is?',
                                             'logo_url' => undef
                                           }
                                         ],
                           'logo_url' => 'https://terapop.example.net/favicon.ico',
                           'description' => 'The R&E networking hub for Big State',
                           'interfaces' => [
                                             {
                                               'cloud_interconnect_id' => 'Test',
                                               'available_vlans' => [],
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
                                             }
                                           ],
                           'entity_id' => '7',
                           'url' => 'https://terapop.example.net/',
                           'parents' => [
                                          {
                                            'entity_id' => '2',
                                            'name' => 'Connectors',
                                            'url' => undef,
                                            'description' => 'Those that are included in this classification',
                                            'logo_url' => undef
                                          }
                                        ]
                         }
                       ]
        }, "The method get_entities() returns expected result when workgroup_id is 11 for entity name Big State TeraPOP");

$ENV{'REMOTE_USER'} = $temp_user;
