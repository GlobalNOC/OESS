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

use Test::More tests => 6;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;


my $cmp_example = {
    'primary' => {
                         'Node 71' => '142',
                         'Node 11' => '145',
                         'Node 31' => '151',
                         'Node 141' => '135',
                         'Node 41' => '135',
                         'Node 111' => '158',
                         'Node 21' => '153'
    },
			     'backup' => {
                        'Node 91' => '146',
                        'Node 11' => '146',
                        'Node 5721' => '25',
                        'Node 61' => '130',
                        'Node 101' => '152',
                        'Node 51' => '134',
                        'Node 21' => '154'
			 }
};

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $res = $db->get_circuit_internal_ids();
ok(!defined($res), "No value returned when no cirucuit id specified");

my $error = $db->get_error();
ok(!defined($error), "No Params were passed and we got an error back");

$res = $db->get_circuit_internal_ids( circuit_id => 101 );
ok(defined($res), "Ciruit found and its internal ids are listed");

$res = $db->get_circuit_internal_ids( circuit_id => 99999999 );
ok(!defined($res), "failed to get internal ids of non-existng circuit");

$res = $db->get_circuit_internal_ids( circuit_id => 4121 );
ok(defined($res), "circuit 4121 has internal ids");

cmp_deeply( $cmp_example, $res, "Output matches what we expect");
