#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use FindBin;

use OESS::MPLS::Discovery;

use Test::More tests => 8;


my $path;

BEGIN {
    if ($FindBin::Bin =~ /(.*)/) { $path = $1; }
}

use lib "$path/../..";

use OESSDatabaseTester;


my $cwd = $FindBin::Bin;
$cwd =~ /(.*)/;
$cwd = $1;

my $conf = "$cwd/../../conf/mpls/discovery.xml";
my $dump = "$cwd/../../conf/mpls/discovery.sql";

OESSDatabaseTester::load_database($conf, $dump);

# Initial adjacencies shown here for reference.
my $adjs = {
    'node2' => {
        'xe-7/0/3' => {
            'remote_node' => 'node3',
            'local_node' => 'node2',
            'remote_ip' => '198.169.70.3',
            'remote_ipv6' => 'fe80::4e96:1400:b77:238b',
            'local_intf' => 'xe-7/0/3',
            'operational_state' => 'Up'
        }
    },
    'node3' => {
        'xe-7/0/3' => {
            'remote_node' => 'node2',
            'local_node' => 'node3',
            'remote_ip' => '198.169.70.2',
            'remote_ipv6' => 'fe80::ae4b:c800:b41:ec83',
            'local_intf' => 'xe-7/0/3',
            'operational_state' => 'Up'
        }
    }
};
my $discovery = OESS::MPLS::Discovery->new(
    config => $conf,
    test   => 1
);
# Move endpoint on node3 from xe-7/0/3 to xe-7/0/2
$discovery->{ipv4_intf} = {
    '198.169.70.2' => 'xe-7/0/3',
    '198.169.70.3' => 'xe-7/0/3'
};

$adjs = {
    'node2' => {
        'xe-7/0/3' => {
            'remote_node' => 'node3',
            'local_node' => 'node2',
            'remote_ip' => '198.169.70.3',
            'remote_ipv6' => 'fe80::4e96:1400:b77:238b',
            'local_intf' => 'xe-7/0/3',
            'operational_state' => 'Up'
        }
    },
    'node3' => {
        'xe-7/0/2' => {
            'remote_node' => 'node2',
            'local_node' => 'node3',
            'remote_ip' => '198.169.70.2',
            'remote_ipv6' => 'fe80::ae4b:c800:b41:ec83',
            'local_intf' => 'xe-7/0/2',
            'operational_state' => 'Up'
        }
    }
};
$discovery->handle_links($adjs);

my $link_insts = $discovery->{db}->_execute_query("select * from link_instantiation where end_epoch=-1",[]);
ok(@$link_insts == 1, "Link instantiation exists.");

my $expected_adj = ($link_insts->[0]->{interface_a_id} == 5 && $link_insts->[0]->{interface_z_id} == 3) ||
    ($link_insts->[0]->{interface_a_id} == 3 && $link_insts->[0]->{interface_z_id} == 5);
ok($expected_adj, "Link instantiation ports updated on adjacency change.");

my $old_port = $discovery->{db}->_execute_query("select * from interface where interface_id=6",[]);
ok($old_port->[0]->{role} eq 'unknown', "Old link port's role updated to unknown.");

my $new_port = $discovery->{db}->_execute_query("select * from interface where interface_id=5",[]);
ok($new_port->[0]->{role} eq 'trunk', "New link port's role updated to trunk.");


sleep 1;


# Move endpoint on node2 from xe-7/0/3 to xe-7/0/2
$discovery->{ipv4_intf} = {
    '198.169.70.2' => 'xe-7/0/3',
    '198.169.70.3' => 'xe-7/0/2'
};

$adjs = {
    'node2' => {
        'xe-7/0/2' => {
            'remote_node' => 'node3',
            'local_node' => 'node2',
            'remote_ip' => '198.169.70.3',
            'remote_ipv6' => 'fe80::4e96:1400:b77:238b',
            'local_intf' => 'xe-7/0/2',
            'operational_state' => 'Up'
        }
    },
    'node3' => {
        'xe-7/0/2' => {
            'remote_node' => 'node2',
            'local_node' => 'node3',
            'remote_ip' => '198.169.70.2',
            'remote_ipv6' => 'fe80::ae4b:c800:b41:ec83',
            'local_intf' => 'xe-7/0/2',
            'operational_state' => 'Up'
        }
    }
};
$discovery->handle_links($adjs);

$link_insts = $discovery->{db}->_execute_query("select * from link_instantiation where end_epoch=-1",[]);
ok(@$link_insts == 1, "Link instantiation exists.");

$expected_adj = ($link_insts->[0]->{interface_a_id} == 5 && $link_insts->[0]->{interface_z_id} == 2) ||
    ($link_insts->[0]->{interface_a_id} == 2 && $link_insts->[0]->{interface_z_id} == 5);
ok($expected_adj, "Link instantiation ports updated on adjacency change.");

$old_port = $discovery->{db}->_execute_query("select * from interface where interface_id=3",[]);
ok($old_port->[0]->{role} eq 'unknown', "Old link port's role updated to unknown.");

$new_port = $discovery->{db}->_execute_query("select * from interface where interface_id=2",[]);
ok($new_port->[0]->{role} eq 'trunk', "New link port's role updated to trunk.");
