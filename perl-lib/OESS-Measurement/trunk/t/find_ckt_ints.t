#!/usr/bin/perl

use Data::Dumper;
use strict;
use Test::More tests => 1;
use OESS::Measurement;

my $meas = OESS::Measurement->new();

my $data = $meas->get_circuit_data(circuit_id => 3, start_time => 1316029378, end_time => 1316115778);
print STDERR Dumper($data);
