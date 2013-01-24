#!/usr/bin/perl
#------ NDDI OESS Forwarding Control 
##-----
##----- $HeadURL:
##----- $Id:
##-----
##----- Listens to all events sent on org.nddi.openflow.events 
##---------------------------------------------------------------------
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
use strict;
use warnings;

###############################################################################
package FwdCtl;
use strict;
use Data::Dumper;
use Net::DBus::Exporter qw(org.nddi.fwdctl);
use Net::DBus qw(:typing);
use base qw(Net::DBus::Object);
use Sys::Syslog qw(:macros :standard);
use Switch;
use OESS::Database;
use OESS::Topology;

use constant FWDCTL_ADD_VLAN     => 0;
use constant FWDCTL_REMOVE_VLAN  => 1;
use constant FWDCTL_CHANGE_PATH  => 2;

use constant FWDCTL_ADD_RULE     => 0;
use constant FWDCTL_REMOVE_RULE  => 1;

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

#port_status reasons
use constant OFPPR_ADD => 0;
use constant OFPPR_DELETE => 1;
use constant OFPPR_MODIFY => 2;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;

$| = 1;

sub _log {
    my $string = shift;

    my $pid = getppid();

    if($pid == 1){
	syslog(LOG_WARNING,$string);
    }else{
	warn $string;
    }    
}

sub new {

    
    my $class = shift;
    my $service = shift;
    my $self = $class->SUPER::new($service, '/controller1');
    bless $self, $class;

    $self->{'of_controller'} = shift;

    my $db = new OESS::Database();

    if (! $db){
	_log("Could not make database object");
	exit(1);
    }
    my @tmp;
    $self->{'nodes_for_diff'} = \@tmp;
    $self->{'db'} = $db;

    dbus_method("addVlan", ["uint32"], ["string"]);
    dbus_method("deleteVlan", ["string"], ["string"]);
    dbus_method("changeVlanPath", ["string"], ["string"]);
    dbus_method("topo_port_status",["uint64","uint32",["dict","string","string"]],["string"]);

    return $self;
}

sub _sync_database_to_network {
    my $self = shift;

    my $nodes = $self->{'db'}->get_current_nodes();
    foreach my $node(@$nodes){
	$node->{'full_diff'} = 1;
	push(@{$self->{'nodes_for_diff'}},$node);
    }
}

sub _generate_forward_rule{
    my $self	   = shift;
    my $prev_rules = shift;
    my $dpid	   = shift;
    my $tag	   = shift;
    my $in_port	   = shift;
    my $out_port   = shift;
    my $sw_act     = shift;

    _log("-- creating forwarding rule from dpid = $dpid inport = $in_port to outport = $out_port with tag $tag --");

    # check to see if we already have a rule with the same qualifiers. If so, add rules to that qualifier.
    foreach my $prev_rule (@$prev_rules){

     	my $prev_attrs = $prev_rule->{'attr'};
	
	if ($prev_attrs->{'DL_VLAN'}->value()    eq $tag 
	    && $prev_attrs->{'IN_PORT'}->value() eq $in_port 
	    && $prev_rule->{'dpid'}->value()     eq $dpid
	    && $prev_rule->{'sw_act'}            eq $sw_act){
	    
	    my $actions = $prev_rule->{'action'};
	    
    	    my @new_action;
	    
    	    $new_action[0]    = dbus_uint16(OFPAT_OUTPUT);
    	    $new_action[1][0] = dbus_uint16(0);
    	    $new_action[1][1] = dbus_uint16($out_port);
	    
    	    push(@$actions, \@new_action);    	    
	    
    	    return;
    	}
	
    }

    my %rule;
    $rule{'sw_act'}	      = $sw_act;
    $rule{'dpid'}             = dbus_uint64($dpid);
    $rule{'attr'}{'DL_VLAN'}  = dbus_uint16($tag);
    $rule{'attr'}{'IN_PORT'}  = dbus_uint1o6($in_port);

    my @action;
    $action[0][0]             = dbus_uint16(OFPAT_OUTPUT);
    $action[0][1][0]          = dbus_uint16(0);
    $action[0][1][1]          = dbus_uint16($out_port);

    $rule{'action'}           = \@action;

    push(@$prev_rules, \%rule);
}

