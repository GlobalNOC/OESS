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
use OESS::DB;
use OESS::Entity;
use OESS::Interface;
use OESS::User;
use OESSDatabaseTester;

use Test::More tests => 60;
use Test::Deep;
use Data::Dumper;

my $db = OESS::DB->new( config => OESSDatabaseTester::getConfigFilePath() );

my $ent1 = OESS::Entity->new( entity_id => 2, db => $db );
ok(defined($db) && defined($ent1), 'Sanity check: can instantiate OESS::DB and OESS::Entity objects');

ok($ent1->entity_id() == 2,       'Entity 1 returns correct entity_id');
ok($ent1->name() eq 'Connectors', 'Entity 1 returns correct name');
ok($ent1->description eq 'Those that are included in this classification', 'Entity 1 returns correct description');
ok(!defined($ent1->url()),        'Entity 1 returns correct (null) URL');
ok(!defined($ent1->logo_url()),   'Entity 1 returns correct (null) logo URL');
cmp_deeply($ent1->users(), [],    'Entity 1 returns correct (empty) users list');
cmp_deeply(
    $ent1->interfaces(),
    [],
    'Entity 1 returns correct (empty) interfaces list'
);
cmp_deeply(
    $ent1->parents(),
    bag(
        {
            entity_id   => 1,
            name        => 'root',
            description => 'The top of the hierarchy blah blah blah',
            logo_url    => undef,
            url         => 'ftp://example.net/pub/',
        },
    ),
    'Entity 1 returns correct list of parents'
);
cmp_deeply(
    $ent1->children(),
    bag(
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
    'Entity 1 returns correct list of children'
);



my $ent2 = OESS::Entity->new( name => 'B University-Metropolis', db => $db );

ok($ent2->entity_id() == 14,                       'Entity 2 returns correct entity_id');
ok($ent2->name() eq 'B University-Metropolis',     'Entity 2 returns correct name');
ok($ent2->url() eq 'https://b-metro.example.edu/', 'Entity 2 returns correct URL');
ok(!defined($ent2->logo_url()),                    'Entity 2 returns correct logo URL');
cmp_deeply(
    [ map {ref $_} @{$ent2->users()} ],
    [ 'OESS::User', 'OESS::User' ],
    'Entity 2: users() returns two User objects'
);
cmp_deeply(
    [ map {$_->user_id()} @{$ent2->users()} ],
    bag( 121, 881 ),
    'Entity 2: users() returns proper users'
);
cmp_deeply(
    [ map {ref $_} @{$ent2->interfaces()} ],
    [ 'OESS::Interface' ],
    'Entity 2: interfaces() returns one Interface object'
);
cmp_deeply(
    [ map {$_->interface_id()} @{$ent2->interfaces()} ],
    bag( 35961 ),
    'Entity 2: interfaces() returns correct interfaces'
);
cmp_deeply($ent2->children(), [], 'Entity 2: children() returns zero children');
cmp_deeply(
    [ map {ref $_} @{$ent2->parents()} ],
    [ 'HASH', 'HASH' ],
    'Entity 2: parents() return two hashes'
);
cmp_deeply(
    [ map {$_->{'entity_id'}} @{$ent2->parents()} ],
    bag( 6, 8 ),
    'Entity 2: parents() returns info on correct parent entities'
);

my $ent3 = OESS::Entity->new( entity_id => 12, db => $db );

ok($ent3->entity_id() == 12,      'Entity 3 returns correct entity_id');
ok($ent3->name() eq 'BC US-West', 'Entity 3 returns correct name');
ok($ent3->description() eq 'Blue Cloud US-West region',
                                  'Entity 3 returns correct description');

ok($ent3->name('West') eq 'West', 'Entity 3: can set name in object');
ok($ent3->description('blah') eq 'blah',
                                  'Entity 3: can set name in object');
ok($ent3->url('ftp://w.bc.net/') eq 'ftp://w.bc.net/',
                                  'Entity 3: can set URL in object');
ok($ent3->logo_url('file:///a.png') eq 'file:///a.png',
                                  'Entity 3: can set logo URL in object');
cmp_deeply(
    {
        name        => $ent3->name(),
        description => $ent3->description(),
        url         => $ent3->url(),
        logo_url    => $ent3->logo_url(),
    },
    {
        name        => 'West',
        description => 'blah',
        url         => 'ftp://w.bc.net/',
        logo_url    => 'file:///a.png',
    },
    'Entity 3: changes to fields in object are (memory-)persistent'
);

cmp_deeply(
    [ map {ref $_} @{$ent3->interfaces()} ],
    [ 'OESS::Interface' ],
    'Entity 3: interfaces() returns one Interface object'
);
cmp_deeply(
    [ map {$_->interface_id()} @{$ent3->interfaces()} ],
    bag( 21 ),
    'Entity 3: interfaces() returns correct interfaces'
);
ok(defined( $ent3->interfaces([ $ent3->interfaces()->[0], $ent2->interfaces()->[0] ]) ), 'Entity 3: set-interfaces sanity check');
cmp_deeply(
    [ map {ref $_} @{$ent3->interfaces()} ],
    [ 'OESS::Interface', 'OESS::Interface' ],
    'Entity 3: post-set interfaces() returns two Interface objects'
);
cmp_deeply(
    [ map {$_->interface_id()} @{$ent3->interfaces()} ],
    bag( 21, 35961 ),
    'Entity 3: post-set interfaces() returns correct interfaces'
);

my $interface_14081 = OESS::Interface->new( interface_id => 14081, db => $db );
ok(defined($interface_14081), 'Sanity check: we can make OESS::Interface for id=14081');
$ent3->add_interface($interface_14081);
cmp_deeply(
    [ map {ref $_} @{$ent3->interfaces()} ],
    [ 'OESS::Interface', 'OESS::Interface', 'OESS::Interface' ],
    'Entity 3: post-add interfaces() returns three Interface objects'
);
cmp_deeply(
    [ map {$_->interface_id()} @{$ent3->interfaces()} ],
    bag( 21, 14081, 35961 ),
    'Entity 3: post-add interfaces() returns correct interfaces'
);

$ent3->remove_interface({ interface_id => 8311 });
cmp_deeply(
    [ map {$_->interface_id()} @{$ent3->interfaces()} ],
    bag( 21, 14081, 35961 ),
    'Entity 3: removing a non-member interface leaves interface list unchanged'
);

$ent3->remove_interface({ interface_id => 21 });
cmp_deeply(
    [ map {$_->interface_id()} @{$ent3->interfaces()} ],
    bag( 14081, 35961 ),
    'Entity 3: removing a member interface removes only that interface'
);

cmp_deeply(
    [ map {$_->{'entity_id'}} @{$ent3->parents()} ],
    bag( 9 ),
    'Entity 3: parents() returns correct set of parents'
);

my $new_parent = {
    entity_id   => 8,
    name        => 'Small State MilliPOP',
    description => undef,
    logo_url    => undef,
    url         => 'https://smst.millipop.net/',
};
$ent3->add_parent($new_parent);
cmp_deeply(
    [ map {$_->{'entity_id'}} @{$ent3->parents()} ],
    bag( 8, 9 ),
    'Entity 3: post-add parents() returns correct set of parents'
);

my $new_parent_list = [
    {
        entity_id   => 7,
        name        => 'Big State TeraPOP',
        description => 'The R&E networking hub for Big State',
        logo_url    => 'https://terapop.example.net/favicon.ico',
        url         => 'https://terapop.example.net/',
    },
];
ok(defined($ent3->parents($new_parent_list)), 'Entity 3: set-parents sanity check');
cmp_deeply(
    [ map {$_->{'entity_id'}} @{$ent3->parents()} ],
    bag( 7 ),
    'Entity 3: post-set parents() returns correct set of parents'
);

cmp_deeply(
    [ map {ref $_} @{$ent3->users()} ],
    [ 'OESS::User' ],
    'Entity 3: users() returns 1 user'
);

cmp_deeply(
    [ map {$_->user_id()} @{$ent3->users()} ],
    [ 121 ],
    'Entity 3: users() returns the correct user'
);

my $new_user = OESS::User->new( user_id => 881, db => $db );
ok(defined($new_user) && (ref($new_user) eq 'OESS::User'), 'Sanity-check: User->new(881) returned a user');

$ent3->add_user($new_user);

cmp_deeply(
    [ map {ref $_} @{$ent3->users()} ],
    [ 'OESS::User', 'OESS::User' ],
    'Entity 3: post-add users() returns 2 uses'
);

cmp_deeply(
    [ map {$_->user_id()} @{$ent3->users()} ],
    bag( 121, 881 ),
    'Entity 3: post-add users() returns the correct users'
);

$ent3->add_user($new_user);
cmp_deeply(
    [ map {$_->user_id()} @{$ent3->users()} ],
    bag( 121, 881 ),
    'Entity 3: adding the same user twice only results in one user returned by users()'
);

my $user_to_delete = OESS::User->new( user_id => 901, db => $db );
ok(defined($user_to_delete) && (ref($user_to_delete) eq 'OESS::User'), 'Sanity-check: User->new(901) returned a user');

$ent3->remove_user($user_to_delete);
cmp_deeply(
    [ map {$_->user_id()} @{$ent3->users()} ],
    bag( 121, 881 ),
    'Entity 3: removing a non-member user does not change the users list'
);

$user_to_delete = OESS::User->new( user_id => 121, db => $db );
ok(defined($user_to_delete) && (ref($user_to_delete) eq 'OESS::User'), 'Sanity-check: User->new(121) returned a user');

$ent3->remove_user($user_to_delete);
cmp_deeply(
    [ map {$_->user_id()} @{$ent3->users()} ],
    [ 881 ],
    'Entity 3: removing a member user removes that user and only that user'
);

my $ent4 = OESS::Entity->new( entity_id => 9, db => $db );

ok($ent4->entity_id() == 9,       'Entity 4 returns correct entity_id');
ok($ent4->name() eq 'Blue Cloud', 'Entity 4 returns correct name');

cmp_deeply(
    [ map {ref $_} @{$ent4->children()} ],
    [ 'HASH', 'HASH', 'HASH' ],
    'Entity 4: children() returns 3 hashes'
);

cmp_deeply(
    [ map {$_->{'entity_id'}} @{$ent4->children()} ],
    bag( 11, 12, 13 ),
    'Entity 4: children() returns info on correct child entities'
);

my $new_child = {
    # corporate acquisition?
    entity_id   => 16,
    name        => 'EC Utopia',
    description => 'Guess where this region is?',
    logo_url    => undef,
    url         => undef,
};

$ent4->add_child($new_child);
cmp_deeply(
    [ map {$_->{'entity_id'}} @{$ent4->children()} ],
    bag( 11, 12, 13, 16 ),
    'Entity 4: post-add children() returns correct set of children'
);

my $new_child_list = [
    # public-private partnership thingy
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
];

$ent4->children($new_child_list);
cmp_deeply(
    [ map {$_->{'entity_id'}} @{$ent4->children()} ],
    bag( 7, 8 ),
    'Entity 4: post-set children() returns correct set of children'
);

cmp_deeply(
    $ent4->users(),
    [],
    'Entity 4 has no member users'
);
