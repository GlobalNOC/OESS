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
use Test::More tests => 2;

use OESSDatabaseTester;

use OESS::DB;
use OESS::VRF;
use OESS::NSO::ClientStub;

OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);


my $db = new OESS::DB(
    config  => "$path/../conf/database.xml"
);


my $nso_l3connection_tests = [];

my $nso_conn1 = {
    "connection_id" => 456,
    "endpoint" => [
        {
            "endpoint_id" => 8,
            "vars" => {
                "pdp" => "CHIC-JJJ-0",
            },
            "device" => "Node 11",
            "interface" => "e15/6",
            "tag" => 300,
            "unit" => 300,
            "bandwidth" => 200,
            "peer" => [
                {
                    "peer_id" => 1,
                    "local_asn" => 64600,
                    "local_ip" => "192.168.3.2/31",
                    "peer_asn" => 64001,
                    "peer_ip" => "192.168.3.3",
                    "bfd" => 1,
                    "ip_version" => "ipv4"
                }
            ]
        },
        {
            "endpoint_id" => 9,
            "vars" => {
                "pdp" => "CHIC-JJJ-0",
            },
            "device" => "Node 11",
            "interface" => "e15/6",
            "tag" => 301,
            "unit" => 301,
            "bandwidth" => 100,
            "peer" => [
                {
                    "peer_id" => 2,
                    "local_asn" => 64600,
                    "local_ip" => "192.168.2.2/31",
                    "peer_asn" => 64602,
                    "peer_ip" => "192.168.2.3",
                    "bfd" => 0,
                    "ip_version" => "ipv4"
                }
            ]
        }
    ]
};
my $diff1 = {
    'Node 11' => '-  e15/6.300
-    Bandwidth: 200
-    Tag:       300
-    Peer: 1
-      Local ASN: 64600
-      Local IP:  192.168.3.2/31
-      Peer ASN:  64001
-      Peer IP:   192.168.3.3
-      BFD:       1
-  e15/6.301
-    Bandwidth: 100
-    Tag:       301
-    Peer: 2
-      Local ASN: 64600
-      Local IP:  192.168.2.2/31
-      Peer ASN:  64602
-      Peer IP:   192.168.2.3
-      BFD:       0
'
};
my $oess_conn1 = new OESS::VRF(
    db     => $db,
    model  => {
        local_asn => 64600,
        vrf_id => 456
    }
);


my $nso_conn2 = {
    "connection_id" => 456,
    "endpoint" => [
        {
            "endpoint_id" => 8,
            "vars" => {
                "pdp" => "CHIC-JJJ-0",
            },
            "device" => "Node 11",
            "interface" => "e15/6",
            "tag" => 300,
            "unit" => 300,
            "bandwidth" => 200,
            "peer" => [
                {
                    "peer_id" => 1,
                    "local_asn" => 64600,
                    "local_ip" => "192.168.3.2/31",
                    "peer_asn" => 64001,
                    "peer_ip" => "192.168.3.3",
                    "bfd" => 1,
                    "ip_version" => "ipv4"
                }
            ]
        },
        {
            "endpoint_id" => 9,
            "vars" => {
                "pdp" => "CHIC-JJJ-0",
            },
            "device" => "Node 11",
            "interface" => "e15/6",
            "tag" => 301,
            "unit" => 301,
            "bandwidth" => 100,
            "peer" => [
                {
                    "peer_id" => 2,
                    "local_asn" => 64600,
                    "local_ip" => "192.168.2.2/31",
                    "peer_asn" => 64602,
                    "peer_ip" => "192.168.2.3",
                    "bfd" => 0,
                    "ip_version" => "ipv4"
                }
            ]
        }
    ]
};
my $diff2 = {
    'Node 11' => '   e15/6.300
-    Peer: 1
-      Local ASN: 64600
-      Local IP:  192.168.3.2/31
-      Peer ASN:  64001
-      Peer IP:   192.168.3.3
-      BFD:       1
   e15/6.301
-    Peer: 2
-      Local ASN: 64600
-      Local IP:  192.168.2.2/31
-      Peer ASN:  64602
-      Peer IP:   192.168.2.3
-      BFD:       0
'
};
my $oess_conn2 = new OESS::VRF(
    db     => $db,
    model  => {
        local_asn => 64600,
        vrf_id => 456
    }
);
$oess_conn2->add_endpoint(new OESS::Endpoint(
    db    => $db,
    model => {
        vrf_endpoint_id   => 8,
        node              => 'Node 11',
        interface         => 'e15/6',
        unit              => 300,
        tag               => 300,
        inner_tag         => undef,
        bandwidth         => 200,
        mtu               => 9000,
        operational_state => 'up'
    }
));
$oess_conn2->add_endpoint(new OESS::Endpoint(
    db    => $db,
    model => {
        vrf_endpoint_id   => 9,
        node              => 'Node 11',
        interface         => 'e15/6',
        unit              => 301,
        tag               => 301,
        inner_tag         => undef,
        bandwidth         => 100,
        mtu               => 9000,
        operational_state => 'up'
    }
));

my $tests = [
    { nso_conn => $nso_conn1, oess_conn => $oess_conn1, diff => $diff1 },
    { nso_conn => $nso_conn2, oess_conn => $oess_conn2, diff => $diff2 },
];

foreach my $test (@$tests) {
    my $result_diff = $test->{oess_conn}->nso_diff($test->{nso_conn});
    my $ok = cmp_deeply($result_diff, $test->{diff}, 'Human readable diff generated');
    warn Dumper($result_diff) if !$ok;
}
