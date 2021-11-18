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
use Test::Deep;
use Test::More tests => 3;

use OESSDatabaseTester;

use OESS::DB;
use OESS::L2Circuit;


OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);


my $db = new OESS::DB(
    config  => "$path/../conf/database.xml"
);


my $nso_l2connection_tests = [];


my $nso_l2connection = {
    'connection_id' => 3000,
    'endpoint' => [
        {
            'bandwidth' => 0,
            'endpoint_id' => 1,
            'interface' => 'GigabitEthernet0/0',
            'tag' => 10,
            'unit' => 10,
            'device' => 'xr0'
        },
        {
            'bandwidth' => 0,
            'endpoint_id' => 2,
            'interface' => 'GigabitEthernet0/0',
            'tag' => 11,
            'unit' => 11,
            'device' => 'xr0'
        }
    ]
};


my $expect1 = {
    'xr0' => '-  GigabitEthernet0/0.10
-    Bandwidth: 0
-    Tag:       10
-  GigabitEthernet0/0.11
-    Bandwidth: 0
-    Tag:       11
'
};
push @$nso_l2connection_tests, { model => {}, nso_state => $nso_l2connection, result => $expect1 };


my $expect2 = {
    'xr0' => '+  GigabitEthernet0/0.10
+    Bandwidth: 0
+    Tag:       10
+  GigabitEthernet0/0.11
+    Bandwidth: 0
+    Tag:       11
'
};
push @$nso_l2connection_tests, {
    model => {
        endpoints => [
            { circuit_ep_id => 1, interface => 'GigabitEthernet0/0', short_node_name => 'xr0', tag => 10, unit => 10, bandwidth => 0 },
            { circuit_ep_id => 2, interface => 'GigabitEthernet0/0', short_node_name => 'xr0', tag => 11, unit => 11, bandwidth => 0 }
        ]
    },
    nso_state => {},
    result => $expect2
};


my $expect3 = {};
push @$nso_l2connection_tests, {
    model => {
        endpoints => [
            { circuit_ep_id => 1, interface => 'GigabitEthernet0/0', short_node_name => 'xr0', tag => 10, unit => 10, bandwidth => 0 },
            { circuit_ep_id => 2, interface => 'GigabitEthernet0/0', short_node_name => 'xr0', tag => 11, unit => 11, bandwidth => 0 }
        ]
    },
    nso_state => $nso_l2connection,
    result => $expect3
};

foreach my $test (@$nso_l2connection_tests) {
    my $conn = new OESS::L2Circuit(
        db         => $db,
        circuit_id => $test->{circuit_id},
        model      => $test->{model}
    );
    $conn->load_endpoints;

    my $result = $conn->nso_diff($test->{nso_state});
    my $ok = cmp_deeply($result, $test->{result}, 'Human readable diff generated');
    warn Dumper($result) if !$ok;
}
