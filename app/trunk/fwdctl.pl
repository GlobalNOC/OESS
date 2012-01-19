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

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => -1;

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

    $self->{'db'} = $db;

    dbus_method("addVlan", ["uint32"], ["string"]);
    dbus_method("deleteVlan", ["string"], ["string"]);
    dbus_method("changeVlanPath", ["string"], ["string"]);

    return $self;
}

sub _sync_database_to_network {
    my $self = shift;

    my $current_circuits = $self->{'db'}->get_current_circuits();

    if (! defined $current_circuits){
	_log("!!!Unable to sync database to network!!!\nSleeping 10 seconds to give you a chance to abort (control-c)...");
	sleep(10);
	return;
    }
    
    foreach my $circuit (@$current_circuits){
	my $circuit_id   = $circuit->{'circuit_id'};
	my $circuit_name = $circuit->{'name'}; 
	my $state        = $circuit->{'state'};

	next unless ($state eq "deploying" || $state eq "active");

	_log("  - Syncing \"$circuit_name\" (id = $circuit_id)...");

	#!!! would probably be useful to have a meaningful return code here
	$self->addVlan($circuit_id);
    }

    return 1;
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
    $rule{'attr'}{'IN_PORT'}  = dbus_uint16($in_port);

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
            if ($actions->[0][0]->value()    == OFPAT_SET_VLAN_VID &&
                $actions->[0][1]->value()    == $out_tag &&
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

    if (!defined $circuit_details){
        #--- no such ckt error
        #--- !!! need to set error !!!
        return undef;
    }
    my $dpid_lookup  = $self->{'db'}->get_node_dpid_hash();
    if(!defined $dpid_lookup){
	#--- some sorta of internal error
	#--- !!! need to set error !!!
	return undef;
    }
 
    my %primary_path;
    my %backup_path;
    my @commands;

    foreach my $link (@{$circuit_details->{'links'}}){
	$primary_path{$link->{'node_a'}}{$circuit_details->{'pri_path_internal_tag'}}{$link->{'port_no_a'}} = 1;
	$primary_path{$link->{'node_z'}}{$circuit_details->{'pri_path_internal_tag'}}{$link->{'port_no_z'}} = 1;
    }
    foreach my $link (@{$circuit_details->{'backup_links'}}){
        $backup_path{$link->{'node_a'}}{$circuit_details->{'bu_path_internal_tag'}}{$link->{'port_no_a'}} = 1;
        $backup_path{$link->{'node_z'}}{$circuit_details->{'bu_path_internal_tag'}}{$link->{'port_no_z'}} = 1;
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

     my $path = \%primary_path;
     #--- go node by node and figure out the simple forwarding rules for this path
     foreach my $node (sort keys %$path){
         foreach my $vlan_tag (sort keys %{$path->{$node}}){
             #--- iterate through ports need set of rules for each input/output port combo
             foreach my $interface(sort keys %{$path->{$node}{$vlan_tag}}){
                 foreach my $other_if(sort keys %{$path->{$node}{$vlan_tag}}){
	             #--- skip when the 2 interfaces are the same
                     next if($other_if eq $interface);
	             $self->_generate_forward_rule(\@commands,$dpid_lookup->{$node},$vlan_tag,$interface,$other_if,$sw_act);
                 }
             }
         }
    } 

    $path = \%backup_path;
    #--- go node by node and figure out the simple forwarding rules for this path
    foreach my $node (sort keys %$path){
        foreach my $vlan_tag (sort keys %{$path->{$node}}){
        #--- iterate through ports need set of rules for each input/output port combo
            foreach my $interface(sort keys %{$path->{$node}{$vlan_tag}}){
                foreach my $other_if(sort keys %{$path->{$node}{$vlan_tag}}){
                    #--- skip when the 2 interfaces are the same
                    next if($other_if eq $interface);
                    $self->_generate_forward_rule(\@commands,$dpid_lookup->{$node},$vlan_tag,$interface,$other_if,$sw_act);
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
      foreach my $inner_tag (sort keys %{$primary_path{$node}}){
        foreach my $other_if(sort keys %{$primary_path{$node}{$inner_tag}}){
           $self->_generate_translation_rule(\@commands,$dpid_lookup->{$node},$outer_tag, $interface, $inner_tag, $other_if,$sw_act);
	   $self->_generate_translation_rule(\@commands,$dpid_lookup->{$node},$inner_tag, $other_if, $outer_tag, $interface,$sw_act);
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
        foreach my $inner_tag (sort keys %{$path->{$node}}){
          foreach my $other_if(sort keys %{$path->{$node}{$inner_tag}}){
              $self->_generate_translation_rule(\@commands,$dpid_lookup->{$node},$outer_tag, $interface, $inner_tag, $other_if,FWDCTL_ADD_RULE);
              $self->_generate_translation_rule(\@commands,$dpid_lookup->{$node},$inner_tag, $other_if, $outer_tag, $interface,FWDCTL_ADD_RULE);
         }
       }

       #--- remove existing edge rules
       foreach my $inner_tag (sort keys %{$old->{$node}}){
         foreach my $other_if(sort keys %{$old->{$node}{$inner_tag}}){
             $self->_generate_translation_rule(\@commands,$dpid_lookup->{$node},$outer_tag, $interface, $inner_tag, $other_if,FWDCTL_REMOVE_RULE);
	     $self->_generate_translation_rule(\@commands,$dpid_lookup->{$node},$inner_tag, $other_if, $outer_tag, $interface,FWDCTL_REMOVE_RULE);
         }
       }
    }
     
     return \@commands; 
   }
}



sub datapath_join{
    my $self   = shift;
    my $dpid   = shift;
    my $ports  = shift;


    #--- get the set of circuits
    my $current_circuits = $self->{'db'}->get_current_circuits();
    if (! defined $current_circuits){
        _log("!!! cant get the list of current circuits");
        return;
    }
    
   #--- process each ckt
    foreach my $circuit (@$current_circuits){
        my $circuit_id   = $circuit->{'circuit_id'};
        my $circuit_name = $circuit->{'name'};
        my $state        = $circuit->{'state'};
    
        next unless ($state eq "deploying" || $state eq "active");
    
        _log("  - Syncing dpid=$dpid \"$circuit_name\" (id = $circuit_id)...");
    
        #--- call addVlan but pass a second arg of dpid that tells add to only update the specified dpid.
        #--- in the case where a switch goes down, the port_status event will trigger a vlan to fail over to 
        #--- backup, if the port going down was caused by a switch crashing, then when it reboots, we will get
        #--- this join event, and we will readd the primary path which will likely be non-active.
        $self->addVlan($circuit_id,$dpid);
    }
    print "datapath_join: $dpid: circuits resynched \n";
}
    
    

sub port_status{
	my $self   = shift;
        my $dpid   = shift;
        my $reason = shift;
        my $info   = shift;

	#_log(Dumper($info));

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

	    my $output = $self->{'of_controller'}->get_xid_result($xid);

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
        if(defined $dpid && $dpid != $command->{'dpid'}->value()){
            #--- if we are restricting the call to a specific dpid
            #--- then ignore commands to non-matching dpids
            #--- this is used when trying to synch up a specific switch
            next;
        }

	my $xid = $self->{'of_controller'}->install_datapath_flow($command->{'dpid'},$command->{'attr'},0,0,$command->{'action'},$command->{'attr'}->{'IN_PORT'});

	push(@xids, $xid);
    }	

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

    return "{status: $result}";
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
        my $xid = $self->{'of_controller'}->delete_datapath_flow($command->{'dpid'},$command->{'attr'});	
	push(@xids, $xid);
    }

    my $result = $self->_poll_xids(\@xids);
        
    return "{status: $result}";
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

	if ($command->{'sw_act'} eq FWDCTL_REMOVE_RULE){
	    my $xid = $self->{'of_controller'}->delete_datapath_flow($command->{'dpid'},$command->{'attr'});
	    push (@xids, $xid);
	}

    }

    my $result = $self->_poll_xids(\@xids);

    # we failed to remove any rules we needed to, no sense going forward. Report failure
    if ($result eq 0){
	return "{status: 0}";
    }

    # reset xids
    @xids = ();

    foreach my $command(@$commands){
    
	if ($command->{'sw_act'} ne FWDCTL_REMOVE_RULE){
	    my $xid = $self->{'of_controller'}->install_datapath_flow($command->{'dpid'},$command->{'attr'},0,0,$command->{'action'},$command->{'attr'}->{'IN_PORT'});

	    push(@xids, $xid);
	}

    }

    $result = $self->_poll_xids(\@xids);
    
    return "{status: $result}";
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

    $dbus->connect_to_signal("datapath_join",\&datapath_join_callback);
    $dbus->connect_to_signal("port_status",\&port_status_callback);
    $dbus->connect_to_signal("link_event",\&link_event_callback);
   
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
