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

use Test::More tests => 30;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $acl_id = $db->update_acl(
    interface_acl_id => 3, 
    user_id          => 11,
    workgroup_id     => 61,
    interface_id     => 45811,
    allow_deny       => 'allow',
    eval_position    => 10,
    vlan_start       => 200,
    vlan_end         => 99,
    notes            => undef
);
ok(!$acl_id, 'vlan range sanity check');
is($db->get_error(),'vlan_end can not be less than vlan_start','correct error');

$acl_id = $db->update_acl(
    interface_acl_id => 3, 
    user_id          => 11,
    workgroup_id     => 61,
    interface_id     => 45811,
    allow_deny       => 'allow',
    eval_position    => 10,
    vlan_start       => -1,
    vlan_end         => 99,
    notes            => undef
);
ok(!$acl_id, 'vlan range sanity check');
is($db->get_error(),'-1-99 does not fall within the vlan tag range defined for the interface, 1-4095','correct error');

$acl_id = $db->update_acl(
    interface_acl_id => 3, 
    user_id          => 301,
    workgroup_id     => 31,
    interface_id     => 45811,
    allow_deny       => 'deny',
    eval_position    => 10,
    vlan_start       => 102,
    vlan_end         => undef,
    notes            => undef
);
ok(!$acl_id, 'authorization check');
is($db->get_error(),'Access Denied','correct error');

$acl_id = $db->update_acl(
    interface_acl_id => 3, 
    user_id          => 11,
    workgroup_id     => 61,
    interface_id     => 45811,
    allow_deny       => 'allow',
    eval_position    => 10,
    vlan_start       => 200,
    vlan_end         => 210,
    notes            => undef
);
ok($acl_id, 'acl updated');

my $acls = $db->get_acls( interface_acl_id => 3 );
is(@$acls, 1, '1 ACL Retrieved');
my $acl = $acls->[0];

is($acl->{'vlan_end'},210,'vlan_end ok');
is($acl->{'vlan_start'},200,'vlan_start ok');
is($acl->{'workgroup_id'},61,'workgroup_id ok');
is($acl->{'interface_id'},45811,'interface_id ok');
is($acl->{'interface_acl_id'},3,'interface_acl_id ok');
is($acl->{'eval_position'},10,'eval_position ok');
is($acl->{'allow_deny'},'allow','allow_deny ok');
is($acl->{'notes'},undef,'notes ok');

# try to add acl to a higher value at same eval position as another acl
$acl_id = $db->update_acl(
    interface_acl_id  => 3, 
    user_id           => 11,
    workgroup_id      => 61,
    interface_id      => 45811,
    allow_deny        => 'allow',
    eval_position     => 30,
    vlan_start        => 200,
    vlan_end          => 210,
    notes             => undef
);

# make sure the eval_position reordering worked correctly
$acls = $db->get_acls( owner_workgroup_id => 51 );
is(@$acls, 6, '6 ACLs Retrieved');
is($acls->[0]{'interface_acl_id'},4, 'correct order');
is($acls->[1]{'interface_acl_id'},5, 'correct order');
is($acls->[2]{'interface_acl_id'},3, 'correct order');
is($acls->[3]{'interface_acl_id'},6, 'correct order');
is($acls->[4]{'interface_acl_id'},7, 'correct order');
is($acls->[5]{'interface_acl_id'},8, 'correct order');

# try to add acl to a lower value at same eval position as another acl
$acl_id = $db->update_acl(
    interface_acl_id  => 7,
    user_id           => 11,
    workgroup_id      => 61,
    interface_id      => 45811,
    allow_deny        => 'allow',
    eval_position     => 10,
    vlan_start        => 200,
    vlan_end          => 210,
    notes             => undef
);
# make sure the eval_position reordering worked correctly
my $acls = $db->get_acls( owner_workgroup_id => 51 );
is(@$acls, 6, '6 ACLs Retrieved');
is($acls->[0]{'interface_acl_id'},7, 'correct order');
is($acls->[1]{'interface_acl_id'},4, 'correct order');
is($acls->[2]{'interface_acl_id'},5, 'correct order');
is($acls->[3]{'interface_acl_id'},3, 'correct order');
is($acls->[4]{'interface_acl_id'},6, 'correct order');
is($acls->[5]{'interface_acl_id'},8, 'correct order');

