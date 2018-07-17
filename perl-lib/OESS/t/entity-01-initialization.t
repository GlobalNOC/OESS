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
use OESSDatabaseTester;

use Test::More tests => 9;
use Test::Deep;
use Data::Dumper;

my $db = OESS::DB->new( config => OESSDatabaseTester::getConfigFilePath() );
ok(defined($db), 'Can instantiate OESS::DB object');

my $ent = OESS::Entity->new( entity_id => 1, db => $db );
ok(defined($ent), 'Can instantiate OESS::Entity object (id=1)');

$ent = OESS::Entity->new( name => 'Blue Cloud', db => $db );
ok(defined($ent), 'Can instantiate OESS::Entity object (name=Blue Cloud)');

$ent = OESS::Entity->new( entity_id => 2, name => 'Elasticcloud', db => $db );
ok(defined($ent), 'Can instantiate OESS::Entity object (id=2, name=Elasticcloud)');

$ent = OESS::Entity->new( entity_id => 2 );
ok(!defined($ent), 'No OESS::Entity created when no db provided (1)');

$ent = OESS::Entity->new( name => 'Blue Cloud' );
ok(!defined($ent), 'No OESS::Entity created when no db provided (2)');

$ent = OESS::Entity->new( entity_id => 4_999_9999, db => $db );
ok(!defined($ent), 'No OESS::Entity created when invalid entity_id provided');

$ent = OESS::Entity->new( name => 'xyzzy', db => $db );
ok(!defined($ent), 'No OESS::Entity created when invalid name provided');

$ent = OESS::Entity->new( db => $db );
ok(!defined($ent), 'No OESS::Entity created when no entity_id or name provided');
