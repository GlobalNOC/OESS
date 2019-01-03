#!/usr/bin/perl -T 

use strict;
use warnings;
use Data::Dumper;
use GRNOC::Config;
use GRNOC::WebService::Client;
use Test::More tests=>8;
use Test::Deep;
use OESS::DB;
use Log::Log4perl;
use OESS::Interface;

# Initialize logging
Log::Log4perl->init("/etc/oess/logging.conf");
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
			url	=> $url."services/interface.cgi",
			uid 	=> $username,
			passwd 	=> $password,
			realm 	=> 'OESS',
			debug	=> 0 
);

my $methods = [
          'get_available_vlans',
          'get_workgroup_interfaces',
          'help',
          'is_vlan_available'
        ];
cmp_deeply($svc->help(), $methods, "The methods have been defined correctly");
cmp_deeply($svc->get_available_vlans(interface_id=>undef),
        {
          'error_text' => 'get_available_vlans: input parameter interface_id cannot be NULL ',
          'error' => 1,
          'results' => undef
        }, "get_available_vlans() give throw an error when passed no object to it");

ok((defined($db) and defined($interface) and defined($svc)),"Sanity Check, can instantiate OESS::DB,OESS::Interface, GRNOC::WebService::Client");
cmp_deeply($svc->get_available_vlans(interface_id=>$interface_id, workgroup_id=>$workgroup_id),
	{
          'results' => {
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
                                              ]
                       }
        }, "The method get_available_vlans() returns right information.");

cmp_deeply($svc->is_vlan_available( interface_id=>$interface_id, workgroup_id=>$workgroup_id, vlan=>3120),
	{
          'results' => {
                         'allowed' => 0
                       }
        },
	, "Vlan is not available for interface $interface_id, workgroup #workgroup_id and Vlan_id =  3120");
cmp_deeply($svc->is_vlan_available( interface_id=>$interface_id, workgroup_id=>$workgroup_id, vlan=>5),
        {
          'results' => {
                         'allowed' => 1
                       }
        },
        , "Vlan is not available fpr interface $interface_id, workgroup $workgroup_id and Vlan_id =  5");
cmp_deeply($svc->get_workgroup_interfaces(workgroup_id=>$workgroup_id),
{
          'results' => [
                         {
                           'cloud_interconnect_id' => undef,
                           'name' => 'e15/2',
                           'interface_id' => '501',
                           'description' => 'e15/2',
                           'node' => 'Node 131',
                           'cloud_interconnect_type' => undef,
                           'node_id' => '131',
                           'acls' => {
                                       'acls' => [],
                                       'interface_id' => '501'
                                     },
                           'operational_state' => 'up'
                         },
                         {
                           'cloud_interconnect_id' => undef,
                           'name' => 'e15/6',
                           'interface_id' => '45841',
                           'description' => 'e15/6',
                           'node' => 'Node 11',
                           'cloud_interconnect_type' => undef,
                           'node_id' => '11',
                           'acls' => {
                                       'acls' => [],
                                       'interface_id' => '45841'
                                     },
                           'operational_state' => 'up'
                         },
                         {
                           'cloud_interconnect_id' => undef,
                           'name' => 'e1/2',
                           'interface_id' => '45851',
                           'description' => 'e1/2',
                           'node' => 'Node 31',
                           'cloud_interconnect_type' => undef,
                           'node_id' => '31',
                           'acls' => {
                                       'acls' => [],
                                       'interface_id' => '45851'
                                     },
                           'operational_state' => 'up'
                         }
                       ]
        },
"The method workgroup_interfaces() returns valid information for workgroup $workgroup_id"
);
cmp_deeply($svc->get_workgroup_interfaces(workgroup_id=> undef),
        {
          'error_text' => 'get_workgroup_interfaces: input parameter workgroup_id cannot be NULL ',
          'error' => 1,
          'results' => undef
        }, "The method get_workgroup_interfaces returns correct output when NULL is passed as parameter.");

