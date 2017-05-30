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
    config => $config_file,
);

ok(defined($topo), "Topology object succesfully instantiated");

#returns empty if no path is provided
ok(!$topo->is_path_up(), "empty path returns undefined");

#path should be up at firs
$db->update_link_state(link_id=>41, state=>'up');
ok($topo->is_path_up(path_id => 121 ), "Path 121 begins as up" );
#set link in path to down

ok($db->update_link_state( link_id=>41, state=>'down' ), "set link 41 to down");

my $path_state = $topo->is_path_up( path_id => 121);

ok( $topo->is_path_up(path_id => 121 )==0, "Path 4841 is now down ");

$db->update_link_state(link_id=>41, state=>'up');

ok($topo->is_path_up(path_id =>121 ) == 1, "Path Returned to up" );