sub _generate_translation_rule{
    my $self       = shift;
    my $prev_rules = shift;
    my $dpid       = shift;
    my $in_tag     = shift;
    my $in_port    = shift;
    my $out_tag    = shift;
    my $out_port   = shift;
    my $sw_act     = shift;

    _log("-- creating translation rule based on tag $in_tag coming in on port $in_port, translating to tag $out_tag out port $out_port on node $dpid --");

    # first let's see if we already have a rule that uses these exact same qualifiers (multipoint)
    foreach my $prev_rule (@$prev_rules){
	
    	my $prev_attrs = $prev_rule->{'attr'};
	
    	# same vlan, same port, and same host == same qualifier, time to add to the actions
    	if ($prev_attrs->{'DL_VLAN'}->value()    eq $in_tag 
	    && $prev_attrs->{'IN_PORT'}->value() eq $in_port 
	    && $prev_rule->{'dpid'}->value()     eq $dpid
	    && $prev_rule->{'sw_act'}            eq $sw_act){
    
    	    my $actions = $prev_rule->{'action'};

            # if we have already seen this exact rule (intranode path likely), skip
            if ((
		($actions->[0][0]->value() == OFPAT_SET_VLAN_VID && $actions->[0][1]->value() == $out_tag)
		||
		($actions->[0][0]->value() == OFPAT_STRIP_VLAN && $actions->[0][1]->value() == 0)) &&
		$actions->[1][0]->value()    == OFPAT_OUTPUT &&
                $actions->[1][1][1]->value() == $out_port){
                return;
            }

    	    my @new_first_action;

	    $new_first_action[0] = dbus_uint16(OFPAT_SET_VLAN_VID);
	    $new_first_action[1] = dbus_uint16($out_tag);

	    push (@$actions, \@new_first_action);

	    my @new_second_action;

    	    $new_second_action[0]    = dbus_uint16(OFPAT_OUTPUT);
    	    $new_second_action[1][0] = dbus_uint16(0);
    	    $new_second_action[1][1] = dbus_uint16($out_port);

    	    push(@$actions, \@new_second_action);

    	    return;
    	}
    }

    # didn't find a previous rule like this, time to make a new one
    my %rule;    

    $rule{'sw_act'} 	       = $sw_act;
    $rule{'dpid'}              = dbus_uint64($dpid);
    $rule{'attr'}{'DL_VLAN'}   = dbus_uint16($in_tag);
    $rule{'attr'}{'IN_PORT'}   = dbus_uint16($in_port);
        
    my @action;

    # untagged traffic
    if ($out_tag eq -1){
	$action[0][0]     = dbus_uint16(OFPAT_STRIP_VLAN);

	# this is a hack to make dbus happy by keeping the signature the same.
	# it does nothing and gets peeled off in nddi_dbus
	$action[0][1]     = dbus_uint16(0);
    }
    #tagged traffic
    else{   
	$action[0][0]     = dbus_uint16(OFPAT_SET_VLAN_VID);
	$action[0][1]     = dbus_uint16($out_tag);
    }

    $action[1][0]         = dbus_uint16(OFPAT_OUTPUT);
    $action[1][1][0]      = dbus_uint16(0);
    $action[1][1][1]      = dbus_uint16($out_port);

    $rule{'action'}       = \@action;

    push(@$prev_rules, \%rule);

}

sub _generate_endpoint_rules{
  #--- maybe we should refactor into this?

}

