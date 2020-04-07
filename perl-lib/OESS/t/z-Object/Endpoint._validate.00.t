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
use Test::More tests => 12;

use OESSDatabaseTester;

use OESS::DB;
use OESS::Endpoint;
use OESS::Peer;

# PURPOSE:
#
# Verify that calling OESS::VRF->create with an entire VRF model will
# all child elements only creates the base record. Child instantiation
# is the responsibility of the child objects.

OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

my $db = new OESS::DB(
    config  => "$path/../conf/database.xml"
);

my $ep = new OESS::Endpoint(db => $db, vrf_endpoint_id => 3);
ok(!defined $ep->_validate, 'Middle tag validated');

$ep->inner_tag(0);
ok(defined $ep->_validate, 'Low inner_tag invalidated');

$ep->inner_tag(1);
ok(!defined $ep->_validate, 'Edge inner_tag validated');

$ep->inner_tag(4095);
ok(defined $ep->_validate, 'High inner_tag invalidated');

$ep->inner_tag(4094);
ok(!defined $ep->_validate, 'Edge inner_tag validated');

$ep->{inner_tag} = undef;
ok(!defined $ep->_validate, 'Undef inner_tag validated');


$ep->{tag} = undef;
ok(defined $ep->_validate, 'Undef tag invalidated');

$ep->tag(1);
ok(!defined $ep->_validate, 'Edge tag validated');

$ep->tag(0);
ok(defined $ep->_validate, 'Low tag invalidated');

$ep->tag(4095);
ok(!defined $ep->_validate, 'Edge tag validated');

$ep->tag(4096);
ok(defined $ep->_validate, 'High tag invalidated');

$ep->tag(3);
ok(!defined $ep->_validate, 'Middle tag validated');
