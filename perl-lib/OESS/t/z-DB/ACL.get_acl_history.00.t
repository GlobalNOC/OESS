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
use Test::More tests => 8;
use OESSDatabaseTester;
use OESS::DB;
use OESS::DB::ACL;
use OESS::ACL;
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
ok(!defined $error, "No errors creating ACL");
$ENV{REMOTE_USER} = 'admin';

my ($history, $error) = OESS::DB::ACL::get_acl_history( db => $db, interface_acl_id => $id, interface_id => $model->{interface_id}, workgroup_id => $model->{workgroup_id});
ok(defined $history, "No errors getting ACL history");
ok(@$history[0]->{'event'} eq "ACL Created", "ACL history create event correctly set");

$model->{eval_position} += 10;
$model->{interface_acl_id} = $id;
my ($update, $error) = OESS::DB::ACL::update( db => $db, acl => $model);
ok(defined $update, "No errors updating ACL");

$history = $db->execute_query("select * from acl_history where event = 'ACL Updated'");
ok(@$history[0]->{'event'} eq "ACL Updated", "ACL history update event correctly set");

my ($delete, $err) = OESS::DB::ACL::remove(db => $db, interface_acl_id => $id);
ok(!defined $err, "No error returned since both params were defined and ACL was deleted");

$history = $db->execute_query("select * from acl_history where event = 'ACL Removed'");
ok(@$history[0]->{'event'} eq "ACL Removed", "ACL history remove event correctly set");

$model->{eval_position} += 10;
($id, $error) = OESS::DB::ACL::create( db => $db, model => $model);
$model->{eval_position} += 10;
($id, $error) = OESS::DB::ACL::create( db => $db, model => $model);
$model->{eval_position} += 10;
($id, $error) = OESS::DB::ACL::create( db => $db, model => $model);

($delete, $err) = OESS::DB::ACL::remove_all(db => $db, interface_id => 1);
my $count = $db->execute_query("select * from acl_history where event = 'ACL Removed' and interface_id = 1");
ok(scalar(@$count) == 3, "ACL history remove event correctly set");