sub _generate_commands{
    my $self             = shift;
    my $circuit_id       = shift;
    my $action           = shift;

     my $circuit_details = $self->{'db'}->get_circuit_details(circuit_id => $circuit_id);
    print STDERR "Generate Commands - Circuit Details: " . Dumper($circuit_details);
    if (!defined $circuit_details){
	_log("No Such Circuit");
        #--- no such ckt error
        #--- !!! need to set error !!!
        return undef;
    }
    my $dpid_lookup  = $self->{'db'}->get_node_dpid_hash();
    if(!defined $dpid_lookup){
	_log("No Such DPID");
	#--- some sorta of internal error
	#--- !!! need to set error !!!
	return undef;
    }
 
    my %primary_path;
    my %backup_path;
    my @commands;

    my $internal_ids = $circuit_details->{'internal_ids'};

    foreach my $link (@{$circuit_details->{'links'}}){
	my $node_a = $link->{'node_a'};
	my $node_z = $link->{'node_z'};
	$primary_path{$node_a}{$link->{'port_no_a'}}{$internal_ids->{'primary'}{$node_a}} = $internal_ids->{'primary'}{$node_z};
	$primary_path{$node_z}{$link->{'port_no_z'}}{$internal_ids->{'primary'}{$node_z}} = $internal_ids->{'primary'}{$node_a};
    }
    foreach my $link (@{$circuit_details->{'backup_links'}}){
	my $node_a = $link->{'node_a'};
	my $node_z = $link->{'node_z'};
	$backup_path{$node_a}{$link->{'port_no_a'}}{$internal_ids->{'backup'}{$node_a}} = $internal_ids->{'backup'}{$node_z};
	$backup_path{$node_z}{$link->{'port_no_z'}}{$internal_ids->{'backup'}{$node_z}} = $internal_ids->{'backup'}{$node_a};
    }

   if($action == FWDCTL_ADD_VLAN || $action == FWDCTL_REMOVE_VLAN){
     my $sw_act = FWDCTL_ADD_RULE;

     if($action == FWDCTL_REMOVE_VLAN){
        $sw_act = FWDCTL_REMOVE_RULE;
     }

     # if we're in backup mode, we need to provision the reverse status
     if ($circuit_details->{'active_path'} eq 'backup'){
	 my %tmp       = %primary_path;
	 %primary_path = %backup_path;
	 %backup_path  = %tmp;
     }

     
     #--- gen set of rules to apply to each node on either primary or backup path
     #--- get the set of links on the primary and backup, then get the interfaces for each
     #---    node     
     foreach my $path ((\%primary_path, \%backup_path)){

	 #--- get node by node and figure out the simple forwarding rules for this path
	 foreach my $node (sort keys %$path){
	     foreach my $interface (sort keys %{$path->{$node}}){
		 foreach my $other_if(sort keys %{$path->{$node}}){
		     
		     #--- skip when the 2 interfaces are the same
		     next if($other_if eq $interface);
		     
		     #--- iterate through ports need set of rules for each input/output port combo
		     foreach my $vlan_tag (sort keys %{$path->{$node}{$interface}}){          
			 
			 my $remote_tag = $path->{$node}{$other_if}{$vlan_tag};

			 # future optimization if remote_tag and vlan_tag are the same?
			 #$self->_generate_forward_rule(\@commands,$dpid_lookup->{$node},$vlan_tag,$interface,$other_if,$sw_act);
			 $self->_generate_translation_rule(\@commands,$dpid_lookup->{$node}, $vlan_tag, $interface, $remote_tag, $other_if, $sw_act);		     
		     }
		 }
	     }
	 } 
     }
    #--- gen set of rules to apply at each endpoint these are for forwarding and translation
    foreach my $endpoint(@{$circuit_details->{'endpoints'}}){

      my $node      = $endpoint->{'node'};
      my $interface = $endpoint->{'port_no'};
      my $outer_tag = $endpoint->{'tag'};

      #--- iterate over the non-edge interfaces on the primary path to setup rules that both forward AND translate
      foreach my $other_if(sort keys %{$primary_path{$node}}){
	  foreach my $local_inner_tag (sort keys %{$primary_path{$node}{$other_if}}){

	      my $remote_inner_tag = $primary_path{$node}{$other_if}{$local_inner_tag};

	      $self->_generate_translation_rule(\@commands,$dpid_lookup->{$node},$outer_tag, $interface, $remote_inner_tag, $other_if,$sw_act);
	      $self->_generate_translation_rule(\@commands,$dpid_lookup->{$node},$local_inner_tag, $other_if, $outer_tag, $interface,$sw_act);
        }
      }

      #--- iterate over the endpoints again to catch more than 1 ep on same switch
      #--- this will be sorta odd as these will always exist regardless backup or primary
      #--- path if exist
      foreach my $other_ep(@{$circuit_details->{'endpoints'}}){
	  my $other_node =  $other_ep->{'node'};
	  my $other_if   =  $other_ep->{'port_no'};
	  my $other_tag  =  $other_ep->{'tag'};
	  
	  next if($other_ep == $endpoint || $node ne $other_node );
	  
	  $self->_generate_translation_rule(\@commands,$dpid_lookup->{$node},$outer_tag, $interface, $other_tag, $other_if,$sw_act);
	  $self->_generate_translation_rule(\@commands,$dpid_lookup->{$node},$other_tag, $other_if, $outer_tag, $interface,$sw_act);
      }
    }
     
     
     #--- if this was a remove call, then we would basically change the base action of the command 
     return \@commands;
    
   }elsif($action == FWDCTL_CHANGE_PATH){
     #--- if primary path , change to backup.  If backup switch to primary
     #--- switching involves changing endpoint rules
     my $path = \%primary_path;
     my $old  = \%backup_path;

     if($circuit_details->{'active_path'} eq 'backup'){
	$path = \%backup_path;
	$old  = \%primary_path;
     }

     foreach my $endpoint(@{$circuit_details->{'endpoints'}}){
        my $node      = $endpoint->{'node'};
        my $interface = $endpoint->{'port_no'};
        my $outer_tag = $endpoint->{'tag'};

        #--- add new edge rules
	foreach my $other_if(sort keys %{$path->{$node}}){
	    foreach my $local_inner_tag (sort keys %{$path->{$node}{$other_if}}){
		my $remote_inner_tag = $path->{$node}{$other_if}{$local_inner_tag};
		
		$self->_generate_translation_rule(\@commands,$dpid_lookup->{$node},$outer_tag, $interface, $remote_inner_tag, $other_if,FWDCTL_ADD_RULE);
		$self->_generate_translation_rule(\@commands,$dpid_lookup->{$node},$local_inner_tag, $other_if, $outer_tag, $interface,FWDCTL_ADD_RULE);
	    }
	}

        #--- remove existing edge rules
	foreach my $other_if(sort keys %{$old->{$node}}){
	    foreach my $local_inner_tag (sort keys %{$old->{$node}{$other_if}}){
		my $remote_inner_tag = $old->{$node}{$other_if}{$local_inner_tag};
		
		$self->_generate_translation_rule(\@commands,$dpid_lookup->{$node},$outer_tag, $interface, $remote_inner_tag, $other_if,FWDCTL_REMOVE_RULE);
		$self->_generate_translation_rule(\@commands,$dpid_lookup->{$node},$local_inner_tag, $other_if, $outer_tag, $interface,FWDCTL_REMOVE_RULE);
	    }
	}

     }
     
     return \@commands; 
   }
}

sub _push_default_rules{
    my $self = shift;
    
    my $nodes = $self->{'db'}->get_node_dpid_hash();

    foreach my $node (keys (%{$nodes})){
	my $node_details = $self->{'db'}->get_node_by_dpid( dpid => $nodes->{$node});

	if($node_details->{'default_forward'} == 1){
	    my $xid     = $self->{'of_controller'}->install_default_forward($nodes->{$node});
	    
	    my $result = $self->_poll_xids([$xid]);
	    
	    if ($result != FWDCTL_SUCCESS){
		_log("Warning: unable to install default forward to controller rule in switch " . $nodes->{$node} . ", discovery likely will not work.");
	    }
	    else {
		_log("Send default forwarding rule to " . $nodes->{$node});
	    }
	}

	if($node_details->{'default_drop'} == 1){
	    my $xid     = $self->{'of_controller'}->install_default_drop($nodes->{$node});
	    
	    my $result = $self->_poll_xids([$xid]);
	    
	    if ($result != FWDCTL_SUCCESS){
		_log("Warning: unable to install default drop to controller rule in switch " . $nodes->{$node} . ", lots of traffic could be headed our way.");
	    }
	    else {
		_log("Send default drop rule to " . $nodes->{$node});
	    }
	}
    }
}

