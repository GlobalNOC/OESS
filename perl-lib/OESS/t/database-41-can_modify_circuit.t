#!/usr/bin/perl -T
#can_modify_circuit.t
use strict;

use FindBin;
my $path;

BEGIN {
    if($FindBin::Bin =~ /(.*)/){
            $path = $1;
      }
}

use lib "$path";
use OESS::Database;
use OESS::Measurement;
use OESS::Circuit;
use OESSDatabaseTester;
use Data::Dumper;
use Test::More tests => 2;
use Test::Deep;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $results = $db->get_user_by_id(user_id => '21');

my $username = $results->[0]{'auth_name'};

my $can_mod_value = $db->can_modify_circuit(circuit_id   => 1,
                        username     => $username,
                        workgroup_id => 11);
my @username = ($username);
ok($can_mod_value == 1, 'is the initial value of the user one?');
#set the user's status to decom
$db->edit_user(user_id => 21, status => 'decom', given_name => $results->[0]{'given_names'}, type => $results->[0]{'type'}, auth_names => \@username,  email => $results->[0]{'email'}, family_name => $results->[0]{'family_name'});

$can_mod_value = $db->can_modify_circuit(circuit_id   => 1,
                        username     => $username,
                        workgroup_id => 11);
ok($can_mod_value ==0, 'is the user now blocked from doing anything?');

#let's put it back to what it was so we don't upset a future unit test.

$db->edit_user(user_id => 21, status_of_user => 'active', 'given_names' => $results->[0]{'given_names'}, 'type' => $results->[0]{'type'}, 'auth_names' => \@username,  'email' => $results->[0]{'email'}, 'family_name' => $results->[0]{'family_name'});


