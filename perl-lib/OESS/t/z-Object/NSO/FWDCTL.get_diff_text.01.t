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

my $fwdctl = new OESS::NSO::FWDCTL(
    config_filename => "$path/../../conf/database.xml",
    connection_cache => $cache,
    db => $db,
    nso => $nso
);

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

my $err = $fwdctl->addVrf(vrf_id => 1);
ok(!defined $err, 'Vrf created');

my ($text1, $err1) = $fwdctl->get_diff_text(node_id => 11);
ok($text1 eq $expect1->{'Node 11'}, 'Got expected diff');

my ($text2, $err2) = $fwdctl->get_diff_text(node_id => 31);
ok($text2 eq $expect1->{'Node 31'}, 'Got expected diff');

my ($text3, $err3) = $fwdctl->get_diff_text(node_name => 'xr1');
ok($text3 eq $expect1->{'xr1'}, 'Got expected diff');
