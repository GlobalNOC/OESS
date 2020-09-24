#!/user/bin/perl

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
use Test::More tests => 9;
use OESSDatabaseTester;

use OESS::DB;
use OESS::DB::ACL;

OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

my $db = new OESS::DB(
    config => "$path/../conf/database.xml"
);

my $workgroup_id =31;

eval {
    OESS::DB::ACL::create()
}; 

ok($@, "Correct dies when no db defined");

eval {
    OESS::DB::ACL::create( db => $db) 
};
ok($@,"Correct dies when no model defined");

my $model = {
    workgroup_id => 31,
    interface_id => 1,
    allow_deny => 'allow',
    eval_position => '1111',
    start => 1025,
    end => 1027,
    notes => undef,
    entity_id => 1
};

my ($id, $error) = OESS::DB::ACL::create( db => $db, model => $model);
ok(!defined $error, "No Error returned since both params were defined");

my ($delete, $err) = OESS::DB::ACL::remove();
ok(defined $err, "Returned Err because no DB was passed");

($delete, $err) = OESS::DB::ACL::remove(db => $db);
ok(defined $err, "Returned Err because no interface_acl_id was passed");

($delete, $err) = OESS::DB::ACL::remove(db => $db, interface_acl_id => $id);
ok(!defined $err, "No error returned since both params were defined and ACL was deleted");

($delete, $err) = OESS::DB::ACL::remove(db => $db, interface_acl_id => -1);
ok(defined $err, "Returned an error due to no interface_acl with id of -1 existing");

($id, $error) = OESS::DB::ACL::create( db => $db, model => $model);
$model->{eval_position} += 10;
($id, $error) = OESS::DB::ACL::create( db => $db, model => $model);
$model->{eval_position} += 10;
($id, $error) = OESS::DB::ACL::create( db => $db, model => $model);
$model->{eval_position} += 10;
($id, $error) = OESS::DB::ACL::create( db => $db, model => $model);

($delete, $err) = OESS::DB::ACL::remove_all(db => $db);
ok(defined $err, "Returned Err because no interface_id was passed");

($delete, $err) = OESS::DB::ACL::remove_all(db => $db, interface_id => 1);
ok($delete eq 5, "Deleted all four of the ACLs assigned to this Interface");
