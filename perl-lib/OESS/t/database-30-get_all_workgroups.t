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

use Test::More tests => 5;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $workgroups = $db->get_all_workgroups();
is(@$workgroups, 29, '29 Workgroups Retrieved');

my $workgroup = $workgroups->[0];

is($workgroup->{'workgroup_id'},263,'workgroup_id ok');
is($workgroup->{'external_id'},undef,'external_id ok');
is($workgroup->{'name'}, 'bar','name ok');
is($workgroup->{'type'},'admin','type ok');

