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

use Test::More tests => 27;
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

# Make a default interface rule that does NOT support tagging ISSUE=9287
$success = $db->update_interface_owner(interface_id => 45571, workgroup_id => 1);
$res = $db->get_acls( interface_id => 45571 );
is($res->[0]{'vlan_start'},1,'vlan_start correct in default rule');
is($res->[0]{'vlan_end'},4095,'vlan_end correct in default rule');

# Check that an error is thrown when attepting to associate a second
# time.
$success = $db->update_interface_owner(interface_id => 45571, workgroup_id => 1);
$error = $db->get_error();
ok(!defined $success, "Interface could not associate a second time.");
ok(defined $error, "Error was received.");

# 51 is a trunk interface, and cannot be associated with non-admin
# workgroups.
$success = $db->update_interface_owner(interface_id => 51,
                                       workgroup_id => 1);
$error = $db->get_error();
ok(!defined $success, "Trunk interface wasn't associated with non-admin workgroup.");
ok(defined $error, "Error was received.");

# $success = $db->update_interface_owner(interface_id => 51,
#                                        workgroup_id => 263);
# ok(defined $success, "Trunk interface was associated with admin workgroup.");

# $success = $db->update_interface_owner(interface_id => 51, workgroup_id => undef);
# ok($success, "workgroup acl was successfully removed");

# Check that proper error is received when non-existent workgroup is used
$success = $db->update_interface_owner(interface_id => 45881, workgroup_id => 999);
$error = $db->get_error();
ok(!defined $success, "Interface could not be associated with non-existent workgroup.");
ok(defined $error, "Error was received.");

$success = $db->update_interface_owner(interface_id => 45881, workgroup_id => undef);
ok($success, "workgroup acl was successfully removed");

# Check that an error is thrown when attepting to dis-associate a
# second time.
$success = $db->update_interface_owner(interface_id => 45881, workgroup_id => undef);
$error = $db->get_error();
ok(!defined $success, "Interface could not dis-associate a second time.");
ok(defined $error, "Error was received.");

$res = $db->get_interface( interface_id => 45881 );
is($res->{'workgroup_id'}, undef, 'interface removed from workgroup');
$res = $db->get_acls( interface_id => 45881 );
is(@$res, 0, 'acl rules removed');

