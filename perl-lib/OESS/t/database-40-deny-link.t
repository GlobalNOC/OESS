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

use Test::More tests => 2;
use Test::Deep;
use OESS::Database;
use OESS::Circuit;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $result = $db->decom_link_instantiation( link_id => 1 );
ok(defined($result));

$result = $db->create_link_instantiation( link_id => 1, interface_a_id => 41, interface_z_id => 21, state => "decom" );
ok(defined($result));
