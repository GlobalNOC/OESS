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
use Test::More tests => 6;

use OESSDatabaseTester;

use OESS::DB;
use OESS::Interface;


OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);


my $db = new OESS::DB(
    config  => "$path/../conf/database.xml"
);

my $intf = new OESS::Interface(db => $db, interface_id => 511);
ok($intf->interface_id eq '511', 'Correct interface_id');
ok($intf->name eq 'e15/1', 'Correct interface name');
ok($intf->description eq 'e15/1', 'Correct interface description');

$intf->{description} = 'e15/1 modified';
$intf->update_db;

my $intf2 = new OESS::Interface(db => $db, interface_id => 511);
ok($intf2->interface_id eq '511', 'Correct interface_id');
ok($intf2->name eq 'e15/1', 'Correct interface name');
ok($intf2->description eq 'e15/1 modified', 'Correct interface with modified description');
