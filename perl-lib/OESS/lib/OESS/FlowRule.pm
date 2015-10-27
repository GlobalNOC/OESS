package OESS::FlowRule;

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
use Data::Dumper;
use Switch;
use Net::DBus;
use Log::Log4perl;
use List::Compare;
use Storable qw(dclone);

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

use constant VLAN_WILDCARD      => 0;
use constant PORT_WILDCARD      => 0;

use constant UNTAGGED           => -1;
use constant OF_UNTAGGED        => 65535;

=head2 new

=cut

sub new {
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

    $self->{'logger'} = Log::Log4perl->get_logger("OESS.FlowRule");

    if(!$self->_validate_flow()){
	return undef;
    }
    return $self;
    
}


=head2 validate_flow

validates that the flow_rule is valid

=cut

sub _validate_flow {
    my $self = shift;
    if($self->_validate_match($self->{'match'}) && $self->_validate_actions($self->{'actions'}) && $self->_validate_priority($self->{'priority'}) && $self->_validate_dpid($self->{'dpid'}) && $self->_validate_byte_count($self->{'byte_count'}) && $self->_validate_packet_count($self->{'packet_count'})){
    return 1;
    }else{
	return 0;
    }
    

}

=head2 _validate_match

=cut

sub _validate_match{
    my $self = shift;
    my $match = shift;
    
    foreach my $key (keys (%{$match})){
        $self->{'logger'}->trace("Processing Match Key: " . $key . " value: " . $match->{$key});
        switch ($key){
            case "in_port"{
		if(!$self->_validate_port($match->{$key})){
		    $self->{'logger'}->error("IN PORT: " . $match->{$key} . " is not supported");
            return 0;
		}
            }case "dl_vlan"{
		if(!$self->_validate_vlan_id($match->{$key})){
		    $self->{'logger'}->error("VLAN Tag " . $match->{$key} . " is not supported");
            return 0;
		}
		#lets do a quick fix here... 65535 = -1
		if($match->{$key} == 65535){
		    $match->{$key} = -1;
		}
            }case "dl_type"{
		
            }case "dl_dst"{

	    }case "dl_vlan_pcp"{
		#not supported
		return 0;
	    }case "nw_proto"{
		#not supported
		return 0;
	    }case "tp_src"{
		#not supported
		return;
	    }case "nw_tos"{
		#not supported
		return 0;
	    }case "tp_dst"{
		#not supported
		return 0;
            }else{
                $self->{'logger'}->error("Unsupported match attribute: " . $key . "\n");
                return 0;
            }
        }
    }

    return 1;
}


=head2 _validate_actions

=cut

sub _validate_actions {
    my $self = shift;
    my $actions = shift;

    foreach my $action (@$actions) {
        foreach my $key (keys %$action) {
            my $value = $action->{$key};
            # standardized the (set_vlan_vid/set_vlan_id) action
            if($key eq 'set_vlan_vid'){
                delete $action->{$key};
                $action->{'set_vlan_id'} = $value;
            }
        }
    }
    return 1;
}

=head2 _validate_vlan_id

=cut

sub _validate_vlan_id { 
    my $self = shift;
    my $vlan_id = shift;
    if($vlan_id == 65535 || $vlan_id == -1 || $vlan_id == VLAN_WILDCARD || ($vlan_id > 0 && $vlan_id < 4096)){
	return 1;
    }

    $self->{'logger'}->error("VLAN ID must be between 1 and 4095, -1 (65535) and wildcard");
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


    $self->{'logger'}->error("Port IDs must be between 1 and 65535");
}

=head2 _validate_priority

=cut

sub _validate_priority{
    my $self = shift;
    my $priority = shift;

    if($priority > 0 && $priority <= 65535){
	return 1;
    }
    $self->{'logger'}->error("Priority does not follow spec... must be an integer between 1 and 65535");
    return 0;
}

=head2 _validate_dpid

=cut

sub _validate_dpid{
    my $self = shift;
    return 1;
}

=head2 _validate_byte_count

=cut

