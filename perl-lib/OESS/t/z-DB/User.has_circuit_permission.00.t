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
use Test::More tests => 80;

use OESSDatabaseTester;

use OESS::DB;
use OESS::DB::User;
use OESS::DB::Workgroup;
use OESS::DB::Circuit;

OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

my $db = new OESS::DB(
    config => "$path/../conf/database.xml"
);

$db->execute_query("update circuit set workgroup_id=31 where circuit_id=2281", []);
$db->execute_query("update interface set workgroup_id=21 where interface_id=401 or interface_id=751", []);

# user 501: workgroup 31 user with role admin + not in admin workgroup + not in workgroup 21
$db->execute_query("delete from user_workgroup_membership where user_id=501 and workgroup_id=11", []);
$db->execute_query("delete from user_workgroup_membership where user_id=501 and workgroup_id=21", []);
$db->execute_query(
    "insert into user_workgroup_membership (workgroup_id,user_id,role) values (?,?,?)",
    [31, 501, 'admin']
);

# user 601: workgroup 31 user with role normal + not in admin workgroup + not in workgroup 21
$db->execute_query("delete from user_workgroup_membership where user_id=601 and workgroup_id=11", []);
$db->execute_query("delete from user_workgroup_membership where user_id=601 and workgroup_id=21", []);
$db->execute_query(
    "insert into user_workgroup_membership (workgroup_id,user_id,role) values (?,?,?)",
    [31, 601, 'normal']
);

# user 701: workgroup 31 user with role read-only + not in admin workgroup + not in workgroup 21
$db->execute_query("delete from user_workgroup_membership where user_id=701 and workgroup_id=11", []);
$db->execute_query("delete from user_workgroup_membership where user_id=701 and workgroup_id=21", []);
$db->execute_query(
    "insert into user_workgroup_membership (workgroup_id,user_id,role) values (?,?,?)",
    [31, 701, 'read-only']
);

# user 201: workgroup user with role admin + not in admin workgroup + not in workgroup 31
$db->execute_query("delete from user_workgroup_membership where user_id=201 and workgroup_id=11", []);
$db->execute_query("delete from user_workgroup_membership where user_id=201 and workgroup_id=31", []);

# user 301: workgroup user with role normal + not in admin workgroup + not in workgroup 31
$db->execute_query("delete from user_workgroup_membership where user_id=301 and workgroup_id=11", []);
$db->execute_query("delete from user_workgroup_membership where user_id=301 and workgroup_id=31", []);
$db->execute_query(
    "insert into user_workgroup_membership (workgroup_id,user_id,role) values (?,?,?)",
    [21, 301, 'normal']
);

# user 401: workgroup user with role read-only + not in admin workgroup + not in workgroup 31
$db->execute_query("delete from user_workgroup_membership where user_id=401 and workgroup_id=11", []);
$db->execute_query("delete from user_workgroup_membership where user_id=401 and workgroup_id=31", []);
$db->execute_query(
    "insert into user_workgroup_membership (workgroup_id,user_id,role) values (?,?,?)",
    [21, 401, 'read-only']
);

# user 11 (aragusa): admin workgroup user with role admin + not in workgroup 21
$db->execute_query("update user_workgroup_membership set role='normal' where user_id=31 and workgroup_id=11", []);
$db->execute_query("delete from user_workgroup_membership where user_id=11 and workgroup_id=21", []);

# user 31: admin workgroup user with role normal + not in workgroup 21
$db->execute_query("update user_workgroup_membership set role='normal' where user_id=31 and workgroup_id=11", []);
$db->execute_query("delete from user_workgroup_membership where user_id=31 and workgroup_id=21", []);

# user 21: admin workgroup user with role read-only + not in workgroup 21
$db->execute_query("update user_workgroup_membership set role='read-only' where user_id=21 and workgroup_id=11", []);
$db->execute_query("delete from user_workgroup_membership where user_id=21 and workgroup_id=21", []);


# NOTE: circuit 2281 is owned by workgroup 31. interfaces 401 and 751
# used by circuit 2281 are owned by workgroup 21.

