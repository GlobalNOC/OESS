#!/usr/bin/perl 
#------ NDDI OESS Forwarding Control 
##-----
##----- $HeadURL:
##----- $Id:
##-----
##----- Listens to all events sent on org.nddi.openflow.events 
##---------------------------------------------------------------------
##
## Copyright 2013 Trustees of Indiana University 
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
use Time::HiRes qw( usleep );

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

my %node;

sub _log {
    my $string = shift;

    my $pid = getppid();

    if($pid == 1){
        openlog("fwdctl.pl", 'cons,pid', LOG_DAEMON);
	syslog(LOG_WARNING,$string);
	closelog();
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

    $self->{'nodes_needing_diff'} = {};
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
	$self->{'nodes_needing_diff'}{$node->{'dpid'}} = $node;
    }
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


    my $dpid_str  = sprintf("%x",$dpid);
    my $in_tag_str = $in_tag;
    if($in_tag == -1){
	$in_tag_str = "untagged";
    }
    my $out_tag_str = $out_tag;
    if($out_tag == -1){
        $out_tag_str = "untagged";
    }
 
    #_log("-- create forwarding rule: dpid:$dpid_str packets going in port:$in_port with tag:$in_tag_str sent out port:$out_port with tag:$out_tag_str\n");

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
    #_log( "Generate Commands - Circuit Details: " . Dumper($circuit_details));
    if (!defined $circuit_details){
	#_log("No Such Circuit");
        #--- no such ckt error
        #--- !!! need to set error !!!
        return undef;
    }
    my $dpid_lookup  = $self->{'db'}->get_node_dpid_hash();
    if(!defined $dpid_lookup){
	#_log("No Such DPID");
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

#--- this and dp join need to be refactored to reuse code.
sub _initialize{
    my $self = shift;
    
    my $nodes = $self->{'db'}->get_node_dpid_hash();

    foreach my $node (keys (%{$nodes})){
        my $dpid         = $nodes->{$node};
        $self->{'nodes_needing_init'}{$dpid} = $node; 

        $self->datapath_join_handler($dpid);
    }
}

sub datapath_join_handler{
    my $self   = shift;
    my $dpid   = shift;

    my $dpid_str  = sprintf("%x",$dpid);

    #--- first push the default "forward to controller" rule to this node. This enables
    #--- discovery to work properly regardless of whether the switch's implementation does it by default
    #--- or not
    my $node_details = $self->{'db'}->get_node_by_dpid(dpid => $dpid);
    my $sw_name = "";
    if(defined $node_details){
	$sw_name = $node_details->{'name'};
    }

    my %xid_hash;

    if(!defined($node_details) || $node_details->{'default_forward'} == 1){
	my $xid     = $self->{'of_controller'}->install_default_forward($dpid);
	if($xid == FWDCTL_FAILURE){
	  #--- switch may not be connected yet or other error in controller
	  _log("sw:$sw_name dpid:$dpid_str failed to install lldp forward to controller rule, discovery will fail");
	  return;
        }
	$xid_hash{$xid} = 1;
	$node{$dpid}++;
    }

    if(!defined($node_details) || $node_details->{'default_drop'} == 1){
	my $xid     = $self->{'of_controller'}->install_default_drop($dpid);
	if($xid == FWDCTL_FAILURE){
        #--- switch may not be connected yet or other error in controller
          _log("sw:$sw_name dpid:$dpid_str failed to install default drop rule, traffic may flood controller");
          return;
        }
        $xid_hash{$xid}  = 1;
	$node{$dpid}++;

	my $result = $self->_poll_xids(\%xid_hash);
	
	if ($result != FWDCTL_SUCCESS){
	    _log("sw:$sw_name dpid:$dpid_str failed to install default drop or lldp forward rules, may cause traffic to flood controller or discovery to fail");
	    return;
	}
	else {
	    _log("sw:$sw_name dpid:$dpid_str installed default drop rule and lldp forward rule");
	}

    }

    #set this node for diffing!
    $self->{'nodes_needing_diff'}{$dpid} = {dpid => $dpid, full_diff => 1};
    delete $self->{'nodes_needing_init'}{$dpid};

}

sub _replace_flowmod{
    my $self = shift;
    my $dpid = shift;
    my $delete_command = shift;
    my $new_command = shift;
    my $delay_ms    = shift;  #--- this is a value that should be an attribute of the object 
    my $xid;

    my $node = $self->{'db'}->get_node_by_dpid( dpid => $dpid);
    if(!defined($delete_command) && !defined($new_command)){
	return undef;
    }

    my %xid_hash; 

    #--- crude rate limiting
    if(defined $delay_ms){
    	usleep($delay_ms * 1000);
    }
    if(defined($delete_command)){
	#delete this flowmod
	$xid = $self->{'of_controller'}->delete_datapath_flow($dpid,$delete_command->{'attr'});
	$node{$dpid}--;
	$xid_hash{$xid} = 1;
    }
    
    if(defined($new_command)){
	if( $node{$dpid} >= $node->{'max_flows'}){
	    my $dpid_str  = sprintf("%x",$dpid);
            _log("sw: dpipd:$dpid_str exceeding max_flows:".$node->{'max_flows'}." replace flowmod failed");
            return FWDCTL_FAILURE;
        }
	$xid = $self->{'of_controller'}->install_datapath_flow($dpid,$new_command->{'attr'},0,0,$new_command->{'action'},$new_command->{'attr'}->{'IN_PORT'});
	$node{$dpid}++;
    	$xid_hash{$xid} = 1;    
	#wait for the delete to take place
    }

    my $result = $self->_poll_xids(\%xid_hash);
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

    my $dpid          = $node->{'dpid'};
    my $dpid_str      = sprintf("%x",$dpid);
    my $node_info     = $self->{'db'}->get_node_by_dpid( dpid => $dpid );
    my $sw_name       = $node_info->{'name'};

    _log("sw:$sw_name dpid:$dpid_str diff sw rules to oe-ss rules");
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

    $self->_actual_diff($dpid,$sw_name, $current_flows, \@all_commands);
}


sub _actual_diff{
    my $self = shift;
    my $dpid = shift;
    my $sw_name = shift;
    my $current_flows = shift;
    my $commands = shift;

    my @rule_queue;			#--- temporary storage of forwarding rules
    my %stats = ( 
			mods => 0,
			adds => 0,
			rems => 0
		);			#--- used to store stats about the diff
    
    my $node = $self->{'db'}->get_node_by_dpid( dpid => $dpid);
    my $dpid_str  = sprintf("%x",$dpid);

    foreach my $command (@$commands){
	#---ignore rules not for this dpid
	next if($command->{'dpid'}->value() != $dpid);
	my $com_port = $command->{'attr'}->{'IN_PORT'}->value();
        my $com_vid  = $command->{'attr'}->{'DL_VLAN'}->value();
	if(defined($current_flows->{$com_port})){
	    #--- we have observed flows on the same switch port defined in the command
	    my $obs_port = $current_flows->{$com_port};
	    if(defined($obs_port->{$com_vid})){
		#--- we have have a flow on the same switchport with the same vid match
		my $action_list = $obs_port->{$com_vid}->{'actions'};
		#increment the number of flow_mods we know are on the box
		$node{$dpid}++;
		$obs_port->{$com_vid}->{'seen'} = 1;
		
		if($#{$action_list} != $#{$command->{'action'}}){
		    #-- the number of actions in the observed and the planned dont match just replace
		    $stats{'mods'}++;
		    _log("--- we have a match port $com_port vid $com_vid, but num actions is wrong\n");
		    push(@rule_queue, [$dpid,_process_flow_stats_to_command($com_port,$com_vid),$command,$node->{'tx_delay_ms'}]);
		    next;
		}
		
		for(my $i=0;$i<=$#{$command->{'action'}};$i++){
		    my $action = $command->{'action'}->[$i];
		    my $action2 = $action_list->[$i];
		    if($action2->{'type'} == $action->[0]->value()){
			if($action2->{'type'} == OFPAT_OUTPUT){
			    if($action2->{'port'} == $action->[1]->[1]->value()){
				#--- port matches nothing to do
			    }else{
				#--- port does not match we need to replace the rule on the switch
				_log("--- we have a match port $com_port vid $com_vid, but output port is wrong\n");

                    		$stats{'mods'}++;
                    		push(@rule_queue, [$dpid,_process_flow_stats_to_command($com_port,$com_vid),$command,$node->{'tx_delay_ms'}]);
				last;
			    }
			}elsif($action2->{'type'} ==  OFPAT_SET_VLAN_VID ){
			    if($action2->{'vlan_vid'} == $action->[1]->value()){
				#--- vlan_id also matches nothing to do
			    }else{
				#--- vlan_id does not match we need to replace the rule on the switch
				_log("--- we have a match port $com_port vid $com_vid, but set vid action is wrong\n");
                    		$stats{'mods'}++;
                    		push(@rule_queue, [$dpid,_process_flow_stats_to_command($com_port,$com_vid),$command,$node->{'tx_delay_ms'}]);
				last;
			    }
			}
		    }
		}
	    }else{
		#---rule missing on switch
                $stats{'adds'}++;
		_log("--- 1.  we have a rule for port $com_port vid $com_vid  that doesnt appear on switch\n");

                push(@rule_queue, [$dpid,undef,$command,$node->{'tx_delay_ms'}]);
	    }
	}else{
	    #---rule missing on switch
	    $stats{'adds'}++;
	    _log("--- 2.  we have a rule for port $com_port vid $com_vid  that doesnt appear on switch\n");
	    push(@rule_queue, [$dpid,undef,$command,$node->{'tx_delay_ms'}]);
	}
    }
    #--- look for rules which are on the switch but which should not be there by design
    foreach my $port_num (keys (%{$current_flows})){
	my $obs_port = $current_flows->{$port_num};
	foreach my $obs_vid (keys (%{$obs_port})){
	    if($obs_port->{$obs_vid}->{'seen'} == 1){
		#--- rule has already been seen when iterating above, skip
		next;
	    }else{
		#---rule needs to be removed from switch 
		$stats{'rems'}++;
		_log("--- we have a a rule on the switch for port $port_num vid $obs_vid which doesnt correspond with plan\n");
		#need to add to our total number of flows_on_the_switch... will be decremented once removed
		$node{'dpid'}++;
		push(@rule_queue, [$dpid,_process_flow_stats_to_command($port_num,$obs_vid),undef,$node->{'tx_delay_ms'}]);
	    }
	}
    }

    my $total = $stats{'mods'} + $stats{'adds'} + $stats{'rems'};
     _log("sw:$sw_name dpid:$dpid_str diff plan  $total changes.  mods:".$stats{'mods'}. " adds:".$stats{'adds'}. " removals:".$stats{'rems'}."\n");
    
    #--- process the rule_queue
    my $success_count=0;
    foreach my $args (@rule_queue){
      my $result = $self->_replace_flowmod(@$args);   
      if($result ==  FWDCTL_SUCCESS){
	$success_count++;
      }  	
    }
     _log("sw:$sw_name dpid:$dpid_str diff completed $success_count of $total changes\n");

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

	my $node_details = $self->{'db'}->get_node_by_dpid( dpid => $dpid );

	
	my $link_info   = $self->{'db'}->get_link_by_dpid_and_port(dpid => $dpid, 
								   port => $port_number);
	
	if (! defined $link_info || @$link_info < 1){
	   #--- no link means edge port
	   # _log("Could not find link info for dpid = $dpid and port_no = $port_number");
	    return;
	}
    
	my $link_id   = @$link_info[0]->{'link_id'};
        my $link_name = @$link_info[0]->{'name'};
        my $sw_name   = $node_details->{'name'};
	my $dpid_str  = sprintf("%x",$dpid);
	
	#--- when a port goes down, determine the set of ckts that traverse the port
	#--- for each ckt, fail over to the non-active path, after determining that the path 
	#--- looks to be intact.
	if (! $link_status){
	 _log("sw:$sw_name dpid:$dpid_str port $port_name trunk $link_name is down");
	    
	    my $affected_circuits = $self->{'db'}->get_affected_circuits_by_link_id(link_id => $link_id);
	    
	    if (! defined $affected_circuits){
		_log("Error getting affected circuits: " . $self->{'db'}->get_error());
		return;
	    }
	    
	    foreach my $circuit_info (@$affected_circuits){
		my $circuit_id   = $circuit_info->{'id'};
		my $circuit_name = $circuit_info->{'name'};
		
		if ( $self->{'db'}->circuit_has_alternate_path(circuit_id => $circuit_id ) ){		
		    my $success = $self->{'db'}->switch_circuit_to_alternate_path(circuit_id => $circuit_id);
                    _log("vlan:$circuit_name id:$circuit_id affected by trunk:$link_name moving to alternate path");     
		    if (! $success){
			 _log("vlan:$circuit_name id:$circuit_id affected by trunk:$link_name has NOT been moved to alternate path due to error: ".$self->{'db'}->get_error());
			next;
		    }
		    
		    $self->changeVlanPath($circuit_id);
		    #--- no way to now if this succeeds???

		}
		else {
		    # this is probably where we would put the dynamic backup calculation
		    # when we get there.
		    _log("vlan:$circuit_name id:$circuit_id affected by trunk:$link_name  has no alternate path and is down");  
		}
	    }
	    
	}
	
	#--- when a port comes back up, do nothing for now, in future it might make sense to 
	#--- have a config option to return back to the primary on restoration of the path, when
	#--- the primary is determined to be intact.
	
#        _log("port status: $dpid: $reason: ".Dumper($info));
}

sub _get_rules_on_port{
    my $self = shift;
    my %args = @_;
    my $port_number = $args{'port_number'};
    my $dpid = $args{'dpid'};
    my $dpid_str  = sprintf("%x",$dpid);

    _log("Find vlans that depend on dpid:$dpid_str port:$port_number");

    #find the interface
    my $interface = $self->{'db'}->get_interface_by_dpid_and_port( dpid => $dpid,
								   port_number => $port_number);
    #determine if anything needs to be pushed to the switch
    #get a list of current circuits that terminate on this interface
    my $affected_circuits = $self->{'db'}->get_current_circuits_by_interface( interface => $interface);

    #get the link and list of circuits affected by this interface
    my $link = $self->{'db'}->get_link_by_interface_id( interface_id => $interface->{'interface_id'});
    if(defined($link)){

	my $affected_link_circuits = $self->{'db'}->get_affected_circuits_by_link_id( link_id => $link->[0]->{'link_id'} );

	foreach my $ckt (@$affected_link_circuits){
	    push(@$affected_circuits,$ckt);
	}
    }

    my @port_commands;
    foreach my $ckt (@$affected_circuits){
	my $circuit_id   = $ckt->{'id'};
	my $circuit_name = $ckt->{'name'};
	my $state        = $ckt->{'state'};

	next unless ($state eq "deploying" || $state eq "active" || !defined($state));
        _log("vlan:$circuit_name id:$circuit_id depends on dpid:$dpid_str port:$port_number");
	
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
    my $dpid_str  = sprintf("%x",$node->{'dpid'});

    _log("sw: dpid:$dpid_str diff sw rules to oe-ss rules for port:".$current_rules->{'port_number'});

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
    
    #get a list of all the rules that we want on the port
    my $rules = $self->_get_rules_on_port( port_number => $node->{'port_number'}, dpid => $node->{'dpid'} );
    
    $self->_actual_diff( $node->{'dpid'}, \%current_flows, $rules);
    _log("sw: dpid:$dpid_str diff sw rules to oe-ss rules for port:".$current_rules->{'port_number'}." complete");
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
	my $node = $self->{'db'}->get_node_by_dpid( dpid => $dpid );

        my $link_info   = $self->{'db'}->get_link_by_dpid_and_port(dpid => $dpid,
                                                                           port => $port_number);
	my $link_id   = @$link_info[0]->{'link_id'};
        my $link_name = @$link_info[0]->{'name'};
        my $sw_name   = $node->{'name'};
        my $dpid_str  = sprintf("%x",$dpid);

	switch ($reason) {
	    #add case
	    case OFPPR_ADD {
		_log("sw:$sw_name dpid:$dpid_str port $port_name trunk $link_name has been added");
		#get list of rules we currently have
		$node->{'interface_diff'} = 1;
		$node->{'port_number'} = $port_number;
		 $self->{'nodes_needing_diff'}{$dpid} = $node;

		#note that this will cause the flow_stats_in handler to handle this data
		#and it will then call the _do_interface_diff				
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
   

	#--- internally we represet untagged as -1 
	my $vid = $match->{'dl_vlan'};
	if($vid == 65535){
		$vid = -1;
        }    
	$tmp->{$match->{'in_port'}}->{$vid} = {seen => 0,actions => $flow->{'actions'}};
    }

    return $tmp;
}


sub flow_stats_in{
    my $self = shift;
    my $dpid = shift;
    my $flows = shift;

    #--- check to see if node still needs to be initialized
    my $node = $self->{'nodes_needing_init'}{$dpid};
    if(defined $node){
      $self->datapath_join_handler($dpid);
    }

    #--- check to see if we need to perform diff
    $node = $self->{'nodes_needing_diff'}{$dpid};
    return if(!defined $node);

    #---process the flow_rules into a lookup hash
    my $hash = _process_flows_to_hash($flows);

    #--- take off the queue
    delete  $self->{'nodes_needing_diff'}{$dpid};

    #--- now that we have the lookup hash of flow_rules
    #--- do the diff
    if($node->{'full_diff'} == 1){
      $self->_do_diff($node,$hash);
    }elsif($node->{'interface_diff'} == 1){
      $self->_do_interface_diff($node,$hash);
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
    my $self          = shift;
    my $xid_hash_ref  = shift;   #-- some day hash will be useful if we have to do aysnch error handling

    my $result  = FWDCTL_SUCCESS;
    my $timeout = time() + 15;
    
    while (time() < $timeout){
	foreach my $xid (keys %$xid_hash_ref){
	    my $output = $self->{'of_controller'}->get_dpid_result($xid);

	    #-- pending, retry later 
	    next if ($output == FWDCTL_WAITING);

	    #--- one failed , some day have handler passed in hash 
	    if ($output == FWDCTL_FAILURE){
		$result = FWDCTL_FAILURE;
	    }
	    #--- must be success, remove from hash
	    delete $xid_hash_ref->{$xid};

        }
	if(scalar keys %$xid_hash_ref == 0){
	  return $result;
        }
	#--- if we got here lets take a short nap
	usleep(100);
    }

    return $result;
}

#----- 
#dbus_method("addVlan", ["uint32"], ["string"]);

sub addVlan {
    my $self       = shift;
    my $circuit_id = shift;
    my $dpid	   = shift;

    _log("addVlan: $circuit_id");
    my $topo = new OESS::Topology(db => $self->{'db'});
    my ($paths_are_valid,$reason) = $topo->validate_paths(circuit_id => $circuit_id);
    if(!$paths_are_valid){
	_log("Invalid VLAN: $reason\n");
	return "Invalid VLAN: $reason";
    }	
    #--- get the set of commands needed to create this vlan per design
    my $commands = $self->_generate_commands($circuit_id,FWDCTL_ADD_VLAN); 

    my %xid_hash;

    foreach my $command(@{$commands}){
	#---!_!_! this needs to not make redudant queries
        my $node = $self->{'db'}->get_node_by_dpid( dpid => $command->{'dpid'}->value());
	if(defined $dpid && $dpid != $command->{'dpid'}->value()){
            #--- if we are restricting the call to a specific dpid
            #--- then ignore commands to non-matching dpids
            #--- this is used when trying to synch up a specific switch
            next;
        }
        #first delay by some configured value in case the device can't handle it                                                                                                                                        
	usleep($node->{'tx_delay_ms'} * 1000);
	if($node{$command->{'dpid'}->value()} >= $node->{'max_flows'}){
	    my $dpid_str  = sprintf("%x",$command->{'dpid'});
            _log("sw: dpipd:$dpid_str exceeding max_flows:".$node->{'max_flows'}." adding vlan failed");
	    return FWDCTL_FAILURE;
	}
	my $xid = $self->{'of_controller'}->install_datapath_flow($command->{'dpid'},$command->{'attr'},0,0,$command->{'action'},$command->{'attr'}->{'IN_PORT'});
	$node{$command->{'dpid'}->value()}++;
	$xid_hash{$xid} = 1;
    }	

    #warn "XIDS:";
    #warn Data::Dumper::Dumper(\@xids);

    my $result = $self->_poll_xids(\%xid_hash);

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
	}
	$self->{'db'}->update_circuit_path_state(circuit_id  => $circuit_id,
						 old_state   => 'deploying',
						 new_state   => 'active',
	    );
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

    my %xid_hash;
    
    foreach my $command(@{$commands}){
        #--- issue each command to controller
	#first delay by some configured value in case the device can't handle it
	my $node = $self->{'db'}->get_node_by_dpid( dpid => $command->{'dpid'}->value());
	usleep($node->{'tx_delay_ms'} * 1000);
        my $xid = $self->{'of_controller'}->delete_datapath_flow($command->{'dpid'},$command->{'attr'});	
	$node{$command->{'dpid'}}--;
	$xid_hash{$xid} = 1;
    }

    my $result = $self->_poll_xids(\%xid_hash);
        
    return $result;
}


#dbus_method("changeVlanPath", ["string"], ["string"]);

sub changeVlanPath {
    my $self = shift;
    my $circuit_id = shift;

    print "changeVlanPath: $circuit_id\n";
    my $topo = new OESS::Topology(db => $self->{'db'});
    my ($paths_are_valid,$reason) = $topo->validate_paths(circuit_id => $circuit_id);
    if(!$paths_are_valid){
        _log("Invalid VLAN: $reason\n");
        return "Invalid VLAN: $reason";  
    }

    #--- get the set of commands needed to create this vlan per design
    my $commands = $self->_generate_commands($circuit_id,FWDCTL_CHANGE_PATH);

    my @xids;
    my %xid_hash;

    # we have to make sure to do the removes first
    foreach my $command(@$commands){
	my $node = $self->{'db'}->get_node_by_dpid( dpid => $command->{'dpid'}->value());
	if ($command->{'sw_act'} eq FWDCTL_REMOVE_RULE){
	    #first delay by some configured value in case the device can't handle it                                                                                                                                        
	    usleep($node->{'tx_delay_ms'} * 1000);
	    my $xid = $self->{'of_controller'}->delete_datapath_flow($command->{'dpid'},$command->{'attr'});
	    $node{$command->{'dpid'}}--;
	    $xid_hash{$xid} = 1;
	}

    }

    foreach my $command(@$commands){
	if ($command->{'sw_act'} ne FWDCTL_REMOVE_RULE){
	    my $node = $self->{'db'}->get_node_by_dpid( dpid => $command->{'dpid'}->value());
	    #first delay by some configured value in case the device can't handle it                                                                                                                                        
	    usleep($node->{'tx_delay_ms'} * 1000);
	    if($node{$command->{'dpid'}} >= $node->{'max_flows'}){
		 my $dpid_str  = sprintf("%x",$command->{'dpid'});
		_log("sw: dpipd:$dpid_str exceeding max_flows:".$node->{'max_flows'}." changing path failed");
		return FWDCTL_FAILURE;
	    }
	    my $xid = $self->{'of_controller'}->install_datapath_flow($command->{'dpid'},$command->{'attr'},0,0,$command->{'action'},$command->{'attr'}->{'IN_PORT'});
	    $node{$command->{'dpid'}}++;
	    $xid_hash{$xid} = 1;
	}

    }

    my $result = $self->_poll_xids(\%xid_hash);

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
    $srv_object->_initialize();
    
    #--- on creation we need to resync the database out to the network as the switches
    #--- might not be in the same state (emergency mode maybe) and there might be 
    #--- pending circuits created when this wasn't running
    $srv_object->_sync_database_to_network();
   
    #--- listen for topo events ----
    sub datapath_join_callback{
	my $dpid   = shift;
	my $ports  = shift;
        my $dpid_str  = sprintf("%x",$dpid);
        FwdCtl::_log("sw: dpipd:$dpid_str datapath_join");
	$srv_object->datapath_join_handler($dpid);
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
    FwdCtl::_log("all signals connected");
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
