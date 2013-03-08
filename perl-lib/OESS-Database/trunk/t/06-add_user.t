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

use Test::More tests => 9;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $user = $db->add_user( );
ok(!defined($user), "no value returned when no workgroup id specified");
my $error = $db->get_error();
print STDERR Dumper($error);
ok(defined($error), "No params were passed and we got an error back");

$user = $db->add_user( given_name => 'foo' );
ok(!defined($user), "no value returned when only given name specified");

$user = $db->add_user( family_name => 'bar');
ok(!defined($user), "no value returned when only family name specified");

$user = $db->add_user( email_address => 'foo@bar.com');
ok(!defined($user), "no value returned when only email address specified");


$user = $db->add_user( family_name => 'bar',
		       given_name => 'foo', 
    );

ok(!defined($user), "no value returned when family name and given name specified");

$user = $db->add_user( family_name => 'bar',
		       given_name => 'foo',
		       email_address => 'foo@bar.com',
		       auth_name => 'foo');

ok(defined($user) && $user->{'user_id'} == 922, "New user created with only 1 auth_name specified");

$user = $db->add_user( family_name => 'bar2',
		       given_name => 'foo2',
		       email_address => 'foo2@bar2.com',
		       auth_name => ['foo2','foo2@bar.com','aasdf3rdf']);

ok(defined($user) && $user->{'user_id'} == 923, "New user created with multiple auth_name specified");

my $user_details = $db->get_user_by_id( user_id => $user->{'user_id'});

ok(defined($user_details), "User existing in the DB");

