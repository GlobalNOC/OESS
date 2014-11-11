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

my $user = $db->add_user( given_name => 'asdfsdfdsf',
			  family_name => 'baserxdvzxdsfa',
			  email_address => 'doesntexist@foo.net',
			  auth_names => [ 'doesntexist@foo.net', "doesntexist" ]
    );

my $workgroup = $db->add_workgroup( name => 'blah');

my $res = $db->add_user_to_workgroup( user_id => $user);
ok(!defined($res), "fails to add without workgroup specified");

$res = $db->add_user_to_workgroup( workgroup_id => $workgroup);
ok(!defined($res), "fails to add without user specified");

$res = $db->add_user_to_workgroup( user_id => $user, workgroup_id => $workgroup );
ok(defined($res), "successfully added user to workgroup");

$res = $db->add_user_to_workgroup( user_id => 999999, workgroup_id => $workgroup);
ok(!defined($res), "fails to add a non-existent user to a workgroup");

$res = $db->add_user_to_workgroup( user_id => 999999, workgroup_id => $workgroup);
ok(!defined($res), "fails to add a user to a non-existent workgroup");



