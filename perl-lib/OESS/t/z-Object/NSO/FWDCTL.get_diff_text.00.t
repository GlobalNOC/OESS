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
use Test::More tests => 5;

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
    'Node 11' => '+ e15/6
+   Bandwidth: 0
+   Tag:       3126
- e15/6
-   Bandwidth: 200
-   Tag:       300
-   Peer 1:
-     Local ASN: 64600
-     Local IP:  192.168.3.2/31
-     Peer ASN:  64001
-     Peer IP:   192.168.3.3/31
-     BFD:       1
',
    'Node 31' => '+ e15/4
+   Bandwidth: 0
+   Tag:       2005
',
    'xr0' => '- GigabitEthernet0/0
-   Bandwidth: 0
-   Tag:       1
- GigabitEthernet0/1
-   Bandwidth: 0
-   Tag:       1
'
};

my $err = $fwdctl->addVlan(circuit_id => 4081);
ok(!defined $err, 'Vlan created');

my ($text1, $err1) = $fwdctl->get_diff_text(node_id => 11);
ok($text1 eq $expect1->{'Node 11'}, 'Got expected diff');
if ($text1 ne $expect1->{'Node 11'}) {
    print "Expected:\n$expect1->{'Node 11'}\nGot:\n$text1";
}

my ($text2, $err2) = $fwdctl->get_diff_text(node_id => 31);
ok($text2 eq $expect1->{'Node 31'}, 'Got expected diff');

my ($text3, $err3) = $fwdctl->get_diff_text(node_name => 'xr0');
ok($text3 eq $expect1->{'xr0'}, 'Got expected diff');


my $cache2 = new OESS::NSO::ConnectionCache();

my $fwdctl2 = new OESS::NSO::FWDCTL(
    config_filename => "$path/../../conf/database.xml",
    connection_cache => $cache2,
    db => $db,
    nso => $nso
);

my $expect2 = {
    'xr0' => '- GigabitEthernet0/0
-   Bandwidth: 0
-   Tag:       1
- GigabitEthernet0/1
-   Bandwidth: 0
-   Tag:       1
'
};

my ($text4, $err4) = $fwdctl2->get_diff_text(node_name => 'xr0');
ok($text4 eq $expect2->{'xr0'}, 'Got expected diff');
