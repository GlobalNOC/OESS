#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
my $path;

BEGIN {
    if ($FindBin::Bin =~ /(.*)/) {
        $path = $1;
    }
}

use lib "$path/..";
use Data::Dumper;
use Test::More tests => 3;
use OESSDatabaseTester;
use OESS::DB;
use OESS::DB::ACL;
use OESS::Config;

OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

my $test_config = new OESS::Config(config_filename => "$path/../conf/database.xml");
my $workgroup_id = 31;

my $db = new OESS::DB(
    config  => "$path/../conf/database.xml"
);

my $model = {
    workgroup_id => 31,
    interface_id => 1,
    allow_deny => 'allow',
    eval_position => '1111',
    start => 1025,
    end => 1027,
    notes => undef,
    entity_id => 1,
    user_id => 1
};

my ($id, $error) = OESS::DB::ACL::create( db => $db, model => $model);
ok(!defined $error, "OK - No errors creating ACl");
my $test = $db->execute_query("select * from acl_history where interface_id = 1");

my ($history, $error) = OESS::DB::ACL::get_acl_history( db => $db, interface_acl_id => $id, interface_id => $model->{interface_id}, workgroup_id => $model->{workgroup_id});
ok(defined $history, "OK - No errors getting ACL history");
ok(@$history[0]->{'event'} eq "ACL Created", "ACL history event correctly set");