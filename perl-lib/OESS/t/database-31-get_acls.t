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

use Test::More tests => 12;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $acls = $db->get_acls( owner_workgroup_id => 1 );
is(@$acls, 5, '5 ACLs Retrieved');

my $acl = $acls->[0];

is($acl->{'vlan_end'},200,'vlan_end ok');
is($acl->{'vlan_start'},101,'vlan_start ok');
is($acl->{'workgroup_id'},21,'workgroup_id ok');
is($acl->{'interface_id'},45901,'interface_id ok');
is($acl->{'interface_acl_id'},1,'interface_acl_id ok');
is($acl->{'eval_position'},10,'eval_position ok');
is($acl->{'allow_deny'},'deny','allow_deny ok');
is($acl->{'notes'},'ima note','notes ok');

$acls = $db->get_acls( interface_id => 45811 );
is(@$acls, 6, '6 ACLs Retrieved');

$acls = $db->get_acls( interface_acl_id => 1 );
is(@$acls, 1, '1 ACLs Retrieved');

$acls = $db->get_acls( );
is(@$acls, 15, '15 ACLs Retrieved');
