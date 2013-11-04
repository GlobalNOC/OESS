#!/usr/bin/perl

#------ NDDI OESS FlowRule Interaction Module
##-----
##----- $HeadURL: $
##----- $Id$
##----- $Date$
##----- $LastChangedBy$
##-----
##----- Provides object oriented methods to interact with OESS FlowRules
##-------------------------------------------------------------------------
##
## Copyright 2011 Trustees of Indiana University 
## 
##   Licensed under the Apache License, Version 2.0 (the "License");
##  you may not use this file except in compliance with the License.
##   You may obtain a copy of the License at
##
##       http://www.apache.org/licenses/LICENSE-2.0
##
##   Unless required by applicable law or agreed to in writing, software
##   distributed under the License is distributed on an "AS IS" BASIS,
##   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
##   See the License for the specific language governing permissions and
##   limitations under the License.
#

=head1 NAME

OESS::FlowRule - OESS representation of FlowRules

=head1 VERSION

Version 1.1.1

=cut

our $VERSION = '1.1.1';

=head1 SYNOPSIS

This module is designed to be a single point of interaction with flow rules
and allows us to use the same object to represent flow rules for DBus transportaion
logging, human readible text etc...

an example

use OESS::FlowRules;
my $flow_rule = OESS::FlowRule->new(dpid => $dpid,
                                    match => {'in_port' => 678,
                                              'dl_vlan' => 100},
                                    actions => [{'output' => 679},
                                               {'set_vlan_vid' => 200}]);

$of_controller->install_datapath_flow($flow_rule->to_dbus());

print $flow_rule->to_human_readible();

=cut

use strict;
use warnings;
use Switch;
use Data::Dumper;
use Net::DBus;

package OESS::FlowRule;

use constant OFPAT_OUTPUT       => 0;
use constant OFPAT_SET_VLAN_VID => 1;
use constant OFPAT_SET_VLAN_PCP => 2;
use constant OFPAT_STRIP_VLAN   => 3;
use constant OFPAT_SET_DL_SRC   => 4;
use constant OFPAT_SET_DL_DST   => 5;
use constant OFPAT_SET_NW_SRC   => 6;
use constant OFPAT_SET_NW_DST   => 7;
use constant OFPAT_SET_NW_TOS   => 8;
use constant OFPAT_SET_TP_SRC   => 9;
use constant OFPAT_SET_TP_DST   => 10;
use constant OFPAT_ENQUEUE      => 11;
use constant OFPAT_VENDOR       => 65535;
use constant OFPP_CONTROLLER    => 65533;

sub new{
    my $that = shift;
    my $class = ref($that) || $that;

    my %args = (
	priority => 32768,
	match => {},
	action => [],
	dpid => undef,
	@_
	);

    my $self = \%args;
    bless $self, $class;

    my $validate_flow = $self->validate_flow();
    
    return $self;
    
}


=head2 validate_flow

validates that the flow_rule is valid

=cut

sub validate_flow{
    my $self = shift;

    if($self->_validate_match($self->{'match'}) && $self->_validate_actions($self->{'actions'}) && $self->_validate_priority($self->{'priority'}) && $self->_validate_dpid($self->{'dpid'})){
	return 1;
    }else{
	return;
    }
    

}

=head2 _validate_match

=cut

sub _validate_match{
    my $self = shift;
    my $match = shift;

    

    return 1;
}


=head2 _validate_actions

=cut

sub _validate_actions{
    my $self = shift;
    my $actions = shift;

    return 1;
}

=head2 _validate_vlan_id

=cut

sub _validate_vlan_id{
    my $self = shift;
    my $vlan_id = shift;

    if($vlan_id > 0 && $vlan_id < 4096){
	return 1;
    }

    $self->_set_error("VLAN ID must be between 1 and 4095");
    return;
}

=head2 _validate_port

=cut

sub _validate_port{
    my $self = shift;
    my $port = shift;

    if($port > 0 && $port <= 65535){
	return 1;
    }


    $self->_set_error("Port IDs must be between 1 and 65535");
}

=head2 _validate_priority

=cut

sub _validate_priority{
    my $self = shift;
    my $priority = shift;

    if($priority > 0 && $priority <= 65535){
	return 1;
    }

    $self->_set_error("Priority does not follow spec... must be an integer between 1 and 65535");

    return 0;
}

=head2 _validate_dpid

=cut

sub _validate_dpid{
    my $self = shift;
    return 1;
}
=head2 set_match

=cut

sub set_match{
    my $self = shift;
    my $new_match = shift;

    if($self->_validate_match($new_match)){
	$self->{'match'} = $new_match;
	return 1;
    }else{
	return;
    }


}

=head2 set_action

=cut

sub set_action{
    my $self = shift;
    my $new_actions = shift;

    if($self->_validate_actions($new_actions)){
	$self->{'actions'} = $new_actions;
	return 1;
    }else{
	return;
    }
    
   
}

=head2 set_priority

=cut

sub set_priority{
    my $self = shift;
    my $new_priority = shift;

    if($self->_validate_priority($new_priority)){
	$self->{'priority'} = $new_priority;
	return 1;
    }else{
	return;
    }
    
}

=head2 set_dpid

=cut

sub set_dpid{
    my $self = shift;
    my $new_dpid = shift;

    if($self->_validate_dpid($new_dpid)){
	$self->{'dpid'} = $new_dpid;
	return 1;
    }else{
	$self->_set_error("DPID: " . $new_dpid . " is not a valid DPID, please try again");
	return;
    }
    
}

