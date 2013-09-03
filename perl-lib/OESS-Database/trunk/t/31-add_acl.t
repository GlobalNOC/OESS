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

use Test::More tests => 21;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $acl_id = $db->add_acl(
    user_id       => 11,
    workgroup_id  => 31,
    interface_id  => 45851,
    allow_deny    => 'deny',
    eval_position => 20,
    vlan_start    => 100,
    vlan_end      => 99,
    notes         => undef
);
ok(!$acl_id, 'vlan_range sanity check 1');
is($db->get_error(),'vlan_end can not be less than vlan_start','correct error');

$acl_id = $db->add_acl(
    user_id       => 11,
    workgroup_id  => 31,
    interface_id  => 45851,
    allow_deny    => 'deny',
    eval_position => 20,
    vlan_start    => -1,
    vlan_end      => 4095,
    notes         => undef
);
ok(!$acl_id, 'vlan_range sanity check 1');
is($db->get_error(),'-1-4095 does not fall within the vlan tag range defined for the interface, 1-4095','correct error');


$acl_id = $db->add_acl(
    user_id       => 301,
    workgroup_id  => 21,
    interface_id  => 45841,
    allow_deny    => 'allow',
    eval_position => 10,
    vlan_start    => 101,
    vlan_end      => 200,
    notes         => "ima note"
);
ok(!$acl_id, 'authorization check');
is($db->get_error(),'Access Denied','correct error');

$acl_id = $db->add_acl(
    user_id       => 11,
    workgroup_id  => 31,
    interface_id  => 45851,
    allow_deny    => 'deny',
    eval_position => 20,
    vlan_start    => 100,
    vlan_end      => undef,
    notes         => undef
);
ok($acl_id, 'acl added');

my $acls = $db->get_acls( owner_workgroup_id => 11 );
is(@$acls, 1, '1 ACL Retrieved');
my $acl = $acls->[0];

is($acl->{'vlan_end'},undef,'vlan_end ok');
is($acl->{'vlan_start'},100,'vlan_start ok');
is($acl->{'workgroup_id'},31,'workgroup_id ok');
is($acl->{'interface_id'},45851,'interface_id ok');
is($acl->{'interface_acl_id'},$acl_id,'interface_acl_id ok');
is($acl->{'eval_position'},20,'eval_position ok');
is($acl->{'allow_deny'},'deny','allow_deny ok');
is($acl->{'notes'},undef,'notes ok');

# try to add acl at same eval position
$acl_id = $db->add_acl(
    user_id       => 11,
    workgroup_id  => 31,
    interface_id  => 45851,
    allow_deny    => 'deny',
    eval_position => 20,
    vlan_start    => 100,
    vlan_end      => undef,
    notes         => undef
);

ok(!$acl_id, 'stopped when adding at same eval position');
is($db->get_error(), 'There is already an acl at eval position 20', 'correct error');

# check that next available eval_position is chosen when none is passed in 
$acl_id = $db->add_acl(
    user_id       => 11,
    workgroup_id  => 31,
    interface_id  => 45851,
    allow_deny    => 'deny',
    vlan_start    => 100,
    vlan_end      => undef,
    notes         => undef
);

ok($acl_id, 'acl added');

my $acls = $db->get_acls( owner_workgroup_id => 11 );
is(@$acls, 2, '2 ACLs Retrieved');
is($acls->[1]{'eval_position'}, '30', 'correct eval position');

