#!/usr/bin/perl -T

use strict;

use FindBin;
my $path;

BEGIN {
    if($FindBin::Bin =~ /(.*)/){
        $path = $1;
    }
}

use lib "$path";
use OESSDatabaseTester;

use Test::More tests => 4;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $count = $db->remove_acl(
    user_id => 301,
    interface_acl_id => 3
);
ok(!$count, 'no result when not authorized');
is($db->get_error(), 'Access Denied', 'correct error');

$count = $db->remove_acl(
    user_id => 11,
    interface_acl_id => 7
);
is($count, 1,'1 acl deleted');

$count = $db->remove_acl(
    user_id => 11,
    interface_acl_id => 12
);
is($count, 1,'1 acl deleted');
