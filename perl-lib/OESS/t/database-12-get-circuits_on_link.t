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

use Test::More tests => 5;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $circuits = $db->get_circuits_on_link( link_id => 1);

ok($#{$circuits} == 29, "Total number of circuits match " . $#{$circuits});

warn Data::Dumper::Dumper($circuits->[0]);

cmp_deeply($circuits->[0],{
          'path_id' => '81',
          'circuit_state' => 'active',
          'static_mac' => '0',
          'circuit_id' => '61',
          'workgroup_id' => '11',
          'ci_end' => '-1',
          'start_epoch' => '1348964242',
          'external_identifier' => undef,
          'remote_requester' => undef,
          'remote_url' => undef,
          'name' => 'Circuit 61',
          'reserved_bandwidth_mbps' => '0',
          'loop_node' => undef,
          'description' => 'Circuit 61',
          'path_type' => 'primary',
          'end_epoch' => '-1',
          'lpm_end' => '-1',
          'path_state' => 'active',
          'modified_by_user_id' => '1',
          'restore_to_primary' => '0' }, "values for first circuit match");

my $is_ok=1;
my %circuit_id_seen;
foreach my $ckt (@$circuits){
    if(defined($circuit_id_seen{$ckt->{'circuit_id'}})){
	$is_ok = 0;
	print STDERR "At least 1 circuit was seen multiple times on the same link\n";
    }
}

ok($is_ok, "All circuits seen only once");

$is_ok = 1;
foreach my $ckt (@$circuits){
    if($ckt->{'end_epoch'} != -1){
	$is_ok = 0;
	print STDERR "Found something that is not currently active on this circuit\n";
    }
}

ok($is_ok, "All circuits are currently active on this link");

$circuits = $db->get_circuits_on_link( );

ok(!defined($circuits), "No params returns undef");