sub datapath_join{
    my $self   = shift;
    my $dpid   = shift;
    my $ports  = shift;

    #--- first push the default "forward to controller" rule to this node. This enables
    #--- discovery to work properly regardless of whether the switch's implementation does it by default
    #--- or not
    my $node = $self->{'db'}->get_node_by_dpid(dpid => $dpid);

    if(!defined($node) || $node->{'default_forward'} == 1){
	my $xid     = $self->{'of_controller'}->install_default_forward($dpid);
	my $result = $self->_poll_xids([$xid]);

	if ($result != FWDCTL_SUCCESS){
	    _log("Warning: unable to install default forward to controller rule in switch $dpid, discovery likely will not work.");
	}    
	else {
	    _log("Send default forwarding rule to $dpid");
	}
	
    }

    if(!defined($node) || $node->{'default_drop'} == 1){
	my $xid     = $self->{'of_controller'}->install_default_drop($dpid);
	
	my $result = $self->_poll_xids([$xid]);
	
	if ($result != FWDCTL_SUCCESS){
	    _log("Warning: unable to install default drop to controller rule in switch $dpid, lots of traffic could be headed our way.");
	}
	else {
	    _log("Send default drop rule to $dpid");
	}
    }

    #set this node for diffing!
    push(@{$self->{'nodes_for_diff'}},{dpid => $dpid, full_diff => 1});


}

sub _replace_flowmod{
    my $self = shift;
    my $dpid = shift;
    my $delete_command = shift;
    my $new_command = shift;
    my $xid;
    _log("replacing flowmods");

    if(!defined($delete_command) && !defined($new_command)){
	return undef;
    }

    my @xids;
    if(defined($delete_command)){
	#delete this flowmod
	$xid = $self->{'of_controller'}->delete_datapath_flow($dpid,$delete_command->{'attr'});
	push(@xids, $xid);
    }
    
    if(defined($new_command)){
	$xid = $self->{'of_controller'}->install_datapath_flow($dpid,$new_command->{'attr'},0,0,$new_command->{'action'},$new_command->{'attr'}->{'IN_PORT'});
	push(@xids, $xid);
	#wait for the delete to take place
    }

    my $result = $self->_poll_xids(\@xids);
    return $result;
}

sub _process_flow_stats_to_command{
    my $port_num = shift;
    my $vlan = shift;
    
    my %tmp;
    $tmp{'attr'}{'DL_VLAN'} = dbus_uint16($vlan);
    $tmp{'attr'}{'IN_PORT'} = dbus_uint16($port_num);
    return \%tmp;
}

sub _do_diff{
    my $self = shift;
    my $node = shift;
    my $current_flows = shift;

    my $dpid = $node->{'dpid'};
    _log("Diffing DPID: $dpid");
    #--- get the set of circuits
    my $current_circuits = $self->{'db'}->get_current_circuits();
    if (! defined $current_circuits){
        _log("!!! cant get the list of current circuits");
        return;
    }
    
    #--- process each ckt                                                                                                                                                                             
    my @all_commands;
    foreach my $circuit (@$current_circuits){
        my $circuit_id   = $circuit->{'circuit_id'};
        my $circuit_name = $circuit->{'name'};
        my $state        = $circuit->{'state'};

        next unless ($state eq "deploying" || $state eq "active");
        #--- get the set of commands needed to create this vlan per design                                                                                                                           
        my $commands = $self->_generate_commands($circuit_id,FWDCTL_ADD_VLAN);
	foreach my $command (@$commands){
	    push(@all_commands,$command);
	}
    }

    $self->_actual_diff( $dpid, $current_flows, \@all_commands);
}

