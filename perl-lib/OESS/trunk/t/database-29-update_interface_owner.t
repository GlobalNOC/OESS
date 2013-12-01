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

use Test::More tests => 17;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $acl = $db->update_interface_owner( workgroup_id => 11 );
ok(!defined($acl), "no value returned when no interface_id specified");
my $error = $db->get_error();
ok(defined($error), "No params were passed and we got an error back");

$acl = $db->update_interface_owner( interface_id => 11 );
ok(!defined($acl), "no value returned when no workgroup_id specified");
$error = $db->get_error();
ok(defined($error), "No params were passed and we got an error back");

my $success = $db->update_interface_owner( 
    interface_id => 45881,
	workgroup_id => 11,
);

ok($success, "workgroup acl was successfully added");

my $res = $db->get_interface( interface_id => 45881 );
is($res->{'workgroup_id'}, 11, 'interface added to workgroup');

$res = $db->get_acls( interface_id => 45881 );
is(@$res, 1, '1 default acl rule added');
is($res->[0]{'eval_position'},10,'eval_position correct in default rule');
is($res->[0]{'allow_deny'},'allow','allow_deny correct in default rule');
is($res->[0]{'workgroup_id'},undef,'workgroup_id correct in default rule');
is($res->[0]{'interface_id'},45881,'interface_id correct in default rule');
is($res->[0]{'vlan_start'},-1,'vlan_start correct in default rule');
is($res->[0]{'vlan_end'},4095,'vlan_end correct in default rule');
is($res->[0]{'notes'},'Default ACL Rule','notes correct in default rule');

$success = $db->update_interface_owner( 
    interface_id => 45881,
	workgroup_id => undef,
);

ok($success, "workgroup acl was successfully removed");

$res = $db->get_interface( interface_id => 45881 );

is($res->{'workgroup_id'}, undef, 'interface removed from workgroup');
$res = $db->get_acls( interface_id => 45881 );
is(@$res, 0, 'acl rules removed');

