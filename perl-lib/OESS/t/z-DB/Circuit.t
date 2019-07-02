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
use Test::More tests => 9;

use OESSDatabaseTester;

use OESS::DB;
use OESS::DB::Circuit;


OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);


my $db = new OESS::DB(
    config  => "$path/../conf/database.xml"
);


my ($circuits_a, $err) = OESS::DB::Circuit::fetch_circuits(
    db => $db,
    circuit_id => 4081
);
warn $err if (defined $err);
ok(!defined $err, 'no error');

my $data = $circuits_a->[0];
ok($data->{circuit_id} == 4081, 'Found expected circuit');


$data->{user_id} = 11;
$data->{external_identifier} = 31;
$data->{description} = 'yeh yup';

my $update_err = OESS::DB::Circuit::update(
    db => $db,
    circuit => $data
);
warn $update_err if defined $update_err;
ok(!defined $update_err, 'no error');

my ($circuits_b, $err_b) = OESS::DB::Circuit::fetch_circuits(
    db => $db,
    circuit_id => 4081
);
warn $err_b if (defined $err_b);
ok(!defined $err_b, 'no error');

my $data_b = $circuits_b->[0];
ok($data_b->{circuit_id} == 4081, 'Found expected circuit');
ok($data_b->{user_id} == 11, 'Found expected user');
ok($data_b->{external_identifier} == 31, 'Found expected external id');
ok($data_b->{description} eq 'yeh yup', 'Found expected description');
ok($data->{start_epoch} != $data_b->{start_epoch}, 'New instantiation created');
