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
use OESS::Circuit;
use OESSDatabaseTester;

use Test::More tests => 2;
use Test::Deep;
use Data::Dumper;

my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );

my $ckt = OESS::Circuit->new( circuit_id => 101, db => $db);

my $clr = $ckt->generate_clr();

ok(defined($clr), "CLR was defined");
warn "CLR: \n" . $clr;
ok($clr eq 'Circuit: Circuit 101
Created by: User 201 User 201 at 09/30/2012 00:41:54 for workgroup
Lasted Modified By: User 1 User 1 at 09/30/2012 00:41:54

Endpoints:
  Node 21 - e15/2 VLAN 105
  Node 81 - e15/2 VLAN 105

Primary Path:
  Link 41

Backup Path:
  Link 41', "CLR Matches");
