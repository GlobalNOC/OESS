#!/usr/bin/perl -T

use strict;
use warnings;
use OESS::FlowRule;

use Data::Dumper;
use Storable qw( dclone );
use Test::More tests => 6;
use Test::Deep;

# initialize our base flow rule
my %match = ( match=> { dl_vlan => 1, in_port => 1} ); # match is the same for all tests
my $fr = OESS::FlowRule->new( %match,
    actions => [{
        set_vlan_id => 2
    },{
        output => 2
    }]
);

# merge a flow with the same actions
$fr->merge_actions( flow_rule => same_as_orig() );
ok( $fr->compare_actions( 
    flow_rule => same_as_orig( expected_result => 1 )
), "Flow is unchanged when merging exact same rule" );

# merge a flow with different set action
$fr->merge_actions( flow_rule => diff_set_action() );
ok( $fr->compare_actions( 
    flow_rule => diff_set_action( expected_result => 1 )
), "Merged action with different set appears at the end of the list" );

# merge a flow with different output action
$fr->merge_actions( flow_rule => diff_output_action() );
ok( $fr->compare_actions( 
    flow_rule => diff_output_action( expected_result => 1 )
), "Merged action with different output appears at the end of the list" );

# merge a flow with the same actions in the middle of the list
$fr->merge_actions( flow_rule => same_as_orig_2() );
ok( $fr->compare_actions( 
    flow_rule => same_as_orig_2( expected_result => 1 )
), "Flow is unchanged after merging actions it already had" );

# merge a flow with different set action and different output action
$fr->merge_actions( flow_rule => diff_set_and_output_action() );
ok( $fr->compare_actions( 
    flow_rule => diff_set_and_output_action( expected_result => 1 )
), "Merged action with different set and output appears at the end of the list" );


my $fr = OESS::FlowRule->new( %match,
                              actions => [{set_vlan_id => 2},
                                          {output => 2}]);

$fr->merge_actions( flow_rule => OESS::FlowRule->new( %match,
                                                      actions => [{set_vlan_id => 2},
                                                                  {output => 3}]));

$fr->merge_actions( flow_rule => OESS::FlowRule->new( %match,
                                                      actions => [{set_vlan_id => 2},
                                                                  {output => 4}]));

$fr->merge_actions( flow_rule => OESS::FlowRule->new( %match,
                                                      actions => [{set_vlan_id => 2},
                                                                  {output => 4}]));

ok( $fr->compare_actions( flow_rule => OESS::FlowRule->new( %match,
                                                            actions => [{set_vlan_id => 2},
                                                                        {output => 2},
                                                                        {set_vlan_id => 2},
                                                                        {output => 3},
                                                                        {set_vlan_id => 2},
                                                                        {output => 4}])),
"Multiple merge actions with the same set of actions did not duplicate actions");
                                                            
sub same_as_orig {
    return OESS::FlowRule->new( %match,
        actions => [{
            set_vlan_id => 2
        },{
            output => 2
        }]
    );
}

sub diff_set_action {
    my %args = @_;
    # return expected result
    if($args{'expected_result'}){
        return OESS::FlowRule->new( %match,
            actions => [{
                set_vlan_id => 2
            },{
                output => 2
            },{
                set_vlan_id => 3
            },{
                output => 2
            }]
        );

    } 
    # return flow to merge for test 
    else {
        return OESS::FlowRule->new(
            actions => [{
                set_vlan_id => 3
            },{
                output => 2
            }]
        );
    }
}

sub diff_output_action {
    my %args = @_;
    # return expected result
    if($args{'expected_result'}){
        return OESS::FlowRule->new( %match,
            actions => [{
                set_vlan_id => 2
            },{
                output => 2
            },{
                set_vlan_id => 3
            },{
                output => 2
            },{
                set_vlan_id => 2
            },{
                output => 3
            }]
        );
    }
    # return flow to merge for test
    else {
        return OESS::FlowRule->new( %match,
            actions => [{
                set_vlan_id => 2
            },{
                output => 3
            }]
        );
    }
}


sub same_as_orig_2 {

    my %args = @_;
    # return expected result
    if($args{'expected_result'}){
        return OESS::FlowRule->new( %match,
            actions => [{
                set_vlan_id => 2
            },{
                output => 2
            },{
                set_vlan_id => 3
            },{
                output => 2
            },{
                set_vlan_id => 2
            },{
                output => 3
            }]
        );
    }
    # push an action that is already contained in the middle of our current actions 
    else {
        return OESS::FlowRule->new( %match,
            actions => [{
                set_vlan_id => 3
            },{
                output => 2
            }]
        );
    }
}


sub diff_set_and_output_action {

    my %args = @_;
    # return expected result
    if($args{'expected_result'}){
        return OESS::FlowRule->new( %match,
            actions => [{
                set_vlan_id => 2
            },{
                output => 2
            },{
                set_vlan_id => 3
            },{
                output => 2
            },{
                set_vlan_id => 2
            },{
                output => 3
            },{
                set_vlan_id => 4
            },{
                output => 4
            }]
        );
    }
    # push an actions with different set and output values than what 
    # we've seen before 
    else {
        return OESS::FlowRule->new( %match,
            actions => [{
                set_vlan_id => 4
            },{
                output => 4
            }]
        );
    }
}
