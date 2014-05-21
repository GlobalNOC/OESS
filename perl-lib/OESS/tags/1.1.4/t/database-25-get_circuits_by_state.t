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
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $active_circuits = $db->get_circuits_by_state( state => 'active' );


is(@$active_circuits, 100, "Total number of circuits match");

cmp_deeply($active_circuits->[0],{
    'circuit_state' => 'active',
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
          'workgroup_id' => '11',
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

