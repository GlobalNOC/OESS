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

use Test::More tests => 4;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $res = $db->get_workgroup_interfaces();
ok(!defined($res), "No value returned when no workgroup_id specified");

my $error = $db->get_error();
is($error, 'Must pass in a workgroup_id.', "No Params were passed and we got an error back");

$res = $db->get_workgroup_interfaces( workgroup_id => 1 );
ok(defined($res), "Found workgroup acls");

cmp_deeply($res,[
          {
            'interface_name' => 'e3/2',
            'node_name' => 'Node 1',
            'interface_id' => '45911',
            'description' => 'e3/2',
            'remote_links' => [],
            'vlan_tag_range' => '1-4095',
            'cloud_interconnect_type' => undef,
            'cloud_interconnect_id' => undef,
            'node_id' => '1',
            'operational_state' => 'up'
          },
          {
            'interface_name' => 'e15/1',
            'node_name' => 'Node 21',
            'interface_id' => '45901',
            'description' => 'e15/1',
            'remote_links' => [],
            'vlan_tag_range' => '1-4095',
            'node_id' => '21',
            'cloud_interconnect_type' => undef,
            'cloud_interconnect_id' => undef,
            'operational_state' => 'up'
          }
        ], 'check results');

