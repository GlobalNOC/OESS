#!/usr/bin/perl -T

# Reset database after changes caused by OESS::Entity tests

use strict;
use FindBin;
my $path;

BEGIN {
    if($FindBin::Bin =~ /(.*)/){
	$path = $1;
    }
}

use Test::More tests => 2;

use lib "$path";
use OESSDatabaseTester;

ok(&OESSDatabaseTester::resetOESSDB(), "Resetting OESS Database");
ok(&OESSDatabaseTester::resetSNAPPDB(), "Resetting SNAPP Database");
