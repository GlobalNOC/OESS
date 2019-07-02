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
use OESS::Path;


OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);


my $db = new OESS::DB(
    config  => "$path/../conf/database.xml"
);

my $pa = new OESS::Path(db => $db, path_id => 71);
$pa->load_links;
ok(@{$pa->links} == 2, 'found expected number of path links');
ok($pa->state eq 'active', 'found expected path state');

my $l = $pa->links->[1];

$pa->remove_link($l->{link_id});
my $update_err = $pa->update;
warn $update_err if defined $update_err;

my $pa2 = new OESS::Path(db => $db, path_id => 71);
$pa2->load_links;
ok(@{$pa2->links} == 1, 'found expected number of path links');
ok($pa2->state eq 'active', 'found expected path state');

$pa2->add_link($l);
$pa2->state('decom');
$update_err = $pa2->update;
warn $update_err if defined $update_err;

my $pa3 = new OESS::Path(db => $db, path_id => 71);
$pa3->load_links;
ok(@{$pa3->links} == 2, 'found expected number of path links');
ok($pa3->state eq 'decom', 'found expected path state');
