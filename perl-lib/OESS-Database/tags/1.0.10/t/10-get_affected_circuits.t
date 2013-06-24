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

ok(defined($db));

my $circuits = $db->get_affected_circuits_by_link_id( link_id => 1);

ok(defined($circuits), "result was defined");

ok($#{$circuits} == 7, "Total number of results match");

cmp_deeply($circuits,[
	       {
            'name' => 'Circuit 61',
            'id' => '61'
	       },
	       {
            'name' => 'Circuit 3851',
            'id' => '3851'
	       },
	       {
            'name' => 'Circuit 3911',
            'id' => '3911'
	       },
	       {
            'name' => 'Circuit 3961',
            'id' => '3961'
	       },
	       {
            'name' => 'Circuit 4041',
            'id' => '4041'
	       },
	       {
            'name' => 'Circuit 4101',
            'id' => '4101'
	       },
	       {
            'name' => 'Circuit 4111',
            'id' => '4111'
	       },
	       {
            'name' => 'Circuit 4131',
            'id' => '4131'
	       }
	   ], "Output matches what we expect");


