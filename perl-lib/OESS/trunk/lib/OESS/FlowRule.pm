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
use Log::Log4perl;

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

use constant UNTAGGED           => -1;

=head2 new

=cut

sub new{
    my $that = shift;
    my $class = ref($that) || $that;

    my %args = (
	priority => 32768,
	match => {},
	actions => [],
	dpid => undef,
	idle_timeout => 0,
	hard_timeout => 0,
	@_
	);

    my $self = \%args;
    bless $self, $class;

    $self->{'logger'} = Log::Log4perl->get_logger("OESS::FlowRule");

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

=head2 get_priority

=cut

sub get_priority{
    my $self = shift;
    $self->{'logger'}->debug("Priority: " . $self->{'priority'});
    return $self->{'priority'};
}

=head2 get_dpid

=cut

sub get_dpid{
    my $self = shift;
    return $self->{'dpid'};
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

    $self->{'logger'}->debug("Processing flow to DBus");

    my $command;
    $command->{'dpid'} = Net::DBus::dbus_uint64($self->{'dpid'});
    my @actions;
    $self->{'logger'}->debug("Processing Actions");
    for(my $i=0;$i<= $#{$self->{'actions'}};$i++){
	my @tmp;
	my $action = $self->{'actions'}->[$i];
        $self->{'logger'}->trace("Processing Action: " . Data::Dumper::Dumper($action));

	foreach my $key (keys (%$action)){
            $self->{'logger'}->trace("Processing action: " . $key . " " . $action->{$key});
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
                        $self->{'logger'}->error("Error no out_port specified in output action");
			$self->_set_error("Error no out_port specified in output action");
			return;
		    }

		    $tmp[0] = Net::DBus::dbus_uint16(OFPAT_OUTPUT);
		    $tmp[1][0] = Net::DBus::dbus_uint16(int($max_length));
		    $tmp[1][1] = Net::DBus::dbus_uint16(int($out_port));
		}

		case "set_vlan_vid" {
		    if(!defined($action->{$key}) || $action->{$key} == UNTAGGED){
			#untagged
			$tmp[0] = Net::DBus::dbus_uint16(OFPAT_STRIP_VLAN);
			$tmp[1] = Net::DBus::dbus_uint16(0);
		    } else {
			$tmp[0] = Net::DBus::dbus_uint16(OFPAT_SET_VLAN_VID);
			$tmp[1] = Net::DBus::dbus_uint16(int($action->{$key}));
		    }
		}

		case "drop"{
		    #no actions... ie... do nothing
		    
		}else{
                    $self->{'logger'}->error("Error unsupported action: " . $key . "\n");
		    $self->_set_error("Error unsupported action: " . $key . "\n");
		    return;
		}
	    }
	    
	    if(defined($tmp[0])){
                $self->{'logger'}->trace("Adding: " . Data::Dumper::Dumper(@tmp)  . " to actions array ");
		push(@actions,\@tmp);
	    }
	}
    }

    #push the actions on to the object
    $command->{'action'} = \@actions;
    
    $self->{'logger'}->debug("Processing Match");
    foreach my $key (keys (%{$self->{'match'}})){
        $self->{'logger'}->trace("Processing Match Key: " . $key . " value: " . $self->{'match'}->{$key});
	switch ($key){
	    case "in_port"{
		$command->{'attr'}{'IN_PORT'} = Net::DBus::dbus_uint16(int($self->{'match'}->{$key}));
	    }case "dl_vlan"{
		$command->{'attr'}{'DL_VLAN'} = Net::DBus::dbus_uint16(int($self->{'match'}->{$key}));
	    }case "dl_type"{
		$command->{'attr'}{'DL_TYPE'} = Net::DBus::dbus_uint16(int($self->{'match'}->{$key}));
	    }case "dl_dst"{
		$command->{'attr'}{'DL_DST'} = Net::DBus::dbus_uint64(int($self->{'match'}->{$key}));
	    }else{
                $self->{'logger'}->error("Unsupported match attribute: " . $key . "\n");
		$self->_set_error("Error unsupported match: " . $key . "\n");
		return;
	    }
	}
    }
    
    #these are all set by default
    $command->{'attr'}{'PRIORITY'} = Net::DBus::dbus_uint16(int($self->{'priority'}));
    $command->{'attr'}{'HARD_TIMEOUT'} = Net::DBus::dbus_uint16(int($self->{'hard_timeout'}));
    $command->{'attr'}{'IDLE_TIMEOUT'} = Net::DBus::dbus_uint16(int($self->{'idle_timeout'}));

    $self->{'logger'}->debug("returning the flow in dbus format");
    $self->{'logger'}->trace("DBUS Data: " . Data::Dumper::Dumper($command));

    return (Net::DBus::dbus_uint64($self->{'dpid'}),$command->{'attr'},$command->{'action'});
}


=head2 get_match

=cut

sub get_match{
    my $self = shift;
    
    return $self->{'match'};

}

=head2 get_actions

=cut

sub get_actions{
    my $self = shift;
    
    return $self->{'actions'};
}

=head2 to_human

    Convert the flow rule into something a normal person can understand

=cut

