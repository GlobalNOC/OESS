#!/usr/bin/perl -T

use strict;
use warnings;

use Test::More tests => 6;
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

my $config_file  = "$cwd/conf/database.xml";
my $topo = OESS::Topology->new(
    config => $config_file,
);
ok(defined($topo), "Topology object succesfully instantiated");


my $valid_links        = ['Link 181', 'Link 191']; 
my $valid_backup_links = ['Link 81', 'Link 91', 'Link 61', 'Link 151', 'Link 171'];
my $looped_links       = ['Link 81', 'Link 91', 'Link 61', 'Link 151', 'Link 31', 'Link 597', 'Link 596', 'Link 595', 'Link 161'];
my $valid_endpoints = [{
    node      => 'Node 11',
    interface => 'e15/1',
    tag       => 3
},{
    node      => 'Node 51',
    interface => 'e15/1',
    tag       => 3
}];

# verify valid path passes

my ($ok, $error) = $topo->validate_paths(
    links        => $valid_links,
    backup_links => $valid_backup_links,
    endpoints    => $valid_endpoints
);
ok($ok, "valid path succeeds");

#verify primary path loop fails
($ok, $error) = $topo->validate_paths(
    links        => $looped_links,
    backup_links => $valid_backup_links,
    endpoints    => $valid_endpoints
);
ok(!$ok, "links with loop fails");

#verify backup path loop fails
($ok, $error) = $topo->validate_paths(
    links        => $valid_links,
    backup_links => $looped_links,
    endpoints    => $valid_endpoints
);
ok(!$ok, "backup links with loop fails");

#verify failure when endpoints don't connect
my $disconnected_endpoints = [{
    node      => 'Node 11',
    interface => 'e15/1',
    tag       => 3
},{
    node      => 'Node 51',
    interface => 'e15/1',
    tag       => 3
}];
($ok, $error) = $topo->validate_paths(
    links        => $valid_links,
    backup_links => $valid_backup_links,
    endpoints    => $disconnected_endpoints
);
ok($ok, "disconnected endpoints fails");


# verify loopback circuit not stopped
my $loopback_endpoints = [{
    'node' => 'Node 11',
    'interface' => 'e15/1',
    'tag' => '2222'
},{
    'node' => 'Node 11',
    'interface' => 'e15/1',
    'tag' => '2223'
}];
ok($topo->validate_paths(
    links        => $looped_links,
    backup_links => $looped_links,
    endpoints    => $loopback_endpoints
), "doesn't stop loopback circuit");