sub _actual_diff{
    my $self = shift;
    my $dpid = shift;
    my $current_flows = shift;
    my $commands = shift;

    my $node = $self->{'db'}->get_node_by_dpid( dpid => $dpid);
    
    foreach my $command (@$commands){
	#--- get the set of commands needed to create this vlan per design
	foreach my $command (@$commands){
	    #ignore rules not for this dpid
	    next if($command->{'dpid'}->value() != $dpid);
	    #ok so we have our list of rules for this node 
	    if(defined($current_flows->{$command->{'attr'}->{'IN_PORT'}->value()})){
		my $port = $current_flows->{$command->{'attr'}->{'IN_PORT'}->value()};
		if(defined($port->{$command->{'attr'}->{'DL_VLAN'}->value()})){
		    my $action_list = $port->{$command->{'attr'}->{'DL_VLAN'}->value()}->{'actions'};
		    $port->{$command->{'attr'}->{'DL_VLAN'}->value()}->{'seen'} = 1;
		    #ok... so our match matches...
		    #does our action match?
		    if($#{$action_list} != $#{$command->{'action'}}){
			_log("Flowmod actions do not match, removing and replacing");
			#replace the busted flowmod with our new flowmod...
			#first delay by some configured value in case the device can't handle it
			usleep($node->{'tx_delay_ms'} * 1000);
			my $result = $self->_replace_flowmod($dpid,_process_flow_stats_to_command($command->{'attr'}->{'IN_PORT'}->value(),$command->{'attr'}->{'DL_VLAN'}->value()),$command);
			next;
		    }
		    
		    for(my $i=0;$i<=$#{$command->{'action'}};$i++){
			my $action = $command->{'action'}->[$i];
			my $action2 = $action_list->[$i];
			if($action2->{'type'} == $action->[0]->value()){
			    if($action2->{'type'} == 0){
				#this is type of output
				if($action2->{'port'} == $action->[1]->[1]->value()){
				    #perfect keep going
				}else{
				    _log("Flowmod actions do not match, replacing");
				    #replace the busted flowmod with our new flowmod...
				    #first delay by some configured value in case the device can't handle it
				    usleep($node->{'tx_delay_ms'} * 1000);
				    my $result = $self->_replace_flowmod($dpid,_process_flow_stats_to_command($command->{'attr'}->{'IN_PORT'}->value(),$command->{'attr'}->{'DL_VLAN'}->value()),$command);
				    last;
				}
			    }elsif($action2->{'type'} == 1){
				#this is type of set vlan
				if($action2->{'vlan_vid'} == $action->[1]->value()){
				    #perfect keep going
				}else{
				    _log("Flowmod actions do not match, replacing");
				    #replace the busted flwomod with our new flowmod
				    #first delay by some configured value in case the device can't handle it
				    usleep($node->{'tx_delay_ms'} * 1000);
				    my $result = $self->_replace_flowmod($dpid,_process_flow_stats_to_command($command->{'attr'}->{'IN_PORT'}->value(),$command->{'attr'}->{'DL_VLAN'}->value()),$command);
				    last;
				}
			    }
			}
		    }
		}else{
		    _log("adding a missing flowmod");
		    #match doesn't exist in our current flows 
		    #first delay by some configured value in case the device can't handle it
		    usleep($node->{'tx_delay_ms'} * 1000);
		    my $result = $self->_replace_flowmod($dpid,undef,$command);
		}
	    }else{
		_log("adding a missing flowmod");
		#match doesn't exist in our current flows
		#first delay by some configured value in case the device can't handle it
		usleep($node->{'tx_delay_ms'} * 1000);
		my $result = $self->_replace_flowmod($dpid,undef,$command);
	    }
	}
    }

    #ok, now we need to figure out if we saw flowmods that we weren't suppose to
    foreach my $port_num (keys (%{$current_flows})){
	my $port = $current_flows->{$port_num};
	foreach my $vlan (keys (%{$port})){
	    if($port->{$vlan}->{'seen'} == 1){
		next;
	    }else{
		_log("Removing flowmod that was not suppose to be there");
		#first delay by some configured value in case the device can't handle it
		usleep($node->{'tx_delay_ms'} * 1000);
		my $result = $self->_replace_flowmod($dpid,_process_flow_stats_to_command($port_num,$vlan),undef);
	    }
	}
    }

    
    print "Diff complete: $dpid: circuits resynched \n";
}
    
    
=head2 port_status
    listens to the port status event from NOX
    and determins if a fail-over needs to occur
    **NOTE - Not used for add/delete events
=cut

sub port_status{
	my $self   = shift;
        my $dpid   = shift;
        my $reason = shift;
        my $info   = shift;

	return if($reason != OFPPR_MODIFY);

	my $port_name   = $info->{'name'};
	my $port_number = $info->{'port_no'};
	my $link_status = $info->{'link'};
	
	my $link_info   = $self->{'db'}->get_link_by_dpid_and_port(dpid => $dpid, 
								   port => $port_number);
	
	if (! defined $link_info || @$link_info < 1){
	    _log("Could not find link info for dpid = $dpid and port_no = $port_number");
	    return;
	}
    
	my $link_id = @$link_info[0]->{'link_id'};
	
	#--- when a port goes down, determine the set of ckts that traverse the port
	#--- for each ckt, fail over to the non-active path, after determining that the path 
	#--- looks to be intact.
	
	_log("Link status is $link_status");
	
	_log("link id is $link_id");
	
	if (! $link_status){
	    
	    my $affected_circuits = $self->{'db'}->get_affected_circuits_by_link_id(link_id => $link_id);
	    
	    if (! defined $affected_circuits){
		_log("Error getting affected circuits: " . $self->{'db'}->get_error());
		return;
	    }
	    
	    _log("Checking affected circuits...");
	    
	    foreach my $circuit_info (@$affected_circuits){
		my $circuit_id   = $circuit_info->{'id'};
		my $circuit_name = $circuit_info->{'name'};
		
		_log("Checking $circuit_id");
		
		if ( $self->{'db'}->circuit_has_alternate_path(circuit_id => $circuit_id ) ){		
		    
		    _log("Trying to change $circuit_id over to alternate path...");
		    
		    my $success = $self->{'db'}->switch_circuit_to_alternate_path(circuit_id => $circuit_id);
		    
		    _log("Success is $success");
		    
		    if (! $success){
			_log("Error changing \"$circuit_name\" (id = $circuit_id) to its backup: " . $self->{'db'}->get_error());
			next;
		    }
		    
		    $self->changeVlanPath($circuit_id);
		}
		else {
		    # this is probably where we would put the dynamic backup calculation
		    # when we get there.
		    _log("Warning: circuit \"$circuit_name\" (id = $circuit_id) has no backup and is now down.");
		}
	    }
	    
	}
	
	#--- when a port comes back up, do nothing for now, in future it might make sense to 
	#--- have a config option to return back to the primary on restoration of the path, when
	#--- the primary is determined to be intact.
	
        print "port status: $dpid: $reason: ".Dumper($info);
}

