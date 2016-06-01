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
use OESS::MPLS::Discovery::Interface;

use OESSDatabaseTester;

use Test::More tests => 1;
use Test::Deep;
use Data::Dumper;


my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );

ok(defined($db), "OESS Database was created");

sub callback{
    #verify callback is called
}

my $interface_discovery = OESS::MPLS::Discovery::Interface->new( db => $db,
								 
    );

my $example_node = "foo";
my $example_data = [{
            'name' => 'xe-2/2/1',
            'description' => 'xe-2/2/1',
            'admin_state' => 'up',
            'operational_state' => 'down'
          },
          {
            'name' => 'xe-2/2/2',
            'description' => 'xe-2/2/2',
            'admin_state' => 'up',
            'operational_state' => 'down'
          },
          {
            'name' => 'xe-2/2/3',
            'description' => 'xe-2/2/3',
            'admin_state' => 'up',
            'operational_state' => 'down'
          }];

my $res = $interface_discovery->process_results( node => $example_node, interfaces => $example_data );

ok($res == 1, "Interface processing reports success");

#TODO:
#Verify new interfaces are added to the DB
#Verify the interface status are updated
