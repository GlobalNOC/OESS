#!/usr/bin/perl -T
#
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

use Test::More tests => 13;
use Test::Deep;
use OESS::Database;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $workgroup = $db->add_workgroup();
ok(!defined($workgroup), "no value returned when no workgroup id specified");
my $error = $db->get_error();

$workgroup = $db->add_workgroup( name => 'foo');
ok(defined($workgroup), "workgroup with only a name defaults to normal type");
my $workgroup_details = $db->get_workgroup_by_id( workgroup_id => $workgroup);
ok(defined($workgroup_details), "workgroup exists in db");
cmp_deeply($workgroup_details, { workgroup_id => '262',
				 name => 'foo',
				 type => 'normal',
				 external_id => undef,
				 description => ''
           },"Workgroup details match");

$workgroup = $db->add_workgroup( name => 'bar', type => 'admin' );
ok(defined($workgroup), "workgroup with a name and type is valid");
$workgroup_details = $db->get_workgroup_by_id( workgroup_id => $workgroup);
ok(defined($workgroup_details), "workgroup exists in db");
cmp_deeply($workgroup_details,{ workgroup_id => '263',
				name => 'bar',
				type => 'admin',
				external_id=> undef,
				description => ''
           },"Workgroup details match");

$workgroup = $db->add_workgroup( name => 'foobar' , type => 'something crazy');
ok($workgroup, "workgroup with an invalid name gets set to normal");
$workgroup_details = $db->get_workgroup_by_id( workgroup_id => $workgroup);
ok(defined($workgroup_details),"workgroup exists in db");
cmp_deeply($workgroup_details,{ workgroup_id => '264',
				name => 'foobar',
				type => 'normal',
				external_id => undef,
				description => ''
	   },"Workgroup details match");

$workgroup = $db->add_workgroup( name => 'barfoo' , type => 'admin', external_id => 'asdfsdfs');
ok($workgroup, "workgroup with an invalid name gets set to normal");
$workgroup_details = $db->get_workgroup_by_id( workgroup_id => $workgroup);
ok(defined($workgroup_details),"workgroup exists in db");
cmp_deeply($workgroup_details,{ workgroup_id => '265',
				name => 'barfoo',
				type => 'admin',
				external_id => 'asdfsdfs',
				description => ''
           },"Workgroup details match");