=head2 to_dbus

    convert the flow rule into something we can send over DBus

=cut

sub to_dbus{
    my $self = shift;

    my $command;
    
    my @actions;
    for(my $i=0;$i<= $#{$self->{'actions'}};$i++){
	my @tmp;
	my $action = $self->{'actions'}->[$i];

	foreach my $key (keys (%$action)){
	    switch ($key){
		case "output" {
		    #look at OF1.0 spec when sending ofp_action_output
		    #it takes a max_length and a port
		    #max length is only used when forwarding to controller
		    #max_length defaults to 0 if not specified
		    my $max_length;
		    my $out_port;

		    if(ref($action->{$key}) ne 'HASH'){
			$out_port = $action->{$key};
			$max_length = 0;
		    }else{
			$max_length = $action->{$key}->{'max_length'};
			$out_port = $action->{$key}->{'port'};
		    }

		    if(!defined($max_length)){
			$max_length = 0;
		    }

		    if(!defined($out_port)){
			$self->_set_error("Error no out_port specified in output action");
			return;
		    }

		    $tmp[0] = Net::DBus::dbus_uint16(OFPAT_OUTPUT);
		    $tmp[1][0] = Net::DBus::dbus_uint16($max_length);
		    $tmp[1][1] = Net::DBus::dbus_uint16($out_port);
		}

		case "set_vlan_vid" {
		    if(!defined($action->{$key}) || $action->{$key} == -1){
			#untagged
			$tmp[0] = Net::DBus::dbus_uint16(OFPAT_STRIP_VLAN);
			$tmp[1] = Net::DBus::dbus_uint16(0);
		    } else {
			$tmp[0] = Net::DBus::dbus_uint16(OFPAT_SET_VLAN_VID);
			$tmp[1] = Net::DBus::dbus_uint16($action->{$key});
		    }
		}

		case "drop"{
		    #no actions... ie... do nothing
		    
		}else{
		    $self->_set_error("Error unsupported action: " . $key . "\n");
		    return;
		}
	    }
	    
	    if(defined($tmp[0])){
		push(@actions,\@tmp);
	    }
	}
    }

    #push the actions on to the object
    $command->{'action'} = \@actions;

    foreach my $key (keys (%{$self->{'match'}})){
	switch ($key){
	    case "in_port"{
		$command->{'attr'}{'IN_PORT'} = Net::DBus::dbus_uint16($self->{'match'}->{$key});
	    }case "dl_vlan"{
		$command->{'attr'}{'DL_VLAN'} = Net::DBus::dbus_uint16($self->{'match'}->{$key});
	    }case "dl_type"{
		$command->{'attr'}{'DL_TYPE'} = Net::DBus::dbus_uint16($self->{'match'}->{$key});
	    }case "dl_dst"{
		$command->{'attr'}{'DL_DST'} = Net::DBus::dbus_uint64($self->{'match'}->{$key});
	    }else{
		$self->_set_error("Error unsupported match: " . $key . "\n");
		return;
	    }
	}
    }

    if(defined($self->{'priority'})){
	$command->{'attr'}{'PRIORITY'} = Net::DBus::dbus_uint16($self->{'priority'});
    }

    return $command;
}


=head2 get_match

=cut

sub get_match{
    my $self = shift;
    
    return $self->{'match'};

}

sub get_actions{
    my $self = shift;
    
    return $self->{'actions'};
}

=head2 to_human

    Convert the flow rule into something a normal person can understand

=cut

sub to_human{
    my $self = shift;

    
    

}


=head2 to_engineer
    
    Convert the flow_mod into something an engineer would be able to parse

=cut


sub to_engineer{
    my $self = shift;
    
    
    
}


=head2 compare_match

compares this match to another flow_rule match. return 1 for a match and 0 for do not match

=cut
sub compare_match{
    my $self = shift;
    my $other_rule = shift;
    
    return 0 if(!defined($other_rule));

    my $other_match = $other_rule->get_match();
    
    return 0 if(!defined($other_match));

    foreach my $key (keys (%{$self->{'match'}})){
        return 0 if(!defined($other_match->{$key}));
        if($other_match->{$key} != $self->{'match'}->{$key}){
            return 0;
        }
    }

    foreach my $key (keys (%{$other_match})){
        return 0 if(!defined($self->{'match'}->{$key}));
        if($other_match->{$key}!= $self->{'match'}->{$key}){
            return 0;
        }
    }

    #made it this far so has to be the same
    return 1;
}


=head2 merge_actions

merges another flow_mods actions into this one, and if any actions are the same removes them

return 1 if successful
returns 0 on error
=cut

sub merge_actions{
    my $self = shift;
    my $params = @_;

    my $other_flow = $params{'flow_rule'};
    #flow rule not defined can't merge flows
    return 0 if(!defined($other_flow));

    #no actions to merge invalid flow rule
    return 0 if(!defined($other_flow->get_actions()));    

    #now loop through all the actions and add any that don't exist
    foreach my $other_action (@{$other_flow->get_actions()}){
        my $found =0;
        foreach my $action (@{$self->{'actions'}}){
            my $action_type = (keys (%$other_action))->[0];
            if(defined($action->{$action_type})){
                if($action->{$action_type} == $other_action->{$action_type}){
                    $found = 1;
                }
            }
        }
        if(!$found){
            push(@{$self->{'actions'}},$other_action);
        }
    }


    return 1;

}
