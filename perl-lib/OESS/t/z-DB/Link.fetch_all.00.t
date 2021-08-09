#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
my $path;

BEGIN {
    if ($FindBin::Bin =~ /(.*)/) {
        $path = $1;
    }
}
use lib "$path/..";


use Data::Dumper;
use Test::More tests => 14;

use OESSDatabaseTester;

use OESS::DB;
use OESS::DB::Link;


OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);


my $db = new OESS::DB(
    config  => "$path/../conf/database.xml"
);


# All links regardless of type
my ($links, $links_err) = OESS::DB::Link::fetch_all(
    db => $db
);
warn $links_err if (defined $links_err);

my $links_count = scalar @$links;
ok($links_count == 25, 'Got expected number of links.');
ok($links->[0]->{node_a_controller} eq 'netconf', 'Got expected node_a controller type.');
ok($links->[0]->{node_z_controller} eq 'netconf', 'Got expected node_z controller type.');


($links, $links_err) = OESS::DB::Link::fetch_all(
    db => $db,
    controller => 'netconf'
);
warn $links_err if (defined $links_err);

$links_count = scalar @$links;
ok($links_count == 25, 'Got expected number of links.');
ok($links->[0]->{node_a_controller} eq 'netconf', 'Got expected node_a controller type.');
ok($links->[0]->{node_z_controller} eq 'netconf', 'Got expected node_z controller type.');


($links, $links_err) = OESS::DB::Link::fetch_all(
    db => $db,
    controller => 'nso'
);
warn $links_err if (defined $links_err);

$links_count = scalar @$links;
ok($links_count == 0, 'Got expected number of links.');




# Update all nodes to nso controller. no netconf links shall be detected
$db->execute_query('update node_instantiation set controller="nso"', []);



($links, $links_err) = OESS::DB::Link::fetch_all(
    db => $db
);
warn $links_err if (defined $links_err);

$links_count = scalar @$links;
ok($links_count == 25, 'Got expected number of links.');
ok($links->[0]->{node_a_controller} eq 'nso', 'Got expected node_a controller type.');
ok($links->[0]->{node_z_controller} eq 'nso', 'Got expected node_z controller type.');


# all links shall be of type nso
($links, $links_err) = OESS::DB::Link::fetch_all(
    db => $db,
    controller => 'nso'
);
warn $links_err if (defined $links_err);

$links_count = scalar @$links;
ok($links_count == 25, 'Got expected number of links.');
ok($links->[0]->{node_a_controller} eq 'nso', 'Got expected node_a controller type.');
ok($links->[0]->{node_z_controller} eq 'nso', 'Got expected node_z controller type.');


($links, $links_err) = OESS::DB::Link::fetch_all(
    db => $db,
    controller => 'netconf'
);
warn $links_err if (defined $links_err);

$links_count = scalar @$links;
ok($links_count == 0, 'Got expected number of links.');
