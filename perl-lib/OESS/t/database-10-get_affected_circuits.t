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

ok($#{$circuits} == 9, "Total number of results match");
warn Dumper($circuits);
cmp_deeply($circuits,[
	    {
            'name' => 'Circuit 61',
            'id' => '61',
            'state' => 'active'
	    },
	    {
            'name' => 'Circuit 311',
            'id' => '311',
            'state' => 'active'
	    },
	    {
            'name' => 'Circuit 3851',
            'id' => '3851',
            'state' => 'active'
	    },
	    {
            'name' => 'Circuit 3911',
            'id' => '3911',
            'state' => 'active'
	    },
	    {
            'name' => 'Circuit 3961',
            'id' => '3961',
            'state' => 'active'
	    },
	    {
            'name' => 'Circuit 4041',
            'id' => '4041',
            'state' => 'active'
	    },
	    {
            'name' => 'Circuit 4101',
            'id' => '4101',
            'state' => 'active'
	    },
	    {
            'name' => 'Circuit 4111',
            'id' => '4111',
            'state' => 'active'
	    },
	    {
            'name' => 'Circuit 4121',
            'id' => '4121',
            'state' => 'active'
	    },
	    {
            'name' => 'Circuit 4131',
            'id' => '4131',
            'state' => 'active'
	    }
	   ]);