sub _get_rules_on_port{
    my $self = shift;
    my %args = @_;
    my $port_number = $args{'port_number'};
    my $dpid = $args{'dpid'};

    #find the interface
    my $interface = $self->{'db'}->get_interface_by_dpid_and_port( dpid => $dpid,
								   port_number => $port_number);

    #determine if anything needs to be pushed to the switch
    #get a list of current circuits that are somehow involved on this interface/node
    my $affected_circuits = $self->{'db'}->get_current_circuits_by_interface( interface => $interface);

    print STDERR "Looking for DPID: " . $dpid . "\n";
    print STDERR "Looking for PORT: " . $interface->{'port_number'} . "\n";

    my @port_commands;
    foreach my $ckt (@$affected_circuits){
	print STDERR "PRocessing command\n";
	my $circuit_id   = $ckt->{'circuit_id'};
	my $circuit_name = $ckt->{'name'};
	my $state        = $ckt->{'state'};

	next unless ($state eq "deploying" || $state eq "active");
	
	my $commands = $self->_generate_commands($circuit_id,FWDCTL_ADD_VLAN);
	foreach my $command (@$commands){
	    #ignore rules not for this dpid
	    next if($command->{'dpid'}->value() != $dpid);

	    #include rules that have a match on this port
	    if($command->{'attr'}->{'IN_PORT'}->value() == $port_number){
		push(@port_commands,$command);
		next;
	    }
	    
	    #include rules that have an action on this port
	    foreach my $action (@{$command->{'action'}}){
		print STDERR "  Action: " . Dumper($action);
		if($action->[0]->value() == OFPAT_OUTPUT && $action->[1]->[1]->value() == $port_number){
		    push(@port_commands,$command);
		}
	    }
	    
	}
    }

    #return the list of rules
    return \@port_commands;

}

sub _do_interface_diff{
    my $self = shift;
    my $node = shift;
    my $current_rules = shift;

    print STDERR "All Rules: " .  Dumper($current_rules);

    my %current_flows;

    $current_flows{$node->{'port_number'}} = $current_rules->{'port_number'};
    #first we need to filter this down to flows on our interfaces
    foreach my $port (keys (%{$current_rules})){
	next if($port == $node->{'port_number'});
	
	foreach my $vlan (keys (%{$current_rules->{$port}})){
	    my $actions = $current_rules->{$port}->{$vlan}->{'action'};
	    foreach my $action (@$actions){
		if($action->[0] == 0 && $action->[1] == $port){
		    $current_flows{$port}{$vlan} = $current_rules->{$port}->{$vlan};
		}
	    }
	}
    }
    
    print STDERR "Current Flows:" . Dumper(%current_flows);

    #get a list of all the rules that we want on the port
    my $rules = $self->_get_rules_on_port( port_number => $node->{'port_number'}, dpid => $node->{'dpid'} );
    
    print STDERR "Expected Flows: " . Dumper($rules);

    $self->_actual_diff( $node->{'dpid'}, \%current_flows, $rules);
}

sub topo_port_status{
        my $self   = shift;
        my $dpid   = shift;
        my $reason = shift;
        my $info   = shift;

        my $port_name   = $info->{'name'};
        my $port_number = $info->{'port_no'};
        my $link_status = $info->{'link'};
	
	my $interface = $self->{'db'}->get_interface_by_dpid_and_port( dpid => $dpid,
								       port_number => $port_number);
	print STDERR "Interface: " . Dumper($interface);
	my $node = $self->{'db'}->get_node_by_dpid( dpid => $dpid );

	print STDERR "Node: " . Dumper($node);
	#ok so this is for the add/delete event
	#not the up/down
	switch ($reason) {
	    #add case
	    case OFPPR_ADD {
		print STDERR "Detected the addition of an interface!!!\n";
		#get list of rules we currently have
		$node->{'interface_diff'} = 1;
		$node->{'port_number'} = $port_number;
		push(@{$self->{'nodes_for_diff'}},$node);

		#note that this will cause the flow_stats_in handler to handle this data
		#and it will then call the _do_interface_diff				
	    };
	    #the delete case
	    case OFPPR_DELETE{
		return 1;
		#determine if anything needs to be pushed to the switch
		#for now if we delete a link fail over
		my $link_info   = $self->{'db'}->get_link_by_dpid_and_port(dpid => $dpid,
                                                                           port => $port_number);

                if(defined($link_info)){
                    my $affected_circuits = $self->{'db'}->get_affected_circuits_by_link_id( link_id => $link_info->{'link_id'});
                    if (! defined $affected_circuits){
                        _log("Error getting affected circuits: " . $self->{'db'}->get_error());
                        return 1;
                    }

                    _log("Checking affected circuits...");

                    foreach my $circuit_info (@$affected_circuits){
                        my $circuit_id   = $circuit_info->{'id'};
                        my $circuit_name = $circuit_info->{'name'};

                        _log("Checking $circuit_id");

                        if ( $self->{'db'}->circuit_has_alternate_path(circuit_id => $circuit_id ) ){
                            _log("Trying to change $circuit_id over to alternate path...");
                            my $success = $self->{'db'}->switch_circuit_to_alternate_path(circuit_id => $circuit_id);
                            _log("Success is $success");
                            if (! $success){
                                _log("Error changing \"$circuit_name\" (id = $circuit_id) to its backup: " . $self->{'db'}->get_error());
                                next;
			    }
                            $self->changeVlanPath($circuit_id);
                        }else {
                            # this is probably where we would put the dynamic backup calculation
                            # when we get there.
                            _log("Warning: circuit \"$circuit_name\" (id = $circuit_id) has no backup and is now down.");
                        }
                    }
                }

	    };
	    case OFPPR_MODIFY{
		#don't do anything... we should not go here!
	    };
	}
	return 1;

}

sub _process_flows_to_hash{
    my $flows = shift;
    my $tmp = {};

    foreach my $flow (@$flows){
	my $match = $flow->{'match'};
	if(!defined($match->{'in_port'})){
	    next;
	}
	$tmp->{$match->{'in_port'}}->{$match->{'dl_vlan'}} = {seen => 0,actions => $flow->{'actions'}};
    }

    return $tmp;
}