sub to_human{
    my $self = shift;

    my $match_str = "";
    foreach my $key (keys (%{$self->{'match'}})){
        $self->{'logger'}->trace("Processing Match Key: " . $key . " value: " . $self->{'match'}->{$key});
	if($match_str ne ''){	    
	    $match_str .= ", ";
	}
        switch ($key){
            case "in_port"{
                $match_str .= "IN PORT: " . $self->{'match'}->{$key};
            }case "dl_vlan"{
                $match_str .= "VLAN: " . $self->{'match'}->{$key};
            }case "dl_type"{
		$match_str .= "TYPE: " . $self->{'match'}->{$key};
            }case "dl_dst"{
		$match_str .= "DST MAC: " . $self->{'match'}->{$key};
            }else{
                $self->{'logger'}->error("Unsupported match attribute: " . $key . "\n");
                $self->_set_error("Error unsupported match: " . $key . "\n");
                return;
            }
        }
    }

    my $action_str = "";

    for(my $i=0;$i<= $#{$self->{'actions'}};$i++){
        my @tmp;
        my $action = $self->{'actions'}->[$i];
	foreach my $key (keys (%$action)){
            if($action_str ne ''){
		$action_str .= '          ';
	    }
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

		    $action_str .= "OUTPUT: " . $out_port . "\n";
                }

                case "set_vlan_vid" {
                    if(!defined($action->{$key}) || $action->{$key} == UNTAGGED){
                        #untagged
			$action_str .= "STRIP VLAN VID\n";
                    } else {
			$action_str .= "SET VLAN ID: " . $action->{$key} . "\n";
                    }
                }

                case "drop"{
                    #no actions... ie... do nothing
                    
                }else{
                    $self->_set_error("Error unsupported action: " . $key . "\n");
                    return;
                }
            }
            
	}
    }
    
    my $dpid_str = sprintf("%x",$self->{'dpid'});
    return "OFFlowMod:\n DPID: " . $dpid_str . "\n Match: " . $match_str . "\n Actions: " . $action_str;

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
    my %params = @_;

    my $other_rule = $params{'flow_rule'};
    
    return 0 if(!defined($other_rule));

    my $other_match = $other_rule->get_match();
    
    return 0 if(!defined($other_match));

    foreach my $key (keys (%{$self->{'match'}})){
        return 0 if(!defined($other_match->{$key}));
        if($other_match->{$key} != $self->{'match'}->{$key}){
            $self->{'logger'}->debug("matches do not match: $key: " . $self->{'match'}->{$key} . " ne " . $other_match->{$key});
            return 0;
        }
    }

    foreach my $key (keys (%{$other_match})){
        return 0 if(!defined($self->{'match'}->{$key}));
        if($other_match->{$key}!= $self->{'match'}->{$key}){
            $self->{'logger'}->debug("matches do not match: $key: " . $self->{'match'}->{$key} . "ne " . $other_match->{$key});
            return 0;
        }
    }

    #made it this far so has to be the same
    return 1;
}


=head2 compare_actions

=cut

sub compare_actions{
    my $self = shift;
    my %params = @_;

    my $other_rule = $params{'flow_rule'};
    
    return 0 if(!defined($other_rule));
    
    my $other_actions = $other_rule->get_actions();

    return 0 if(!defined($other_actions));
    
    if($#{$self->{'actions'}} != $#{$other_actions}){
	return 0;
    }

    for(my $i=0;$i<=$#{$self->{'actions'}};$i++){
	
    }

    return 1;
}

=head2 compare_flow

=cut

sub compare_flow{
    my $self = shift;
    my %params = @_;
    
    if(!defined($params{'flow_rule'})){
        $self->{'logger'}->error("No Flow rule specified");
        return 0;
    }
    
    if($self->compare_match( flow_rule => $params{'flow_rule'} ) && $self->compare_actions( flow_rule => $params{'flow_rule'})){

        if($self->get_dpid() != $params{'flow_rule'}->get_dpid()){
            $self->{'logger'}->debug("DPIDs do not match");
            return 0;
        }
        
        if($self->get_priority() != $params{'flow_rule'}->get_priority()){
            $self->{'logger'}->debug("Priorities do not match");
            return 0;
        }

        $self->{'logger'}->debug("flows match");
        return 1;
    }

    $self->{'logger'}->debug("flows do not match");
    return 0; 
}

=head2 merge_actions

merges another flow_mods actions into this one, and if any actions are the same removes them

return 1 if successful
returns 0 on error
=cut

sub merge_actions{
    my $self = shift;
    my %params = @_;

    my $other_flow = $params{'flow_rule'};
    #flow rule not defined can't merge flows
    return 0 if(!defined($other_flow));

    #no actions to merge invalid flow rule
    return 0 if(!defined($other_flow->get_actions()));    

    $self->{'logger'}->debug("Attempting to merge flow actions");

    #now loop through all the actions and add any that don't exist
    foreach my $other_action (@{$other_flow->get_actions()}){
	$self->{'logger'}->trace("Actions: " . Data::Dumper::Dumper($self->{'actions'}));
        my $found =0;
        foreach my $action (@{$self->{'actions'}}){
	    $self->{'logger'}->trace("processing action: " . Data::Dumper::Dumper($action));
	    $self->{'logger'}->trace("comparing to action: " . Data::Dumper::Dumper($other_action));
            my $action_type = (keys (%$other_action))[0];
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


=head2 parse_stat

=cut

sub parse_stat{
    my $self = shift;
    my %params = @_;

    my $dpid = $params{'dpid'};
    my $stat = $params{'stat'};

    return if(!defined($stat));

    my $match = $stat->{'match'};
    my $actions = $stat->{'actions'};

    my @new_actions;

    foreach my $action (@$actions){
	switch ($action->[0]){
	    case (OFPAT_OUTPUT){
		push(@new_actions,{'output' => $action->[0]->[0]});
	    }case (OFPAT_SET_VLAN_VID){
		push(@new_actions,{'set_vlan_id' => $action->[1]});
	    }case (OFPAT_STRIP_VLAN){
		push(@new_actions,{'set_vlan_id' => UNTAGGED});
	    }
	}
    }

    my $flow = OESS::FlowRule->new( match => $match,
				    dpid => $dpid,
				    actions => @new_actions);

    return $flow;
    

}
