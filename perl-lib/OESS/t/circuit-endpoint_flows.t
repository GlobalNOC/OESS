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

use Test::More tests => 15;
use Test::Deep;
use Data::Dumper;

use Log::Log4perl;

Log::Log4perl::init_and_watch('t/conf/logging.conf',10);

my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );

my $ckt = OESS::Circuit->new( circuit_id => 4111, db => $db);

my $primary_flows = $ckt->get_endpoint_flows( path => 'primary');

my $backup_flows = $ckt->get_endpoint_flows( path => 'backup');

ok(defined($primary_flows), "Primary flows were defined");
ok(defined($backup_flows), "Backup flows were defined");

is(scalar(@$primary_flows), 2, "Primary flow count matches");
is(scalar(@$backup_flows), 2, "Backup flow count matches");

my $p_flow_1 = OESS::FlowRule->new( 'priority' => 32768,
				    'actions' => [
					{
					    'set_vlan_vid' => '150'
					},
					{
					    'output' => '2'
					}
				    ],
				    'idle_timeout' => 0,
				    'dpid' => '155569080320',
				    'match' => {
					'dl_vlan' => 4090,
					'in_port' => '677'
				    });
ok($p_flow_1->compare_flow( flow_rule => $primary_flows->[0]),"Primary Flow 1 Matches");


my $p_flow_2 = OESS::FlowRule->new( 'priority' => 32768,
				    'actions' => [
					{
					    'set_vlan_vid' => '134'
					},
					{
					    'output' => '2'
					}
				    ],
				    'idle_timeout' => 0,
				    'dpid' => '155568668928',
				    'match' => {
					'dl_vlan' => 2055,
					'in_port' => '676'
				    });
ok($p_flow_2->compare_flow(flow_rule => $primary_flows->[1]),"Primary Flow 2 Matches");

my $b_flow_1 = OESS::FlowRule->new('priority' => 32768,
				   'actions' => [
				       {
					   'set_vlan_vid' => '151'
				       },
				       {
					   'output' => '97'
				       }
				   ],
				   'idle_timeout' => 0,
				   'dpid' => '155569080320',
				   'match' => {
				       'dl_vlan' => 4090,
				       'in_port' => '677'
				   });
ok($b_flow_1->compare_flow( flow_rule => $backup_flows->[0]), "Backup Flow 1 matches");

my $b_flow_2= OESS::FlowRule->new('priority' => 32768,
                   'actions' => [
		       {
                                    'set_vlan_vid' => '134'
		       },
		       {
                                    'output' => '1'
		       }
                                ],
                   'idle_timeout' => 0,
                   'dpid' => '155568668928',
				  'match' => {
                                'dl_vlan' => 2055,
                                'in_port' => '676'
				  });

ok($b_flow_2->compare_flow( flow_rule => $backup_flows->[1]), "Backup Flow 2 matches");


$ckt = OESS::Circuit->new( circuit_id => 101, db => $db);

ok(defined($ckt),"Circuit was defined");
ok(!$ckt->has_backup_path(), "Circuit does not have backup path");

$primary_flows = $ckt->get_endpoint_flows( path => 'primary');

ok(defined($primary_flows), "Primary flows were defined");

$backup_flows = $ckt->get_endpoint_flows( path => 'backup');

ok(defined($backup_flows), "Backup flows were not defined (circuit has no backup path)");
ok(scalar(@$backup_flows) == 0, "No actual backup path flows were specified");

ok(!defined($ckt->get_endpoint_flows( path => 'foo')), "Doesn't support paths that aren't 'primary' or 'backup'");
ok(!defined($ckt->get_endpoint_flows()), "Doesn't support not specifying a path");
