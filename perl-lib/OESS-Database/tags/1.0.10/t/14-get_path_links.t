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

use Test::More tests => 3;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $links = $db->get_path_links( path_id => 5191);

ok($#{$links} == 4, "Total number of paths match");


cmp_deeply($links,[
	       {
            'link_id' => '61',
            'name' => 'Link 61'
	       },
	       {
            'link_id' => '101',
            'name' => 'Link 101'
	       },
	       {
            'link_id' => '151',
            'name' => 'Link 151'
	       },
	       {
            'link_id' => '171',
            'name' => 'Link 171'
	       },
	       {
            'link_id' => '221',
            'name' => 'Link 221'
	       }
	   ], "Output matches");

$links = $db->get_path_links( );

ok(!defined($links), "No params returns undef");
