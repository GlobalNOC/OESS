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
use OESS::DB::Link;


OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);


my $db = new OESS::DB(
    config  => "$path/../conf/database.xml"
);


my ($history, $history_err) = OESS::DB::Link::fetch_history(
    db => $db,
    link_id => 1
);
warn $history_err if (defined $history_err);

my $history_count = scalar @$history;

my ($ok, $update_err) = OESS::DB::Link::update(
    db => $db,
    link => {
        link_id => 1,
        link_state => 'active',
        name => 'Link lolz',
        ip_z => undef,
        metric => 666,
        ip_a => undef,
        interface_z_id => 21,
        interface_a_id => 31
    }
);
warn $update_err if (defined $update_err);

my ($data, $err) = OESS::DB::Link::fetch(
    db => $db,
    link_id => 1
);
warn $err if (defined $err);

ok($data->{link_id} == 1, 'link_id as expected after update');
ok($data->{metric} == 666, 'metric as expected after update');
ok($data->{interface_a_id} == 31, 'interface_a_id as expected after update');
ok($data->{interface_z_id} == 21, 'interface_z_id as expected after update');
ok($data->{name} eq 'Link lolz', 'name as expected after update');

($history, $history_err) = OESS::DB::Link::fetch_history(
    db => $db,
    link_id => 1
);
warn $history_err if (defined $history_err);
ok(@$history = $history_count + 1, "Link instantiation created on edit.");
