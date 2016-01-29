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

use Test::More tests => 8;
use Test::Deep;
use OESS::Database;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $active_circuits = $db->get_circuits_by_state( state => 'active' );


is(@$active_circuits, 98, "Total number of circuits match");

cmp_deeply($active_circuits->[0],{
    'circuit_state' => 'active',
    'loop_node' => undef,
    'remote_requester' => undef,
    'remote_url' => undef,
    'circuit_id' => '11',
    'workgroup_id' => '11',
    'start_epoch' => '1348855218',
    'external_identifier' => undef,
    'name' => 'Circuit 11',
    'reserved_bandwidth_mbps' => '0',
    'description' => 'Circuit 11',
    'end_epoch' => '-1',
    'modified_by_user_id' => '1',
    'restore_to_primary' => '0',
    'static_mac' => 0
}, "values for first circuit matches");


cmp_deeply($active_circuits->[1],{
          'circuit_state' => 'active',
          'circuit_id' => '51',
          'loop_node' => undef,
          'workgroup_id' => '11',
          'remote_requester' => undef,
          'remote_url' => undef,
          'start_epoch' => '1348963870',
          'external_identifier' => undef,
          'name' => 'Circuit 51',
          'reserved_bandwidth_mbps' => '0',
          'description' => 'Circuit 51',
          'end_epoch' => '-1',
          'modified_by_user_id' => '1',
	  'restore_to_primary' => '0',
          'static_mac' => 0
}, "values for second circuit matches");

my $scheduled_circuits = $db->get_circuits_by_state( state => 'scheduled' );
my $ref = ref $scheduled_circuits;
is($ref, 'ARRAY', "No results returns empty array ref");

my $reserved_circuits = $db->get_circuits_by_state( state => 'reserved' );
is(@$reserved_circuits, 1, "Total number of circuits match");

cmp_deeply($reserved_circuits->[0],{
          'circuit_state' => 'reserved',
          'circuit_id' => '4091',
          'loop_node' => undef,
          'workgroup_id' => '241',
          'remote_requester' => "urn:uuid:aragusa",
          'remote_url' => "http://some/remotehost",
          'start_epoch' => '1361994404',
          'external_identifier' => undef,
          'name' => 'Circuit 4091',
          'reserved_bandwidth_mbps' => '0',
          'description' => 'Circuit 4091',
          'end_epoch' => '-1',
          'modified_by_user_id' => '1',
          'restore_to_primary' => '0',
          'static_mac' => 0
           }, "values for reserved circuit matches");

my $provisioned_circuits = $db->get_circuits_by_state( state => 'provisioned' );
is(@$provisioned_circuits, 1, "Total number of circuits match");

cmp_deeply($provisioned_circuits->[0],{
          'circuit_state' => 'provisioned',
          'circuit_id' => '4081',
          'loop_node' => undef,
          'workgroup_id' => '241',
          'remote_requester' => "urn:uuid:aragusa",
          'remote_url' => "http://some/remotehost",
          'start_epoch' => '1361994356',
          'external_identifier' => undef,
          'name' => 'Circuit 4081',
          'reserved_bandwidth_mbps' => '0',
          'description' => 'Circuit 4081',
          'end_epoch' => '-1',
          'modified_by_user_id' => '1',
          'restore_to_primary' => '0',
          'static_mac' => 0
           }, "values for provisioned circuit matches");
