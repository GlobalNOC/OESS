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
use OESS::Database;
use OESSDatabaseTester;

use Test::More tests => 1;
use Test::Deep;
use Data::Dumper;

my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );

my ($status,$err) = $db->validate_circuit( nodes => ['Node 11', 'Node 51'],
                                           links => ['Link 181', 'Link 191', 'Link 531'],
                                           backup_links => [],
                                           interfaces => ['e15/1', 'e15/1'],
                                           vlans => [10,10]);

ok($status, "Successfully validated circuit");
