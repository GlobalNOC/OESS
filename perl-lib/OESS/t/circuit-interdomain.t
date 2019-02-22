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

use Test::More tests => 6;
use Test::Deep;
use Data::Dumper;
use Log::Log4perl;

Log::Log4perl::init_and_watch('t/conf/logging.conf',10);

my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );

my $ckt = OESS::Circuit->new( circuit_id => 1601, db => $db);

ok(!$ckt->has_backup_path(), "Circuit has no backup path");
ok($ckt->is_interdomain(), "Circuit is interdomain");

my $endpoints = $ckt->get_endpoints();

warn Data::Dumper::Dumper($endpoints);

ok(scalar(@$endpoints) == 3, "Has correct number of endpoints");

cmp_deeply($endpoints->[0], {
            'local' => '1',
	    'interface_id' => 741,
            'node' => 'Node 91',
            'mac_addrs' => [],
            'interface_description' => 'e15/1',
            'port_no' => '673',
            'node_id' => '91',
            'urn' => undef,
            'interface' => 'e15/1',
            'unit' => '3005',
            'inner_tag' => undef,
            'tag' => '3005',
            'role' => 'unknown'
           }, "Endpoint 1 matches");

cmp_deeply($endpoints->[1], {
            'local' => '1',
            'node' => 'Node 91',
	    'interface_id' => 761,
            'mac_addrs' => [],
            'interface_description' => 'e15/3',
            'port_no' => '675',
            'node_id' => '91',
            'urn' => undef,
            'interface' => 'e15/3',
            'unit' => '3005',
            'inner_tag' => undef,
            'tag' => '3005',
            'role' => 'unknown'
           }, "Endpoint 2 matches");

cmp_deeply($endpoints->[2], {
                'local' => '0',
		'interface_id' => 29961,
            'node' => 'ion.internet2.edu-rtr.newy',
            'mac_addrs' => [],
            'interface_description' => 'xe-1/1/0',
            'port_no' => undef,
            'node_id' => '4161',
                'unit' => '3005',
                'inner_tag' => undef,
            'urn' => 'urn:ogf:network:domain=ion.internet2.edu:node=rtr.newy:port=xe-1/1/0:link=*',
            'interface' => 'xe-1/1/0',
            'tag' => '3005',
            'role' => 'unknown'
           }, "Endpoint 3 matches");
