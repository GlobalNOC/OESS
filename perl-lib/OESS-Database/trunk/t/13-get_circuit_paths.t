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

my $paths = $db->get_circuit_paths( circuit_id => 4011);

ok($#{$paths} == 1, "Total number of paths match");

cmp_deeply($paths->[0],{
            'circuit_id' => '4011',
            'path_id' => '5191',
            'path_instantiation_id' => '9761',
            'status' => 1,
            'start_epoch' => '1362144043',
            'path_type' => 'primary',
            'end_epoch' => '-1',
            'path_state' => 'deploying',
            'links' => [
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
                       ]
          }, "values for first path matches");


cmp_deeply($paths->[1],{
            'circuit_id' => '4011',
            'path_id' => '5201',
            'path_instantiation_id' => '9771',
            'status' => 1,
            'start_epoch' => '1362144043',
            'path_type' => 'backup',
            'end_epoch' => '-1',
            'path_state' => 'available',
            'links' => [
                         {
                           'link_id' => '1',
                           'name' => 'Link 1'
                         },
                         {
                           'link_id' => '21',
                           'name' => 'Link 21'
                         },
                         {
                           'link_id' => '181',
                           'name' => 'Link 181'
                         },
                         {
                           'link_id' => '191',
                           'name' => 'Link 191'
                         },
                         {
                           'link_id' => '231',
                           'name' => 'Link 231'
                         },
                         {
                           'link_id' => '521',
                           'name' => 'Link 521'
                         },
                         {
                           'link_id' => '531',
                           'name' => 'Link 531'
                         }
                       ]
          }, "values for second path matches");

$paths = $db->get_circuit_paths( );

ok(!defined($paths), "No params returns undef");
print STDERR Dumper($paths);
