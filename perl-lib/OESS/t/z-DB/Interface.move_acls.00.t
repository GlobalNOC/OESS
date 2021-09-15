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
use Test::More tests => 5;

use OESSDatabaseTester;

use OESS::DB;
use OESS::DB::Interface;

# Purpose:
#
# Verify ACLs are correctly moved between interfaces.


OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

my $db = new OESS::DB(
   config => "$path/../conf/database.xml"
);

my $err;

$err = OESS::DB::Interface::move_acls(
    db => $db,
    src_interface_id => 21,
    dst_interface_id => 22
);
ok(defined $err, "ACLs not moved to non-existing interface.");

my $pre_src_acls = OESS::DB::Interface::get_acls(
    db => $db,
    interface_id => 21
);

my $pre_dst_acls = OESS::DB::Interface::get_acls(
    db => $db,
    interface_id => 31
);
ok(@$pre_dst_acls == 0, "No ACLs on destination interface.");

$err = OESS::DB::Interface::move_acls(
    db => $db,
    src_interface_id => 21,
    dst_interface_id => 31
);
ok(!defined $err, "ACLs moved.");

my $post_src_acls = OESS::DB::Interface::get_acls(
    db => $db,
    interface_id => 21
);
ok(@$post_src_acls == 0, "No ACLs on source interface.");

my $post_dst_acls = OESS::DB::Interface::get_acls(
    db => $db,
    interface_id => 31
);

ok(@$pre_src_acls == @$post_dst_acls, "Expected number of ACLs on destination interface.");
