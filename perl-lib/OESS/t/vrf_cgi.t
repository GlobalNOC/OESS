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

warn Dumper($svc->get_vrf_details(vrf_id => 1));
#warn Dumper($db->execute_query("SELECT * FROM vrf_ep_peer LIMIT 1"));

#get_vrf_details
#get_vrfs
#provision
#remove

