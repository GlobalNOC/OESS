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
use Test::More tests => 1;

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

my $nso = new OESS::NSO::ClientStub();

my ($nso_l3connections, $err) = $nso->get_l3connections();
my $nso_l3connection = $nso_l3connections->[0];

my $expect1 = {
    'Node 31' => '+ e15/4
+   Bandwidth: 100
+   Tag:       2010
+   Peer 2:
+     Local ASN: 7
+     Local IP:  192.168.2.2/31
+     Peer ASN:  64602
+     Peer IP:   192.168.2.3/31
+     BFD:       0
',
    'Node 11' => '  e15/6
-   Bandwidth: 200
+   Bandwidth: 100
-   Tag:       300
+   Tag:       3010
    Peer 1:
-     Local IP:  192.168.3.2/31
+     Local IP:  192.168.1.2/31
-     Peer ASN:  64001
+     Peer ASN:  64601
-     Peer IP:   192.168.3.3/31
+     Peer IP:   192.168.1.3/31
-     BFD:      1
+     BFD:      0
+   Peer 3:
+     Local ASN: 
+     Local IP:  192.168.5.2/31
+     Peer ASN:  64605
+     Peer IP:   192.168.5.3/31
+     BFD:       0
',
    'xr1' => '- GigabitEthernet0/1
-   Bandwidth: 100
-   Tag:       300
-   Peer 2:
-     Local ASN: 64600
-     Local IP:  192.168.2.2/31
-     Peer ASN:  64602
-     Peer IP:   192.168.2.3/31
-     BFD:       0
'
};
push @$nso_l3connection_tests, { vrf_id => 1, result => $expect1 };


foreach my $test (@$nso_l3connection_tests) {
    my $conn = new OESS::VRF(
        db     => $db,
        vrf_id => $test->{vrf_id},
        model  => $test->{model}
    );
    $conn->load_endpoints;
    foreach my $ep (@{$conn->endpoints}) {
        $ep->load_peers;
    }

    my $result = $conn->nso_diff($nso_l3connection);
    my $ok = cmp_deeply($result, $test->{result}, 'Human readable diff generated');
    warn Dumper($result) if !$ok;
}