my $tests = [
    # BEGIN Circuit owners
    # user 501: workgroup 31 user with role admin + not in admin workgroup + not in workgroup 21
    { args => { db => $db, user_id => 501, circuit_id => 2281, permission => 'create' }, result => { value => 1, error => undef } },
    { args => { db => $db, user_id => 501, circuit_id => 2281, permission => 'read'   }, result => { value => 1, error => undef } },
    { args => { db => $db, user_id => 501, circuit_id => 2281, permission => 'update' }, result => { value => 1, error => undef } },
    { args => { db => $db, user_id => 501, circuit_id => 2281, permission => 'delete' }, result => { value => 1, error => undef } },

    # user 601: workgroup 31 user with role normal + not in admin workgroup + not in workgroup 21
    { args => { db => $db, user_id => 601, circuit_id => 2281, permission => 'create' }, result => { value => 1, error => undef } },
    { args => { db => $db, user_id => 601, circuit_id => 2281, permission => 'read'   }, result => { value => 1, error => undef } },
    { args => { db => $db, user_id => 601, circuit_id => 2281, permission => 'update' }, result => { value => 1, error => undef } },
    { args => { db => $db, user_id => 601, circuit_id => 2281, permission => 'delete' }, result => { value => 1, error => undef } },

    # user 701: workgroup 31 user with role read-only + not in admin workgroup + not in workgroup 21
    { args => { db => $db, user_id => 701, circuit_id => 2281, permission => 'create' }, result => { value => 0, error => 1 } },
    { args => { db => $db, user_id => 701, circuit_id => 2281, permission => 'read'   }, result => { value => 1, error => undef } },
    { args => { db => $db, user_id => 701, circuit_id => 2281, permission => 'update' }, result => { value => 0, error => 1 } },
    { args => { db => $db, user_id => 701, circuit_id => 2281, permission => 'delete' }, result => { value => 0, error => 1 } },
    # END Circuit owners

    # BEGIN Interface owners
    # user 201: workgroup user with role admin + not in admin workgroup
    { args => { db => $db, user_id => 201, circuit_id => 2281, permission => 'create' }, result => { value => 0, error => 1 } },
    { args => { db => $db, user_id => 201, circuit_id => 2281, permission => 'read'   }, result => { value => 1, error => undef } },
    { args => { db => $db, user_id => 201, circuit_id => 2281, permission => 'update' }, result => { value => 0, error => 1 } },
    { args => { db => $db, user_id => 201, circuit_id => 2281, permission => 'delete' }, result => { value => 0, error => 1 } },

    # user 301: workgroup user with role normal + not in admin workgroup
    { args => { db => $db, user_id => 301, circuit_id => 2281, permission => 'create' }, result => { value => 0, error => 1 } },
    { args => { db => $db, user_id => 301, circuit_id => 2281, permission => 'read'   }, result => { value => 1, error => undef } },
    { args => { db => $db, user_id => 301, circuit_id => 2281, permission => 'update' }, result => { value => 0, error => 1 } },
    { args => { db => $db, user_id => 301, circuit_id => 2281, permission => 'delete' }, result => { value => 0, error => 1 } },

    # user 401: workgroup user with role normal + not in admin workgroup
    { args => { db => $db, user_id => 301, circuit_id => 2281, permission => 'create' }, result => { value => 0, error => 1 } },
    { args => { db => $db, user_id => 301, circuit_id => 2281, permission => 'read'   }, result => { value => 1, error => undef } },
    { args => { db => $db, user_id => 301, circuit_id => 2281, permission => 'update' }, result => { value => 0, error => 1 } },
    { args => { db => $db, user_id => 301, circuit_id => 2281, permission => 'delete' }, result => { value => 0, error => 1 } },
    # END Interface owners

    # BEGIN Admins
    # admin workgroup user with a role of admin. has global access to everything.
    { args => { db => $db, username => 'aragusa', circuit_id => 2281, permission => 'create' }, result => { value => 1, error => undef } },
    { args => { db => $db, username => 'aragusa', circuit_id => 2281, permission => 'read'   }, result => { value => 1, error => undef } },
    { args => { db => $db, username => 'aragusa', circuit_id => 2281, permission => 'update' }, result => { value => 1, error => undef } },
    { args => { db => $db, username => 'aragusa', circuit_id => 2281, permission => 'delete' }, result => { value => 1, error => undef } },

    # admin workgroup user with a role of normal. has global access to circuits.
    { args => { db => $db, user_id => 31, circuit_id => 2281, permission => 'create' }, result => { value => 1, error => undef } },
    { args => { db => $db, user_id => 31, circuit_id => 2281, permission => 'read'   }, result => { value => 1, error => undef } },
    { args => { db => $db, user_id => 31, circuit_id => 2281, permission => 'update' }, result => { value => 1, error => undef } },
    { args => { db => $db, user_id => 31, circuit_id => 2281, permission => 'delete' }, result => { value => 1, error => undef } },

    # admin workgroup user with a role of read-only. has global read access to circuits.
    { args => { db => $db, user_id => 21, circuit_id => 2281, permission => 'create' }, result => { value => 0, error => 1 } },
    { args => { db => $db, user_id => 21, circuit_id => 2281, permission => 'read'   }, result => { value => 1, error => undef } },
    { args => { db => $db, user_id => 21, circuit_id => 2281, permission => 'update' }, result => { value => 0, error => 1 } },
    { args => { db => $db, user_id => 21, circuit_id => 2281, permission => 'delete' }, result => { value => 0, error => 1 } },
    # END Admins

    # user not in admin workgroup, circuit workgroup, or circuit's interfaces' workgroup
    { args => { db => $db, user_id => 371, circuit_id => 2281, permission => 'create' }, result => { value => 0, error => 1 } },
    { args => { db => $db, user_id => 371, circuit_id => 2281, permission => 'read'   }, result => { value => 0, error => 1 } },
    { args => { db => $db, user_id => 371, circuit_id => 2281, permission => 'update' }, result => { value => 0, error => 1 } },
    { args => { db => $db, user_id => 371, circuit_id => 2281, permission => 'delete' }, result => { value => 0, error => 1 } },
];

foreach my $test (@$tests) {
    my ($result, $error) = OESS::DB::User::has_circuit_permission(%{$test->{args}});

    ok($result == $test->{result}->{value}, "Got '$result'. Expected '$test->{result}->{value}'.");
    if (defined $test->{result}->{error}) {
        ok(defined $error, "Got error message '$error'. Expected an error message.");
    } else {
        my $error_str = (!defined $error) ? 'undef' : $error;
        ok(!defined $error, "Got error message '$error_str'. Expected error message 'undef'.");
    }
}
