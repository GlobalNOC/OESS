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
    'directly-modified' => {
        'services' => [
            '/i2-common:internal-services/sdp:sdp-attach[sdp:sdp=\'0\'][sdp:name=\'3000\']',
            '/i2-common:internal-services/sdp:sdp-attach[sdp:sdp=\'1\'][sdp:name=\'3000\']'
        ],
        'devices' => [
            'xr0'
        ]
    },
    'endpoint' => [
        {
            'bandwidth' => 0,
            'endpoint_id' => 1,
            'interface' => 'GigabitEthernet0/0',
            'tag' => 1,
            'unit' => 1,
            'device' => 'xr0'
        },
        {
            'bandwidth' => 0,
            'endpoint_id' => 2,
            'interface' => 'GigabitEthernet0/1',
            'tag' => 1,
            'unit' => 1,
            'device' => 'xr0'
        }
    ],
    'device-list' => [
        'xr0'
    ],
    'modified' => {
        'services' => [
            '/i2-common:internal-services/sdp:sdp-attach[sdp:sdp=\'1\'][sdp:name=\'3000\']',
            '/i2-common:internal-services/sdp:sdp-attach[sdp:sdp=\'0\'][sdp:name=\'3000\']'
        ],
        'devices' => [
            'xr0'
        ]
    }
};


my $expect1 = {
    'N11' => '+  e15/6.3126
+    Bandwidth: 0
+    Tag:       3126
',
    'N31' => '+  e15/4.2005
+    Bandwidth: 0
+    Tag:       2005
',
    'xr0' => '-  GigabitEthernet0/0.1
-    Bandwidth: 0
-    Tag:       1
-  GigabitEthernet0/1.1
-    Bandwidth: 0
-    Tag:       1
'
};
push @$nso_l2connection_tests, { circuit_id => 4081, result => $expect1 };


my $expect2 = {
    'xr0' => '-  GigabitEthernet0/0.1
-    Bandwidth: 0
-    Tag:       1
-  GigabitEthernet0/1.1
-    Bandwidth: 0
-    Tag:       1
'
};
push @$nso_l2connection_tests, { model => {}, result => $expect2 };


my $expect3 = {};
push @$nso_l2connection_tests, {
    model => {
        endpoints => [
            { circuit_ep_id => 1, interface => 'GigabitEthernet0/0', short_node_name => 'xr0', tag => 1, unit => 1, bandwidth => 0 },
            { circuit_ep_id => 2, interface => 'GigabitEthernet0/1', short_node_name => 'xr0', tag => 1, unit => 1, bandwidth => 0 }
        ]
    },
    result => $expect3
};

foreach my $test (@$nso_l2connection_tests) {
    my $conn = new OESS::L2Circuit(
        db         => $db,
        circuit_id => $test->{circuit_id},
        model      => $test->{model}
    );
    $conn->load_endpoints;

    my $result = $conn->nso_diff($nso_l2connection);
    my $ok = cmp_deeply($result, $test->{result}, 'Human readable diff generated');
    warn Dumper($result) if !$ok;
}
