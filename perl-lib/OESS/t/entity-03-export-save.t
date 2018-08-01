#!/usr/bin/perl -T

# tests of OESS::Entity's to_hash and save-to-DB functionality

use strict;

use FindBin;
my $path;

BEGIN {
    if($FindBin::Bin =~ /(.*)/){
        $path = $1;
    }
}

use lib "$path";
use OESS::DB;
use OESS::Entity;
use OESSDatabaseTester;

use Test::More tests => 8;
use Test::Deep;
use Data::Dumper;

my $db = OESS::DB->new( config => OESSDatabaseTester::getConfigFilePath() );

my $ent1 = OESS::Entity->new( entity_id => 2, db => $db );
ok(defined($db) && defined($ent1), 'Sanity check: can instantiate OESS::DB and OESS::Entity objects');

# Take to_hash out for a spin
cmp_deeply(
    $ent1->to_hash(),
    {
        entity_id   => 2,

        name        => 'Connectors',
        description => 'Those that are included in this classification',
        url         => undef,
        logo_url    => undef,

        interfaces  => [],
        contacts    => [],
        parents     => [
            {
                entity_id   => 1,
                name        => 'root',
                description => 'The top of the hierarchy blah blah blah',
                logo_url    => undef,
                url         => 'ftp://example.net/pub/',
            },
        ],
        children    => bag(
            {
                entity_id   => 7,
                name        => 'Big State TeraPOP',
                description => 'The R&E networking hub for Big State',
                logo_url    => 'https://terapop.example.net/favicon.ico',
                url         => 'https://terapop.example.net/',
            },
            {
                entity_id   => 8,
                name        => 'Small State MilliPOP',
                description => undef,
                logo_url    => undef,
                url         => 'https://smst.millipop.net/',
            },
        ),
    },
    'Entity 1: to_hash() returns expected results'
);

# Try changing one field
ok($ent1->name() eq 'Connectors', 'Entity 1: name retrieved from database');

$ent1->name('Not Connectors');
ok($ent1->name() eq 'Not Connectors', 'Entity 1: name changed in in-memory object');

ok(!defined($ent1->update_db()), 'Entity 1: no DB errors when running update_db()');

my $ent1a = OESS::Entity->new( entity_id => 2, db => $db );
ok($ent1a->name() eq 'Not Connectors', 'Entity 1: after update_db(), row in DB has changed name');
ok($ent1a->description() eq 'Those that are included in this classification', 'Entity 1: after update_db(), description still exists in DB');



ok(&OESSDatabaseTester::resetOESSDB(), "Resetting OESS Database");