sub flow_stats_in{
    my $self = shift;
    my $dpid = shift;
    my $flows = shift;

    if($#{$self->{'nodes_for_diff'}} < 0){
	return;
    }

    for(my $i=0;$i<=$#{$self->{'nodes_for_diff'}};$i++){
	my $node = $self->{'nodes_for_diff'}->[$i];
	print STDERR Dumper($node);
	if($node->{'dpid'} == $dpid){
	    #process the flow_rules into a lookup hash
	    my $hash = _process_flows_to_hash($flows);

	    #remove the node from the requested differ
	    splice(@{$self->{'nodes_for_diff'}},$i,1);

	    #now that we have the lookup hash of flow_rules
	    #do the diff
	    if($node->{'full_diff'} == 1){
		$self->_do_diff($node,$hash);
	    }elsif($node->{'interface_diff'} == 1){
		print STDERR "Doing an interface diff!!!\n";
		$self->_do_interface_diff($node,$hash);
	    }
	} 
    }
}

sub link_event {
    my $self   = shift;
    my $a_dpid = shift;
    my $a_port = shift;
    my $z_dpid = shift;
    my $z_port = shift;
    my $status = shift;
    
    
    print "link_event: $a_dpid:$a_port -> $z_dpid:$z_port is now $status\n";

}

sub _poll_xids{
    my $self    = shift;
    my $xids    = shift;

    my $result  = FWDCTL_SUCCESS;
    my $timeout = time() + 15;
    
    while (time() < $timeout){

	# no more xids to poll, we're done
	last if (@$xids == 0);

	for (my $i = @$xids - 1; $i > -1; $i--){

	    my $xid = @$xids[$i];    

	    my $output = $self->{'of_controller'}->get_dpid_result($xid);

	    # this one is still pending, just check the next
	    next if ($output == FWDCTL_WAITING);

	    # sadness, this one failed so we consider the whole thing a failure
	    if ($output == FWDCTL_FAILURE){
		$result = FWDCTL_FAILURE;
	    }

	    # we're done with this xid, get rid of it
	    splice(@$xids, $i, 1);
	}

    }

    #warn "XID Result is: $result";
    #warn "(1 => success, 2 => waiting, 0 => failure, 3 => unknown)";
    
    return $result;
}

#----- 
#dbus_method("addVlan", ["uint32"], ["string"]);

sub addVlan {
    my $self       = shift;
    my $circuit_id = shift;
    my $dpid	   = shift;

    print "addVlan: $circuit_id\n";
    my $topo = new OESS::Topology(db => $self->{'db'});
    my ($paths_are_valid,$reason) = $topo->validate_paths(circuit_id => $circuit_id);
    if(!$paths_are_valid){
	_log("Invalid VLAN: $reason\n");
	return "Invalid VLAN: $reason";
    }	
    #--- get the set of commands needed to create this vlan per design
    my $commands = $self->_generate_commands($circuit_id,FWDCTL_ADD_VLAN); 

    my @xids;

    foreach my $command(@{$commands}){
        my $node = $self->{'db'}->get_node_by_dpid( dpid => $command->{'dpid'});
	if(defined $dpid && $dpid != $command->{'dpid'}->value()){
            #--- if we are restricting the call to a specific dpid
            #--- then ignore commands to non-matching dpids
            #--- this is used when trying to synch up a specific switch
            next;
        }
        #first delay by some configured value in case the device can't handle it                                                                                                                                        
	usleep($node->{'tx_delay_ms'} * 1000);
	my $xid = $self->{'of_controller'}->install_datapath_flow($command->{'dpid'},$command->{'attr'},0,0,$command->{'action'},$command->{'attr'}->{'IN_PORT'});

	push(@xids, $xid);
    }	

    warn "XIDS:";
    warn Data::Dumper::Dumper(\@xids);

    my $result = $self->_poll_xids(\@xids);

    if ($result == FWDCTL_SUCCESS){

	my $details = $self->{'db'}->get_circuit_details(circuit_id => $circuit_id);
	
	my $user_id = $self->{'db'}->get_user_id_by_given_name(name => "System");
	
	if (! $user_id){
	    return "Unable to get System user: " . $self->{'db'}->get_error();       
	}
	
	if ($details->{'state'} eq "deploying" || $details->{'state'} eq "scheduled"){
	    
	    my $state = $details->{'state'};
	    
	    $self->{'db'}->update_circuit_state(circuit_id          => $circuit_id,
						old_state           => $state,
						new_state           => 'active',
						modified_by_user_id => $user_id 
		);
	    
	    $self->{'db'}->update_circuit_path_state(circuit_id  => $circuit_id,
						     old_state   => 'deploying',
						     new_state   => 'active',
		);
	}
    }

    return $result;
}

#dbus_method("deleteVlan", ["string"], ["string"]);

sub deleteVlan {
    my $self = shift;
    my $circuit_id = shift;

    print "removeVlan: $circuit_id\n";
    #--- get the set of commands needed to create this vlan per design
    my $commands = $self->_generate_commands($circuit_id,FWDCTL_REMOVE_VLAN);

    my @xids;
    
    foreach my $command(@{$commands}){
        #--- issue each command to controller
	#first delay by some configured value in case the device can't handle it
	my $node = $self->{'db'}->get_node_by_dpid( dpid => $command->{'dpid'});
	usleep($node->{'tx_delay_ms'} * 1000);
        my $xid = $self->{'of_controller'}->delete_datapath_flow($command->{'dpid'},$command->{'attr'});	
	push(@xids, $xid);
    }

    my $result = $self->_poll_xids(\@xids);
        
    return $result;
}