sub _validate_byte_count{
    my $self = shift;
    return 1;
}

=head2 _validate_packet_count

=cut

sub _validate_packet_count{
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

=head2 set_actions

=cut

sub set_actions{
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

=head2 set_byte_count

=cut

sub set_byte_count {
    my $self = shift;
    my $new_byte_count = shift;

    if($self->_validate_byte_count($new_byte_count)){
	$self->{'byte_count'} = $new_byte_count;
	return 1;
    }else{
	return;
    }
    
}

=head2 set_packet_count

=cut

sub set_packet_count {
    my $self = shift;
    my $new_packet_count = shift;

    if($self->_validate_packet_count($new_packet_count)){
	$self->{'packet_count'} = $new_packet_count;
	return 1;
    }else{
	return;
    }
    
}

=head2 get_byte_count

=cut

sub get_byte_count{
    my $self = shift;
    $self->{'logger'}->debug("Byte Count: " . $self->{'byte_count'});
    return $self->{'byte_count'};
}

=head2 get_packet_count

=cut

sub get_packet_count{
    my $self = shift;
    $self->{'logger'}->debug("Packet Count: " . $self->{'packet_count'});
    return $self->{'packet_count'};
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
	$self->{'logger'}->error("DPID: " . $new_dpid . " is not a valid DPID, please try again");
	return;
    }
    
}

=head2 to_dbus

    convert the flow rule into something we can send over DBus

=cut

sub to_dbus {
    my ($self, %args) = @_;

    $self->{'logger'}->debug("Processing flow to DBus");

    my $command;
    $command->{'dpid'} = Net::DBus::dbus_uint64($self->{'dpid'});
    my @actions;
    $self->{'logger'}->debug("Processing Actions");
    for(my $i=0;$i<= $#{$self->{'actions'}};$i++){
        my @tmp;
        my $action = $self->{'actions'}->[$i];

        foreach my $key (keys (%$action)){
            $self->{'logger'}->trace("Processing action: " . $key . " " . $action->{$key});
            switch (lc($key)){
                case "output" {
                    #look at OF1.0 spec when sending ofp_action_output
                    #it takes a max_length and a port
                    #max length is only used when forwarding to controller
                    #max_length defaults to 0 if not specified
                    my $max_length;
                    my $out_port;

                    if(ref($action->{$key}) ne 'HASH'){
                        $out_port = $action->{$key};
                        $max_length = 65535;
                    }else{
                        $max_length = $action->{$key}->{'max_length'};
                        $out_port = $action->{$key}->{'port'};
                    }

                    if(!defined($max_length)){
                        $max_length = 65535;
                    }

                    if(!defined($out_port)){
                        $self->{'logger'}->error("Error no out_port specified in output action");
                        return;
                    }

                    $tmp[0] = Net::DBus::dbus_uint16(OFPAT_OUTPUT);
                    $tmp[1][0] = Net::DBus::dbus_uint16(int($max_length));
                    $tmp[1][1] = Net::DBus::dbus_uint16(int($out_port));
                }

                case "set_vlan_vid" {
                    if(!defined($action->{$key}) || $action->{$key} == UNTAGGED || $action->{$key} == 65535){
                        #untagged
                        $tmp[0] = Net::DBus::dbus_uint16(OFPAT_STRIP_VLAN);
                        $tmp[1] = Net::DBus::dbus_uint16(0);
                    } else {
                        $tmp[0] = Net::DBus::dbus_uint16(OFPAT_SET_VLAN_VID);
                        $tmp[1] = Net::DBus::dbus_uint16(int($action->{$key}));
                    }
                }case "set_vlan_id"{
                    if(!defined($action->{$key}) || $action->{$key} == UNTAGGED || $action->{$key} == 65535){
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
                $command->{'attr'}{'DL_DST'}  = Net::DBus::dbus_uint64(int($self->{'match'}->{$key}));
            }case "dl_vlan_pcp"{
                #not supported
            }case "nw_proto"{
                #not supported
            }case "tp_src"{
                #not supported
            }case "nw_tos"{
                #not supported
            }case "tp_dst"{
                #not supported
            }else{
                $self->{'logger'}->error("To Dbus: Unsupported match attribute: " . $key . "\n");
                return;
            }
        }
    }
    
    #these are all set by default
    $command->{'attr'}{'PRIORITY'}     = Net::DBus::dbus_uint16(int($self->{'priority'}));
    $command->{'attr'}{'HARD_TIMEOUT'} = Net::DBus::dbus_uint16(int($self->{'hard_timeout'}));
    $command->{'attr'}{'IDLE_TIMEOUT'} = Net::DBus::dbus_uint16(int($self->{'idle_timeout'}));

    #set the command if it was defined
    if(defined($args{'command'})){
        $command->{'attr'}{'COMMAND'} = Net::DBus::dbus_uint16(int($args{'command'}));
        $self->{'logger'}->debug("flow converted to dbus with OFPFC of :". $command->{'attr'}{'COMMAND'});
    } else {
        $self->{'logger'}->error("no command sent with to_dbus command!");
    }

    $self->{'logger'}->debug("returning the flow in dbus format");

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

sub to_human {
    my ( $self, %args ) = @_;
    
    my $node_name;
    if ($args{'db'}) {
        
        my $results = $args{'db'}->get_node_by_dpid(dpid => $self->{'dpid'}); 
        $node_name = $results->{'name'}


    }

    my $match_str = "";
    foreach my $key (keys (%{$self->{'match'}})){
        $self->{'logger'}->trace("Processing Match Key: " . $key . " value: " . $self->{'match'}->{$key});
        if($match_str ne ''){
            $match_str .= ", ";
        }
        switch ($key){
            case "in_port"{

                if ($args{'db'}) {

                    my $results = $args{'db'}->get_interface_by_dpid_and_port(dpid => $self->{'dpid'}, port_number => $self->{'match'}->{$key});
                    
                    my $port_name  = $results->{'name'}; 

                    $match_str .= "IN PORT: " . $self->{'match'}->{$key} . " ($port_name)";
                }
                else {
                    $match_str .= "IN PORT: " . $self->{'match'}->{$key};
                }

            }case "dl_vlan"{
                $match_str .= "VLAN: " . $self->{'match'}->{$key};
            }case "dl_type"{
                $match_str .= "TYPE: " . $self->{'match'}->{$key};
            }case "dl_dst"{
                $match_str .= "DST MAC: " . $self->{'match'}->{$key};
            }case "dl_vlan_pcp"{
                $match_str .= "VLAN PCP: " . $self->{'match'}->{$key};
            }case "nw_proto"{
                $match_str .= "NW PROTO: " . $self->{'match'}->{$key};
            }case "tp_src"{
                $match_str .= "TP SRC: " . $self->{'match'}->{$key};
            }case "nw_tos"{
                $match_str .= "NW TOS: " . $self->{'match'}->{$key};
            }case "tp_dst"{
                $match_str .= "TP DST: " . $self->{'match'}->{$key};
            }else{
                $self->{'logger'}->error("Unsupported match attribute: " . $key . "\n");
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
            switch (lc($key)){
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
                        return;
                    }

                    if ($args{'db'}) { 
                        my $results = $args{'db'}->get_interface_by_dpid_and_port(dpid => $self->{'dpid'}, port_number => $out_port);
                        my $port_name = $results->{'name'}; 
                        $action_str .= "OUTPUT: " . $out_port . " ($port_name) \n";
                    }
                    else {
                        $action_str .= "OUTPUT: " . $out_port . "\n";
                    }

                }

                case "set_vlan_vid" {
                    if(!defined($action->{$key}) || $action->{$key} == UNTAGGED){
                        #untagged
                        $action_str .= "STRIP VLAN VID\n";
                    } else {
                        $action_str .= "SET VLAN ID: " . $action->{$key} . "\n";
                    }
                }
                case "set_vlan_id" {
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
                    $self->{'logger'}->error("Error unsupported action: " . $key . "\n");
                    return;
                }
            }
            
        }
    }
    
    my $dpid_str    = sprintf("%x",$self->{'dpid'});
    my $str = "OFFlowMod:\n".
              " DPID: " . $dpid_str . " ($node_name)\n".
              " Priority: " . $self->{'priority'} . "\n".
              " Match: " . $match_str . "\n".
              " Actions: " . $action_str;

    return $str;
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

    $self->{'logger'}->debug("compare match");

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
	my $obj = $self->{'actions'}->[$i];
        my $obj2 = $other_actions->[$i];

        #what if there are multiple keys (there shouldn't be)
        my $key = (keys %{$obj})[0];
        if($obj->{$key} ne $obj2->{$key}){
            return 0;
        }
            
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

Determines if another flow's actions can be merged into this one. And merges them if so.
If the other flow's complete action set is already in our's, do nothing.

return 1 if successful
returns 0 on error

=cut

sub merge_actions {
    my ( $self, %args ) = @_;
    my $other_flow      = $args{'flow_rule'};

    # get the uniquye list of 'set actions' from our action list and the action list
    # of the flow we're merging
    my @set_action_types       = $self->_get_set_action_types( $self->get_actions() );
    my @other_set_action_types = $self->_get_set_action_types( $other_flow->get_actions() );

    # figure out which 'set actions' one list has that the other doesn't
    my $lc = List::Compare->new( \@set_action_types, \@other_set_action_types );
    my @actions_only_in_ours  = $lc->get_unique();
    my @actions_only_in_other = $lc->get_complement(); 

    # if each flow has a 'set action' that other does not have
    # they can not be merged as the original intent of one of one
    # actions will be changed
    if( @actions_only_in_ours > 0 && @actions_only_in_other > 0 ){
        $self->{'logger'}->error("Actions can not be merged due to incompatible 'set actions'");
        return 0;
    }
    # if our flow has 'set actions' that are not in the other's list
    # unshift the other flow's actions onto the front of our action list
    elsif( @actions_only_in_ours > 0 ){
        foreach my $action (@$other_flow->get_actions()){
            unshift(@{$self->{'actions'}}, $action);
        }
        return 1;
    }
    # if the other flow has 'set actions' that are not in our
    # actions list, push the other flow's actions on the end of our list
    elsif( @actions_only_in_other > 0 ){
        foreach my $action (@$other_flow->get_actions()){
            push(@{$self->{'actions'}}, $action);
        }
        return 1;
    }
    # if the set actions are equal check the action lists for equality
    elsif( @actions_only_in_ours == @actions_only_in_other ){
        # don't merge, we already do what this flows' actions are doing
        return 1 if( $self->compare_actions( flow_rule => $other_flow ) );

        # check if we already perform the same actions, in the same order,
        # without any 'set actions' in between
        my $other_actions      = dclone($other_flow->get_actions());
        my $other_action       = shift(@$other_actions);
        my $different_outcome  = 0;
        my $found_action_count = 0;
        my $other_action_type  = (keys(%$other_action))[0];
        foreach my $action (@{$self->get_actions()}){
            my $action_type = (keys(%$action))[0];
            
            # if actions are the same increment found action cound and continue
            if( $other_action_type eq $action_type &&
                $action->{$action_type} eq $other_action->{$other_action_type} ){
                $found_action_count += 1;
                # if we've found all our actions we are done
                last if( $found_action_count == @{$other_flow->get_actions()} );
                # shift the next action off the list of actions we're looking for
                $other_action      = shift(@$other_actions);
                $other_action_type = (keys(%$other_action))[0];
                # continue looking for other_flow's actions
                next;
            }
            # if we hit a set action before we found all of the other flow's actions the outcome will
            # not be the same, 
            if( $found_action_count && $self->_is_set_action($action_type) ){
                $different_outcome = 1;
                last;
            }
        } 
        return 1 if( !$different_outcome && ($found_action_count == @{$other_flow->get_actions()}));

        # other wise just push it on the end of our actions
        # since the set actions are the same both actions set
        # will be able to keep their original intent
        foreach my $action (@{$other_flow->get_actions()}){
            push(@{$self->{'actions'}}, $action);
        }
        return 1;
    }

    # shouldn't be possible to hit this 
    $self->{'logger'}->error("Actions could not be merged for unknown reason");
    return 0;
}

=head2 _get_set_action_types

Returns a list of the unique 'set action' types, i.e. any action that 
modifies the packet

=cut

sub _get_set_action_types {
    my ($self, $actions) = @_;

    my %set_action_types;
    foreach my $action (@$actions){
        my $action_type = (keys(%$action))[0]; 
        # currently only do set_vlan_vid
        next if( $action_type ne 'set_vlan_id' );
        $set_action_types{$action_type} = 1;
    }

    return keys(%set_action_types);
}

sub _is_set_action {
    my ($self, $action_type) = @_;
        
    return 1 if( $action_type eq 'set_vlan_id' );

    return 0;

}


=head2 to_canonical

=cut

sub to_canonical{
    my $self = shift;
    
    my %obj;
    $obj{'match'} = $self->{'match'};
    $obj{'actions'} = $self->{'actions'};
    $obj{'dpid'} = $self->{'dpid'};
    $obj{'priority'} = $self->{'priority'};
    return \%obj;
}

=head2 parse_stat

=cut

sub parse_stat{
    my %params = @_;

    my $logger = Log::Log4perl->get_logger("OESS.FlowRule");
    $logger->debug("Processing Stat to Flow Rule");
    my $dpid = $params{'dpid'};
    my $stat = $params{'stat'};
    return if(!defined($stat));
    return if(!defined($dpid));

    my $match = $stat->{'match'};
    
    my $actions = $stat->{'actions'};
    my $priority = $stat->{'priority'};
    $logger->trace("Byte Count: " . $stat->{'byte_count'});
    my $byte_count = $stat->{'byte_count'};
    
    $logger->trace("Packet Count: " . $stat->{'packet_count'});
    my $packet_count = $stat->{'packet_count'};

    my @new_actions;

    foreach my $action (@$actions){
	switch ($action->{'type'}){
	    case (OFPAT_OUTPUT){
		push(@new_actions,{'output' => $action->{'port'}});
	    }case (OFPAT_SET_VLAN_VID){
		push(@new_actions,{'set_vlan_id' => $action->{'vlan_vid'}});
	    }case (OFPAT_STRIP_VLAN){
		push(@new_actions,{'set_vlan_id' => UNTAGGED});
	    }
	}
    }
    my $new_match = {};
    foreach my $key (keys (%{$match})){
	$logger->debug("Key: " . $key . " = " . $match->{$key});
	switch($key){
	    case "dl_vlan"{
                if($match->{$key} == 0){
                    #this is really untagged
                    $new_match->{$key} = -1;
                }else{
                    $new_match->{$key} = $match->{$key};
                }
	    }case "in_port"{
		$new_match->{$key} = $match->{$key};
	    }case "dl_dst"{
		$new_match->{$key} = $match->{$key};
	    }case "dl_type"{
		$new_match->{$key} = $match->{$key};
	    }
	}
    }
    my $flow = OESS::FlowRule->new( 
        priority => $priority,
        match => $new_match,
        dpid => $dpid,
        actions => \@new_actions,
        byte_count => $byte_count,
        packet_count => $packet_count
        );
    
    return $flow;
    

}

=head2 get_flowrules

Takes an arrary ref of OESS::FlowRules and returns an array ref of OESS::FlowRules that match the options passed in.

Options
match (hash ref)
dpid  (scalar)

=cut

sub get_flowrules {
    my %params = @_;
    my $flowrules = $params{'flowrules'};
    # filter options
    my $match     = $params{'match'};
    my $dpid      = $params{'dpid'};

    my $result = [];
    foreach my $flowrule (@$flowrules){
        next if(defined($match) && !eq_deeply($match, $flowrule->get_match()));
        next if(defined($dpid)  && !($dpid == $flowrule->get_dpid()));
        push(@$result, $flowrule);
    }

    return $result;
}

1;
