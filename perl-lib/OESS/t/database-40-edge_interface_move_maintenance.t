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

use Data::Dumper;
use Test::More tests => 16;
use Test::Deep::NoTest;
use OESS::Database;
use OESS::Circuit;
use OESSDatabaseTester;

my $orig_interface_id = 321;
my $temp_interface_id = 401;
my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

sub main {
    # get the circuit edge records before doing any tests 
    my $edge_recs_orig = _get_edge_recs( $orig_interface_id ); 
    my $edge_recs_temp = _get_edge_recs( $temp_interface_id ); 

    my $maintenance_id = test_maintenance_add(
        before_edge_recs_orig => $edge_recs_orig, 
        before_edge_recs_temp => $edge_recs_temp
    );

    test_maintenance_revert(
        before_edge_recs_orig => $edge_recs_orig, 
        before_edge_recs_temp => $edge_recs_temp,
        maintenance_id        => $maintenance_id
    );
}

sub test_maintenance_add {
    my %args = @_;
    my $before_edge_recs_orig = $args{'before_edge_recs_orig'}; 
    my $before_edge_recs_temp = $args{'before_edge_recs_temp'}; 

    # add maintenance 
    my $maintenance_id = $db->add_edge_interface_move_maintenance (
        name              => "Test Maintenance",
        orig_interface_id => $orig_interface_id,
        temp_interface_id => $temp_interface_id
    );


    #verify maintenance was successfully added
    ok(defined($maintenance_id), "maintenance successfully added") or diag("DB ERROR: ".$db->get_error()); 

    #verify counts are what we would expect
    my $after_edge_recs_orig = _get_edge_recs( $orig_interface_id ); 
    my $after_edge_recs_temp = _get_edge_recs( $temp_interface_id ); 

    # original interface should not have any edge records associated with it
    my $orig_count_after     = scalar(@$after_edge_recs_orig);
    my $orig_count_after_exp = 0;
    is($orig_count_after, $orig_count_after_exp, "count on orig int is correct");

    # temporary interface should have it's intial records plus the original interfaces records
    my $temp_count_after     = scalar(@$after_edge_recs_temp);
    my $temp_count_after_exp = scalar(@$before_edge_recs_orig) + scalar(@$before_edge_recs_temp);
    is($temp_count_after, $temp_count_after_exp, "count on temp int is correct");

    # get maintence record and verify it looks correct
    my $maintenances = $db->get_edge_interface_move_maintenances(
        maintenance_id => $maintenance_id,
        show_moved_circuits => 1
    );
    ok((defined($maintenances) && @$maintenances > 0), "retrieved maintenance record");

    my $maint = $maintenances->[0];
    is($maint->{'name'}, "Test Maintenance", "maint name correct");
    is($maint->{'orig_interface_id'}, $orig_interface_id, "maint orig_interface_id correct");
    is($maint->{'temp_interface_id'}, $temp_interface_id, "maint temp_interface_id correct");
    is($maint->{'maintenance_id'}, $maintenance_id, "maint maintenance_id correct");
    is($maint->{'end_epoch'}, -1, "maint end_epoch correct");
    ok(defined($maint->{'start_epoch'}), "start_epoch defined");

    # verify the circuits on the original interface are our moved_circuits
    my $circuit_ids = {};
    foreach my $edge_rec (@$before_edge_recs_orig){
        $circuit_ids->{$edge_rec->{'circuit_id'}} = 1;
    }
    is(scalar(keys %$circuit_ids), scalar(@{$maint->{'moved_circuits'}}), "circuit count correct");

    # verify correct circuit were moved
    my $found_all_circuits = 1;
    foreach my $moved_circuit (@{$maint->{'moved_circuits'}}){
        if(!$circuit_ids->{$moved_circuit->{'circuit_id'}}){
            $found_all_circuits = 0;
            last;
        }
    }
    ok($found_all_circuits, "correct circuits moved");
}

sub test_maintenance_revert {
    my %args = @_;
    my $before_edge_recs_orig = $args{'before_edge_recs_orig'}; 
    my $before_edge_recs_temp = $args{'before_edge_recs_temp'}; 
    my $maintenance_id        = $args{'maintenance_id'};

    # add maintenance 
    my $res = $db->revert_edge_interface_move_maintenance (
        maintenance_id => $maintenance_id 
    );
    #verify maintenance was successfully added
    ok(defined($res), "maintenance successfully reverted") or diag("DB ERROR: ".$db->get_error()); 

    #verify counts are what we would expect
    my $after_edge_recs_orig = _get_edge_recs( $orig_interface_id );
    my $after_edge_recs_temp = _get_edge_recs( $temp_interface_id );

    # original interface should be returned to its initial count
    my $orig_count_after     = scalar(@$after_edge_recs_orig);
    my $orig_count_after_exp = scalar(@$before_edge_recs_orig);
    is($orig_count_after, $orig_count_after_exp, "count on orig int is correct");

    # temporary interface should be returned to its initial count
    my $temp_count_after     = scalar(@$after_edge_recs_temp);
    my $temp_count_after_exp = scalar(@$before_edge_recs_temp);
    is($temp_count_after, $temp_count_after_exp, "count on temp int is correct");

    # verify end_epoch is now set
    # get maintence record and verify it looks correct
    my $maintenances = $db->get_edge_interface_move_maintenances(
        maintenance_id => $maintenance_id
    );
    is(scalar(@$maintenances), 0, "no maintenance record returned");
    
}

sub _get_edge_recs {
    my $interface_id = shift;

    my $ckt_edge_recs_query = 'SELECT * '.
                              'FROM circuit_edge_interface_membership '.
                              'WHERE end_epoch = -1 '.
                              'AND interface_id = ?';

    return $db->_execute_query($ckt_edge_recs_query, [$interface_id]);
}


main();
