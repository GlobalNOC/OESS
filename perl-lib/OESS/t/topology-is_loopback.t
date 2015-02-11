#!/usr/bin/perl -T

use strict;
use warnings;

use Test::More tests => 3;
use Data::Dumper;
use FindBin;

my $cwd;

BEGIN {
    if($FindBin::Bin =~ /(.*)/){
    $cwd = $1;
    }
}

use lib "$cwd/../lib";
use OESS::Topology;

my $config_file  = "$cwd/conf/database.xml";
my $topo = OESS::Topology->new(
    config => $config_file,
);
ok(defined($topo), "Topology object succesfully instantiated");

my $endpoints = [{
    'local' => 1,
    'node' => 'Node 11',
    'mac_addrs' => [],
    'interface_description' => 'e15/1',
    'port_no' => '673',
    'node_id' => '11',
    'urn' => undef,
    'interface' => 'e15/1',
    'tag' => '2222',
    'role' => 'unknown'
},{
    'local' => 1,
    'node' => 'Node 11',
    'mac_addrs' => [],
    'interface_description' => 'e15/1',
    'port_no' => '673',
    'node_id' => '11',
    'urn' => undef,
    'interface' => 'e15/1',
    'tag' => '2223',
    'role' => 'unknown'
}];



# make sure is_loopback returns 
ok($topo->is_loopback($endpoints), "is loopback returns true!");

#-- ISSUE=10077 make sure a circuit whose endpoints share the same name but are on 
#-- different nodes are not treated as a loopback circuit
# make the first endpoints' node different from the seconds'
$endpoints->[0]{'node'}    = 'Node 10';
$endpoints->[0]{'node_id'} = 10;
ok(!$topo->is_loopback($endpoints), "is loopback returns false when nodes are different");

