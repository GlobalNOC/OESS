#!/usr/bin/perl -T

# tests of OESS::Entity's to_hash and save-to-DB functionality

use strict;
use warnings;

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
use OESS::Interface;
use OESS::User;
use OESSDatabaseTester;

use Test::More tests => 11;
use Test::Deep;
use Data::Dumper;

my $db;

sub _interface {
    my $id = shift;
    return all(
        OESS::Interface->new(interface_id => $id, db => $db)->to_hash,
        # second half of the test is a sanity-check that the method calls in the first half didn't fail
        superhashof({interface_id => $id, node_id => ignore(), name => ignore()}),
    );
}


$db = OESS::DB->new( config => OESSDatabaseTester::getConfigFilePath() );



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



my $ent2 = OESS::Entity->new( entity_id => 14, db => $db );

cmp_deeply(
    $ent2->to_hash(),
    {
        entity_id   => 14,

        name        => 'B University-Metropolis',
        description => 'Metropolis regional campus',
        url         => 'https://b-metro.example.edu/',
        logo_url    => undef,

        interfaces  => bag( _interface(35961) ),
        contacts    => bag( 
                            {
                             'email' => 'user_121@foo.net',
                             'is_admin' => '0',
                             'user_id' => '121',
                             'last_name' => 'User 121',
                             'first_name' => 'User 121',
                             'status' => 'active',
                             'usernames' => ['user_121@foo.net']
                            },
                            {
                             'email' => 'user_881@foo.net',
                             'is_admin' => '0',
                             'user_id' => '881',
                             'last_name' => 'User 881',
                             'first_name' => 'User 881',
                             'status' => 'active',
                             'usernames' => ['user_881@foo.net']
                            }
                          ),
        parents     => bag(
            {
                entity_id   => 6,
                name        => 'B University',
                description => 'mascot: Wally B. from the 1980s short',
                logo_url    => undef,
                url         => 'gopher://b.example.edu/',
            },
            {
                entity_id   => 8,
                name        => 'Small State MilliPOP',
                description => undef,
                logo_url    => undef,
                url         => 'https://smst.millipop.net/',
            },
        ),
        children    => [],
    },
    'Entity 2: to_hash returns expected results'
);

# Try changing multiple things, update the DB, and see if we get the expected results after:
$ent2->name('xyzzy');
$ent2->logo_url('https://example.edu/icon');
$ent2->remove_user(OESS::User->new(user_id => 121, db => $db));
$ent2->add_child({ entity_id => 15 });
$ent2->add_child({ entity_id => 15 }); # Try adding it twice!

ok(!defined($ent2->update_db()), 'Entity 2: no DB errors when running update_db()');

my $ent2a = OESS::Entity->new( entity_id => 14, db => $db );

cmp_deeply(
    $ent2a->to_hash(),
    {
        entity_id   => 14,

        name        => 'xyzzy',
        description => 'Metropolis regional campus',
        url         => 'https://b-metro.example.edu/',
        logo_url    => 'https://example.edu/icon',

        interfaces  => bag( _interface(35961) ),
        contacts    => bag(  {
                              'email' => 'user_881@foo.net',
                              'is_admin' => '0',
                              'user_id' => '881',
                              'last_name' => 'User 881',
                              'first_name' => 'User 881',
                              'status' => 'active',
                              'usernames' => ['user_881@foo.net']
                             }
                            ),
        parents     => bag(                                                                                                                     
            {
                entity_id   => 6,
                name        => 'B University',
                description => 'mascot: Wally B. from the 1980s short',
                logo_url    => undef,
                url         => 'gopher://b.example.edu/',
            },
            {
                entity_id   => 8,
                name        => 'Small State MilliPOP',
                description => undef,
                logo_url    => undef,
                url         => 'https://smst.millipop.net/',
            },
        ),
        children    => bag(
            {
                entity_id   => 15,
                name        => 'EC Ellettsville',
                description => 'Ellettsville region',
                logo_url    => undef,
                url         => undef,
            },
        ),
    },
    'Entity 2: after update_db(), stuff in DB has been updated appropriately'
);



ok(&OESSDatabaseTester::resetOESSDB(), "Resetting OESS Database");
