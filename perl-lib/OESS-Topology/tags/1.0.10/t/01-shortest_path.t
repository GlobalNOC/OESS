#!/usr/bin/perl -T

use strict;
use warnings;

use Test::More tests => 7;
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
use OESS::Database;

#--- instantiate OESS DB to alter paths for testing
my $db = OESS::Database->new(config => "$cwd/conf/database.xml");
ok(defined($db));

my $config_file  = "$cwd/conf/database.xml";

my $topo = OESS::Topology->new( 
    config_file => $config_file,
);

ok(defined($topo), "Topology object succesfully instantiated");

# Verify path is determined by shortest hops when metrics are all 0
my $path = $topo->find_path(
                    nodes => ['Node 11','Node 51']
                  );
ok($path, "find_path() ran succesfully");
is_deeply($path,['Link 181', 'Link 191']);

# Change metric of link in middle of previous path and verfiy it takes the longer route now
my $return = $db->update_link( 
    link_id => 191,
    metric  => 10,
    name => 'Link 191' 
);

ok($return, "Link 191 sucessfully updated");

$path = $topo->find_path(
                nodes => ['Node 11','Node 51']
               );
ok($path, "find_path() ran succesfully");
is_deeply($path,['Link 171','Link 151','Link 61','Link 91','Link 81']);
