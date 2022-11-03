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
use lib "$path/../..";


use Data::Dumper;
use Test::More tests => 4;

use OESSDatabaseTester;

use OESS::DB;
use OESS::L2Circuit;
use OESS::NSO::ClientStub;
use OESS::NSO::ConnectionCache;
use OESS::NSO::FWDCTL;

OESSDatabaseTester::resetOESSDB(
    config => "$path/../../conf/database.xml",
    dbdump => "$path/../../conf/oess_known_state.sql"
);


my $cache = new OESS::NSO::ConnectionCache();
my $db = new OESS::DB(config  => "$path/../../conf/database.xml");
my $nso = new OESS::NSO::ClientStub();


# OESS::NSO::FWDCTL::get_diff_text works by fetching nodes with
# controller of 'nso'.
$db->execute_query("update node_instantiation set controller='nso'", []);


my $fwdctl = new OESS::NSO::FWDCTL(
    config_filename => "$path/../../conf/database.xml",
    connection_cache => $cache,
    db => $db,
    nso => $nso
);

my $expect1 = {
    'N31' => 'OESS-VRF-1:
+  e15/4.200
+    Bandwidth: 100
+    MTU:       9000
+    Tag:       2010
+    Peer: 2
+      Local ASN: 7
+      Local IP:  192.168.2.2/31
+      Peer ASN:  64602
+      Peer IP:   192.168.2.3
+      BFD:       0
',
    'N11' => 'OESS-VRF-1:
   e15/6.300
-    Bandwidth: 200
+    Bandwidth: 100
-    Tag:       300
+    Tag:       3010
     Peer: 1
-      Local IP:  192.168.3.2/31
+      Local IP:  192.168.1.2/31
-      Peer ASN:  64001
+      Peer ASN:  64601
-      Peer IP:   192.168.3.3
+      Peer IP:   192.168.1.3
-      BFD:       1
+      BFD:       0
+    Peer: 3
+      Local ASN: 7
+      Local IP:  192.168.5.2/31
+      Peer ASN:  64605
+      Peer IP:   192.168.5.3
+      BFD:       0
',
    'xr1' => 'OESS-VRF-1:
-  GigabitEthernet0/1.300
-    Bandwidth: 100
-    MTU:       1500
-    Tag:       300
-    Peer: 2
-      Local ASN: 64600
-      Local IP:  192.168.2.2/31
-      Peer ASN:  64602
-      Peer IP:   192.168.2.3
-      BFD:       0
'
};

my $err = $fwdctl->addVrf(vrf_id => 1);
ok(!defined $err, 'Vrf created');

my ($text1, $err1) = $fwdctl->get_diff_text(node_id => 11);
ok($text1 eq $expect1->{'N11'}, 'Got expected diff');
if ($text1 ne $expect1->{'N11'}) {
    print "Expected:\n$expect1->{'N11'}\nGot:\n$text1";
}

my ($text2, $err2) = $fwdctl->get_diff_text(node_id => 31);
ok($text2 eq $expect1->{'N31'}, 'Got expected diff');
if ($text2 ne $expect1->{'N31'}) {
    print "Expected:\n$expect1->{'N31'}\nGot:\n$text2";
}

my ($text3, $err3) = $fwdctl->get_diff_text(node_name => 'xr1');
ok($text3 eq $expect1->{'xr1'}, 'Got expected diff');
if ($text3 ne $expect1->{'xr1'}) {
    print "Expected:\n$expect1->{'xr1'}\nGot:\n$text3";
}
