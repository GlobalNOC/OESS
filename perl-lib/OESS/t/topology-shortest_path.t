#!/usr/bin/perl -T

use strict;
use warnings;

use Test::More tests => 8;
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
use Log::Log4perl;

Log::Log4perl::init_and_watch('t/conf/logging.conf',10);

#--- instantiate OESS DB and Topo
my $db = OESS::Database->new(config => "$cwd/conf/database.xml");
ok(defined($db));
my $config_file  = "$cwd/conf/database.xml";
my $topo = OESS::Topology->new(
    config => $config_file,
);
ok(defined($topo), "Topology object succesfully instantiated");

sub main {

    # Verify path is determined by shortest hops when metrics are all 0
    my $path = $topo->find_path(
        nodes => ['Node 11','Node 51']
    );
    ok($path, "find_path() ran succesfully");
    is_deeply($path,['Link 181','Link 191']);

    # Change metric of link in middle of previous path and verfiy it takes the longer route now
    my $return = $db->update_link(
        link_id => 191,
        metric  => 10000,
        name => 'Link 191'
    );
    ok($return, "Link 191 sucessfully updated");

    $path = $topo->find_path(
        nodes => ['Node 11','Node 51']
    );
    ok($path, "find_path() ran succesfully");

    is_deeply($path,['Link 171','Link 151','Link 61','Link 91','Link 81']);

    my $return = $db->update_link(
        link_id => 191,
        metric  => 1200,
        name => 'Link 191'
    );

    # Verify backup path does not contain a loop ISSUE=8688
    $path = $topo->find_path(
        nodes      => ['Node 11','Node 31','Node 111','Node 21'],
        used_links => ['Link 171','Link 151','Link 61','Link 101','Link 221','Link 1']
    );

    my $path_details = get_path_details($path);
    ok($topo->path_is_loop_free($path_details), "Backup path does not contain loop");
}


sub get_path_details {
    my $path = shift;

    my $path_details = [];
    my $query = 'SELECT node_a.name AS node_a, '.
                '       node_z.name AS node_z  '.
                'FROM link '.
                'JOIN link_instantiation AS li ON link.link_id = li.link_id '.
                'JOIN interface AS int_a ON li.interface_a_id = int_a.interface_id '.
                'JOIN interface AS int_z ON li.interface_z_id = int_z.interface_id '.
                'JOIN node AS node_a ON int_a.node_id = node_a.node_id '.
                'JOIN node AS node_z ON int_z.node_id = node_z.node_id '.
                'WHERE link.name = ? '.
                'AND li.end_epoch = -1';
    foreach my $link_name (@$path){
        my $result = $db->_execute_query($query, [$link_name]);
        if (!defined($result)){
            warn "Error retrieving path details for link, $link_name: ".$db->get_error();
        }
        $result = $result->[0];
        push(@$path_details, {
            link_name => $link_name,
            node_a    => $result->{'node_a'},
            node_z    => $result->{'node_z'}
        });
    }

    return $path_details;
}


main();