#dbus_method("changeVlanPath", ["string"], ["string"]);

sub changeVlanPath {
    my $self = shift;
    my $circuit_id = shift;

    print "changeVlan: $circuit_id\n";
    my $topo = new OESS::Topology(db => $self->{'db'});
    my ($paths_are_valid,$reason) = $topo->validate_paths(circuit_id => $circuit_id);
    if(!$paths_are_valid){
        _log("Invalid VLAN: $reason\n");
        return "Invalid VLAN: $reason";  
    }

    #--- get the set of commands needed to create this vlan per design
    my $commands = $self->_generate_commands($circuit_id,FWDCTL_CHANGE_PATH);

    my @xids;

    # we have to make sure to do the removes first
    foreach my $command(@$commands){
	my $node = $self->{'db'}->get_node_by_dpid( dpid => $command->{'dpid'});
	if ($command->{'sw_act'} eq FWDCTL_REMOVE_RULE){
	    #first delay by some configured value in case the device can't handle it                                                                                                                                        
	    usleep($node->{'tx_delay_ms'} * 1000);
	    my $xid = $self->{'of_controller'}->delete_datapath_flow($command->{'dpid'},$command->{'attr'});
	    push (@xids, $xid);
	}

    }

    my $result = $self->_poll_xids(\@xids);

    # we failed to remove any rules we needed to, no sense going forward. Report failure
    if ($result eq FWDCTL_FAILURE){
	return $result;
    }

    # reset xids
    @xids = ();

    foreach my $command(@$commands){
    
	if ($command->{'sw_act'} ne FWDCTL_REMOVE_RULE){
	    my $node = $self->{'db'}->get_node_by_dpid( dpid => $command->{'dpid'});
	    #first delay by some configured value in case the device can't handle it                                                                                                                                        
	    usleep($node->{'tx_delay_ms'} * 1000);
	    my $xid = $self->{'of_controller'}->install_datapath_flow($command->{'dpid'},$command->{'attr'},0,0,$command->{'action'},$command->{'attr'}->{'IN_PORT'});

	    push(@xids, $xid);
	}

    }

    $result = $self->_poll_xids(\@xids);
    
    return $result;
}


1;
###############################################################################
package main;

use OESS::DBus;
use Sys::Syslog qw(:standard :macros);
use Net::DBus::Exporter qw(org.nddi.fwdctl);
use Net::DBus qw(:typing);
use base qw(Net::DBus::Object);
use English;
use Getopt::Long;
use Proc::Daemon;

my $srv_object = undef;

sub core{

    my $dbus = OESS::DBus->new( service => "org.nddi.openflow", instance => "/controller1");
    
    if (! defined $dbus){
	_log("Could not connect to openflow service, aborting.");
	exit(1);
    }
    
    my $bus = Net::DBus->system;
    my $service = $bus->export_service("org.nddi.fwdctl");
    
    $srv_object = FwdCtl->new($service,$dbus->{'dbus'});

    #first thing to do is to try and push out all of the default forward/drop rules
    #to all of the switches to make sure they are in a known state
    sleep(10);
    $srv_object->_push_default_rules();
    
    #--- on creation we need to resync the database out to the network as the switches
    #--- might not be in the same state (emergency mode maybe) and there might be 
    #--- pending circuits created when this wasn't running
    $srv_object->_sync_database_to_network();
   
    #--- listen for topo events ----
    sub datapath_join_callback{
	my $dpid   = shift;
	my $ports  = shift;
	$srv_object->datapath_join($dpid,$ports);
    }
    
    sub port_status_callback{
	my $dpid   = shift;
	my $reason = shift;
	my $info   = shift;
	$srv_object->port_status($dpid,$reason,$info);
    }

    sub link_event_callback{
	my $a_dpid  = shift;
	my $a_port  = shift;
	my $z_dpid  = shift;
	my $z_port  = shift;
	my $status  = shift;
	$srv_object->link_event($a_dpid,$a_port,$z_dpid,$z_port,$status);
    }

    sub flow_stats_callback{
	my $dpid = shift;
	my $flows = shift;
	$srv_object->flow_stats_in($dpid,$flows);
    }

    $dbus->connect_to_signal("datapath_join",\&datapath_join_callback);
    $dbus->connect_to_signal("port_status",\&port_status_callback);
    $dbus->connect_to_signal("link_event",\&link_event_callback);
    $dbus->connect_to_signal("flow_stats_in",\&flow_stats_callback);
    $dbus->start_reactor();
}

sub main{
    my $is_daemon = 0;
    my $verbose;
    my $username;

    my $result = GetOptions ( #"length=i" => \$length, # numeric
			      #"file=s"   => \$data, # string
			      "user|u=s"  => \$username,
			      "verbose"   => \$verbose, #flag
			      "daemon|d"  => \$is_daemon,
	                    );

    if ($is_daemon != 0){
         openlog("fwctl.pl", 'cons,pid', LOG_DAEMON);
    }

    #now change username/
    if(defined $username){
	my $new_uid=getpwnam($username);
	my $new_gid=getgrnam($username);
	$EGID=$new_gid;
	$EUID=$new_uid;	
    }

    if ($is_daemon != 0){
       my $daemon = Proc::Daemon->new(
	                               pid_file => '/var/run/oess/fwdctl.pid',	                       
	                             );

       my $kid_pid = $daemon->Init;

       if ($kid_pid){
	   return;
       }

       core();
    }
    #not a deamon, just run the core;
    else{
      core();
    }

}

main();

1;
