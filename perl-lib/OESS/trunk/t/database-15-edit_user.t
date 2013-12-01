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

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $user = $db->edit_user();
ok(!defined($user), "No value returned when no parameter is specified");
my $error = $db->get_error();
ok(defined($error),"No params were passed and we got an error back");


$user = $db->edit_user( given_name => 'Aj');
ok(!defined($user), "No value returned when only given name specified");

$user = $db->edit_user( family_name => 'User 11');
ok(!defined($user), "No value returned when only family name specified");

$user = $db->edit_user( email_address => 'user_11');
ok(!defined($user), "No value returned when only email address specified");

$user = $db->edit_user( user_id => '11', given_name => 'Hari', family_name => 'User 11', email_address => 'user_11', auth_names => ['aragusa@grnoc.iu.edu'] );
                        
ok(defined($user), "User updated");
