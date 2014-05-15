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
package OESS::FWDCTL::Switch;

use strict;
use Data::Dumper;

use Log::Log4perl;
use Switch;
use Storable;

use AnyEvent;
use OESS::FlowRule;
use OESS::DBus;
use Net::DBus;

use JSON;
use Time::HiRes qw( usleep );

use constant FWDCTL_ADD_VLAN     => 0;
use constant FWDCTL_REMOVE_VLAN  => 1;
use constant FWDCTL_CHANGE_PATH  => 2;

use constant FWDCTL_ADD_RULE     => 0;
use constant FWDCTL_REMOVE_RULE  => 1;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;

$| = 1;

$Storable::Deparse = 1;
$Storable::Eval = 1;

=head1 NAME OESS::FWDCTL::Switch

=cut

=head2 new

=cut

sub new {
    my $class = shift;
    
    my %args = (
        @_
    );
    
    if(!defined($args{'dpid'})){
        my $logger = Log::Log4perl->get_logger("OESS.FWDCTL.SWITCH");
        $logger->error("no DPID specified!!!");
        return;
    }

    my $nox = OESS::DBus->new( service => 'org.nddi.openflow', instance => '/controller1');

    my $self = \%args;

    $self->{'nox'} = $nox->{'dbus'};

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.FWDCTL.Switch.' . sprintf("%x",$self->{'dpid'}));
    $self->{'logger'}->debug("I EXIST!!!");
    bless $self, $class;
    
    $self->_update_cache();
    $self->datapath_join_handler();
    
    $self->{'timer'} = AnyEvent->timer( after => 10, interval => 10, 
                                        cb => sub { 
                                            $self->{'logger'}->debug("Processing FlowStat Timer event");
                                            $self->get_flow_stats();
                                        } );
    return $self;
}

=head2 echo

=cut

sub echo{
    my $self = shift;
    return FWDCTL_SUCCESS;
}

sub _update_cache{
    my $self = shift;
    $self->{'logger'}->debug("Retrieve file: " . $self->{'share_file'});
    my $data = retrieve($self->{'share_file'});
    $self->{'logger'}->debug("Fetched data!");
    my %ckts;

    
    foreach my $ckt (keys %{ $data->{'ckts'}}){

        $self->{'logger'}->debug("processing cache for circuit: " . $ckt);
        $ckts{$ckt}->{'details'} = $data->{'ckts'}->{$ckt}->{'details'};

        foreach my $obj (@{$data->{'ckts'}->{$ckt}->{'flows'}->{'current'}}){
            next unless($obj->{'dpid'} == $self->{'dpid'});
            my $flow = OESS::FlowRule->new( match => $obj->{'match'},
                                            actions => $obj->{'actions'},
                                            dpid => $obj->{'dpid'},
                                            priority => $obj->{'priority'});
            push(@{$ckts{$ckt}->{'flows'}->{'current'}},$flow);
        }

        foreach my $obj (@{$data->{'ckts'}->{$ckt}->{'flows'}->{'endpoint'}->{'primary'}}){
            next unless($obj->{'dpid'} == $self->{'dpid'});
            my $flow = OESS::FlowRule->new( match => $obj->{'match'},
                                            actions => $obj->{'actions'},
                                            dpid => $obj->{'dpid'},
                                            priority =>$obj->{'priority'});
            push(@{$ckts{$ckt}->{'flows'}->{'endpoint'}->{'primary'}},$flow);
        }

        foreach my $obj (@{$data->{'ckts'}->{$ckt}->{'flows'}->{'endpoint'}->{'backup'}}){
            next unless($obj->{'dpid'} == $self->{'dpid'});
            my $flow = OESS::FlowRule->new( match => $obj->{'match'},
                                            actions => $obj->{'actions'},
                                            dpid => $obj->{'dpid'},
                                            priority =>$obj->{'priority'});
            push(@{$ckts{$ckt}->{'flows'}->{'endpoint'}->{'backup'}},$flow);
        }
        

        foreach my $obj (@{$data->{'ckts'}->{$ckt}->{'flows'}->{'static_mac_addr'}}){
            next unless($obj->{'dpid'} == $self->{'dpid'});
            my $flow = OESS::FlowRule->new( match => $obj->{'match'},
                                            actions => $obj->{'actions'},
                                            dpid => $obj->{'dpid'},
                                            priority =>$obj->{'priority'});
            push(@{$ckts{$ckt}->{'flows'}->{'static_mac_addr'}},$flow);
        }

    }
    $self->{'data'} = {nodes => $data->{'nodes'},
                       ckts => \%ckts};

    $self->{'logger'}->debug("Cache update for circuits: " . Data::Dumper::Dumper(keys (%ckts)));

    $self->{'ckts'} = \%ckts;
    $self->{'node'} = $data->{'nodes'}->{$self->{'dpid'}};
    $self->{'logger'}->info("Updating node info: " . Data::Dumper::Dumper($self->{'node'}));
    $self->{'settings'} = $data->{'settings'};

}

sub _generate_commands{
    my $self = shift;
    my $circuit_id = shift;
    my $action = shift;
    
    $self->{'logger'}->debug("getting flows for circuit_id: " . $circuit_id);
    
    if(!defined($self->{'ckts'}->{$circuit_id})){
        $self->{'logger'}->error("No circuit with id: " . $circuit_id . " found in the cache");
        return;
    }
    
    switch($action){
	case (FWDCTL_ADD_VLAN){
	    return $self->{'ckts'}->{$circuit_id}->{'flows'}->{'current'};
	    
	}case (FWDCTL_REMOVE_VLAN){
	    
            return $self->{'ckts'}->{$circuit_id}->{'flows'}->{'current'};
	    
	}case (FWDCTL_CHANGE_PATH){
	    
            my @commands;

	    my $primary_flows = $self->{'ckts'}->{$circuit_id}->{'flows'}->{'endpoint'}->{'primary'};
	    my $backup_flows =  $self->{'ckts'}->{$circuit_id}->{'flows'}->{'endpoint'}->{'backup'};
	    
            #we already performed the DB change so that means
            #whatever path is active is actually what we are moving to
	    foreach my $flow (@$primary_flows){
		if($self->{'ckts'}->{$circuit_id}->{'details'}->{'active_path'} eq 'primary'){
		    $flow->{'sw_act'} = FWDCTL_REMOVE_RULE;
		}else{
		    $flow->{'sw_act'} = FWDCTL_ADD_RULE;
		}
		push(@commands,$flow);
	    }
	    
	    foreach my $flow (@$backup_flows){
		if($self->{'ckts'}->{$circuit_id}->{'details'}->{'active_path'} eq 'primary'){
		    $flow->{'sw_act'} = FWDCTL_ADD_RULE;
		}else{
		    $flow->{'sw_act'} = FWDCTL_REMOVE_RULE;
		}
		push(@commands,$flow);
	    }
	    
	    return \@commands;
	}else{

        }
    }
}

=head2 force_sync

=cut

sub force_sync{
    my $self = shift;

    $self->_update_cache();
    $self->{'needs_diff'} = 1;

    return FWDCTL_SUCCESS;

}

=head2 process_event

=cut

sub process_event{
    my $self = shift;
    my $message = shift;
    
    $self->{'logger'}->debug("Processing Event");
    
    switch ($message->{'action'}){
        case 'echo'{
            return {success => 1, msg => "I'm alive!", total_rules => $self->{'flows'}};
        }case 'datapath_join'{
            $self->datapath_join_handler();
            return {success => 1, msg => "default drop/forward installed, diffing scheduled", total_rules => $self->{'flows'}};
        }case 'change_path'{
            my $res = $self->change_path($message->{'circuits'});
            $res->{'total_rules'} = $self->{'flows'};
            return $res;
        }case 'add_vlan'{
            my $res = $self->add_vlan($message->{'circuit'});
            $res->{'total_rules'} = $self->{'flows'};
            return $res;
        }case 'remove_vlan'{
            my $res = $self->remove_vlan($message->{'circuit'});
            $res->{'total_rules'} = $self->{'flows'};
            return $res;
        }case 'force_sync'{
            $self->_update_cache();
            $self->{'logger'}->warn("received a force_sync command");
            $self->{'needs_diff'} = 1;
            return {success => 1, msg => "diff scheduled!", total_rules => $self->{'flows'}};
        }case 'update_cache'{
            $self->_update_cache();
            return {success => 1, msg => "cache updated", total_rules => $self->{'flows'}};
        }else{
            $self->{'logger'}->error("Received unsupported action type: " . $message->{'action'} . " continuing");
            return {success => 0, msg => "unsupported event", total_rules => $self->{'flows'}};
        }
    }
}

=head2 change_path

=cut

sub change_path{
    my $self = shift;
    my $circuits = shift;
    
    $self->_update_cache();
    
    my $res = FWDCTL_SUCCESS;
   
    foreach my $circuit (@$circuits){
        
        my $commands = $self->_generate_commands($circuit,FWDCTL_CHANGE_PATH);

        foreach my $command (@$commands){
            next unless defined($command);
            next unless ($command->get_dpid() == $self->{'dpid'});
            
            if($command->{'sw_act'} == FWDCTL_REMOVE_RULE){
                
                $self->{'logger'}->info("Removing Flow: " . $command->to_human());
                $self->{'nox'}->delete_datapath_flow($command->to_dbus());
                $self->{'flows'}--;
                
            }elsif($command->{'sw_act'} == FWDCTL_ADD_RULE){
                
                if($self->{'flows'} < $self->{'node'}->{'max_flows'}){
                    $self->{'logger'}->info("Installing Flow: " . $command->to_human());
                    $self->{'nox'}->install_datapath_flow($command->to_dbus());
                }else{
                    $self->{'logger'}->error("Node: " . $self->{'node'}->{'name'} . " is at or over its maximum flow mod limit, unable to send flow rule for circuit: " . $circuit);
                    $res = FWDCTL_FAILURE;
                }
            }else{
                $self->{'logger'}->error("Invalid Switch action: " . $command->{'sw_act'} . " in flow rule");
                $res = FWDCTL_FAILURE;
            }
            #if not doing bulk barrier send a barrier and wait
            if(!$self->{'node'}->{'send_barrier_bulk'}){
                $self->{'logger'}->info("Sending Barrier for node: " . $self->{'dpid'});
                $self->{'nox'}->send_barrier(Net::DBus::dbus_uint64($self->{'dpid'}));
                my $result = $self->_poll_node_status();
                if($result != FWDCTL_SUCCESS){
                    $res = FWDCTL_FAILURE;
                }
            }    
        }
    }

    #send our final barrier and wait for reply
    $self->{'logger'}->info("Sending Barrier for node: " . $self->{'dpid'});
    $self->{'nox'}->send_barrier(Net::DBus::dbus_uint64($self->{'dpid'}));
    my $result = $self->_poll_node_status();
    if($result != FWDCTL_SUCCESS){
        $res = FWDCTL_FAILURE;
    }

    if($res == FWDCTL_SUCCESS){
        return {success => 1, msg => "All Circuits successfully changed path"};
    }else{
        return {success => 0, msg => "Some circuits failed to change path"};
    }
        
    
}

=head2 add_vlan

=cut

sub add_vlan{
    my $self = shift;
    my $circuit = shift;

    $self->_update_cache();

    my $commands = $self->_generate_commands($circuit,FWDCTL_ADD_VLAN);
    
    my $res = FWDCTL_SUCCESS;

    foreach my $command (@$commands){
        
        if($self->{'flows'} < $self->{'node'}->{'max_flows'}){
            $self->{'logger'}->info("Installing Flow: " . $command->to_human());

            $self->{'nox'}->install_datapath_flow($command->to_dbus());
            $self->{'flows'}++;
            
            
        }else{
 
           $self->{'logger'}->error("Node: " . $self->{'node'}->{'name'} . " is at or over its maximum flow mod limit, unable to send flow rule for circuit: " . $circuit);
            $res = FWDCTL_FAILURE;

        }

        #if not doing bulk barrier send a barrier and wait
        if(!$self->{'node'}->{'send_barrier_bulk'}){
            $self->{'logger'}->info("Sending Barrier for node: " . $self->{'dpid'});
            $self->{'nox'}->send_barrier(Net::DBus::dbus_uint64($self->{'dpid'}));
            my $result = $self->_poll_node_status();
            if($result != FWDCTL_SUCCESS){
                $res = FWDCTL_FAILURE;
            }
        }

    }

    #send our final barrier and wait for reply
    $self->{'logger'}->info("Sending Barrier for node: " . $self->{'dpid'});
    $self->{'nox'}->send_barrier(Net::DBus::dbus_uint64($self->{'dpid'}));
    my $result = $self->_poll_node_status();
    if($result != FWDCTL_SUCCESS){
        $res = FWDCTL_FAILURE;
    }

    if($res == FWDCTL_SUCCESS){
        return {success => 1, msg => "Successfully added flows for circuit: $circuit"};
    }else{
        return {success => 0, msg => "Failed to add flows for circuit: $circuit"};
    }

}

=head2 remove_vlan

=cut

sub remove_vlan{
    my $self = shift;
    my $circuit = shift;

    $self->_update_cache();

    my $commands = $self->_generate_commands($circuit,FWDCTL_REMOVE_VLAN);
    
    my $res = FWDCTL_SUCCESS;

    foreach my $command (@$commands){

        $self->{'logger'}->info("Removing Flow: " . $command->to_human());
        $self->{'nox'}->delete_datapath_flow($command->to_dbus());
        $self->{'flows'}--;
        
        #if not doing bulk barrier send a barrier and wait
        if(!$self->{'node'}->{'send_barrier_bulk'}){
            $self->{'logger'}->info("Sending Barrier for node: " . $self->{'dpid'});
            $self->{'nox'}->send_barrier(Net::DBus::dbus_uint64($self->{'dpid'}));
            my $result = $self->_poll_node_status();
            if($result != FWDCTL_SUCCESS){
                $res = FWDCTL_FAILURE;
            }
        }

    }    

    #send our final barrier and wait for reply
    $self->{'logger'}->info("Sending Barrier for node: " . $self->{'dpid'});
    $self->{'nox'}->send_barrier(Net::DBus::dbus_uint64($self->{'dpid'}));
    my $result = $self->_poll_node_status();
    if($result != FWDCTL_SUCCESS){
        $res = FWDCTL_FAILURE;
    }

    if($res == FWDCTL_SUCCESS){
        return {success => 1, msg => "Successfully removed flows for: $circuit"};
    }else{
        return {success => 0, msg => "Failed to remove flows for circuit: $circuit"};
    }
    
}

=head2 datapath_join_handler

=cut

sub datapath_join_handler{
    my $self   = shift;
    
    #--- first push the default "forward to controller" rule to this node. This enables
    #--- discovery to work properly regardless of whether the switch's implementation does it by default
    #--- or not
    $self->{'logger'}->info("sw:" . $self->{'node'}->{'name'} . " dpid:" . $self->{'node'}->{'dpid_str'} . " datapath join");
    
    my %xid_hash;
    
    if(!defined($self->{'node'} || $self->{'node'}->{'default_forward'} == 1)) {
        my $status = $self->{'nox'}->install_default_forward(Net::DBus::dbus_uint64($self->{'dpid'}),$self->{'data'}->{'settings'}->{'discovery_vlan'});
	$self->{'flows'}++;
    }
    
    if (!defined($self->{'node'}) || $self->{'node'}->{'default_drop'} == 1) {
        my $status = $self->{'nox'}->install_default_drop(Net::DBus::dbus_uint64($self->{'dpid'}));
        #this actually installs 2 flows now
        $self->{'flows'}++;
        $self->{'flows'}++;
    }
    $self->{'logger'}->info("Sending Barrier for node: " . $self->{'dpid'});
    my $xid = $self->{'nox'}->send_barrier(Net::DBus::dbus_uint64($self->{'dpid'}));
    my $result = $self->_poll_node_status();
    
    if ($result != FWDCTL_SUCCESS) {
        $self->{'logger'}->error("sw:" . $self->{'node'}->{'name'} . " dpid:" . $self->{'node'}->{'dpid_str'} . " failed to install default drop or lldp forward rules, may cause traffic to flood controller or discovery to fail");
        return;
    } else {
        $self->{'logger'}->info("sw:" . $self->{'node'}->{'name'} . " dpid:" . $self->{'node'}->{'dpid_str'} ." installed default drop rule and lldp forward rule");
    }
    
    $self->{'needs_diff'} = 1;
    
}

sub _replace_flowmod{
    my $self = shift;
    my $commands = shift;

    if (!defined($commands->{'remove'}) && !defined($commands->{'add'})) {
        return undef;
    }

    my $state = FWDCTL_SUCCESS;

    if (defined($commands->{'remove'})) {
        #delete this flowmod
	$self->{'logger'}->info("Deleting flow: " . $commands->{'remove'}->to_human());
	my $status = $self->{'nox'}->delete_datapath_flow($commands->{'remove'}->to_dbus());

	if(!$self->{'node'}->{'send_barrier_bulk'}){
	    my $xid = $self->{'nox'}->send_barrier(Net::DBus::dbus_uint64($commands->{'remove'}->get_dpid()));
	    $self->{'logger'}->debug("replace flowmod: send_barrier: with dpid: " . $commands->{'remove'}->get_dpid());
            my $res = $self->_poll_node_status();
            if($res != FWDCTL_SUCCESS){
                $state = FWDCTL_FAILURE;
            }
	}
        $self->{'flows'}--;
    }
    
    if (defined($commands->{'add'})) {
        if ( $self->{'flows'} >= $self->{'node'}->{'max_flows'}){
            $self->{'logger'}->error("sw: dpipd:" . $self->{'node'}->{'dpid_str'} . " exceeding max_flows:". $self->{'node'}->{'max_flows'} ." replace flowmod failed");
            return FWDCTL_FAILURE;
        }
	$self->{'logger'}->trace("Flow: " . Data::Dumper::Dumper($commands->{'add'}));
	$self->{'logger'}->info("Installing Flow: " . $commands->{'add'}->to_human());
        my $status = $self->{'nox'}->install_datapath_flow($commands->{'add'}->to_dbus());
	
        # send the barrier if the bulk flag is not set
        if (!$self->{'node'}->{'send_barrier_bulk'}) {
            $self->{'logger'}->info("Sending Barrier for node: " . $self->{'dpid'});
            my $xid = $self->{'nox'}->send_barrier(Net::DBus::dbus_uint64($commands->{'add'}->get_dpid()));
            $self->{'logger'}->error("replace flowmod: send_barrier: with dpid: " . $commands->{'add'}->get_dpid());
            my $res = $self->_poll_node_status();
            if($res != FWDCTL_SUCCESS){
                $state = FWDCTL_FAILURE;
            }
        }	
        $self->{'flows'}++;
    }
    
    return $state;
}

sub _do_diff{
    my $self = shift;
    my $current_flows = shift;

    my $dpid          = $self->{'dpid'};
    my $dpid_str      = sprintf("%x",$dpid);
    my $node_info     = $self->{'node'};
    my $sw_name       = $node_info->{'name'};


    $self->{'logger'}->info("sw:$sw_name dpid:$dpid_str diff sw rules to oe-ss rules");
    #--- get the set of circuits

    #--- process each ckt
    my @all_commands;
    foreach my $circuit_id (keys %{ $self->{'ckts'} }){
        next unless ($self->{'ckts'}->{$circuit_id}->{'details'}->{'state'} eq 'active' || 
                     $self->{'ckts'}->{$circuit_id}->{'details'}->{'state'} eq 'deploying');
        #--- get the set of commands needed to create this vlan per design
        my $commands = $self->_generate_commands($circuit_id,FWDCTL_ADD_VLAN);
        foreach my $command (@$commands) {
            push(@all_commands,$command);
        }
    }

    if (!defined($node_info) || $node_info->{'default_forward'} == 1) {
	if(defined($self->{'settings'}->{'discovery_vlan'}) && $self->{'settings'}->{'discovery_vlan'} != -1){
	    push(@all_commands,OESS::FlowRule->new( dpid => $dpid,
						    match => {'dl_type' => 35020,
							      'dl_vlan' => $self->{'settings'}->{'discovery_vlan'}},
						    actions => [{'output' => 65533}]));

	    push(@all_commands,OESS::FlowRule->new( dpid => $dpid,
						    match => {'dl_type' => 34998,
							      'dl_vlan' => $self->{'settings'}->{'discovery_vlan'}},
						    actions => [{'output' => 65533}]));
	}else{
	    push(@all_commands,OESS::FlowRule->new( dpid => $dpid,
						    match => {'dl_type' => 35020,
							      'dl_vlan' => -1},
						    actions => [{'output' => 65533}]));
	    
	    push(@all_commands,OESS::FlowRule->new( dpid => $dpid,
                                                    match => {'dl_type' => 34998,
							      'dl_vlan' => -1},
                                                    actions => [{'output' => 65533}]));
	}
    }
    
    #start at one for the default drop
    $self->{'flows'} = 1;

    return $self->_actual_diff($current_flows, \@all_commands);
}


sub _actual_diff{
    my $self = shift;
    my $current_flows = shift;
    my $commands = shift;

    $self->{'logger'}->warn("Staring diffing process... total flows expected: " . scalar(@$commands));

    my @rule_queue;         #--- temporary storage of forwarding rules
    my %stats = (
                 mods => 0,
                 adds => 0,
                 rems => 0
                );             #--- used to store stats about the diff

    foreach my $command (@$commands) {
        #---ignore rules not for this dpid
        $self->{'logger'}->debug("Checking to see if " . $command->to_human() . " is on device");
        next if($command->get_dpid() != $self->{'dpid'});
	my $found = 0;
        my $match = $command->get_match();

        if(defined($current_flows->{$match->{'in_port'}}->{$match->{'dl_vlan'}})){
            $self->{'logger'}->debug("Found flows for this match/vlan: " . Data::Dumper::Dumper($match));
            for(my $i=0;$i<= $#{$current_flows->{$match->{'in_port'}}->{$match->{'dl_vlan'}}}; $i++){
                my $flow = $current_flows->{$match->{'in_port'}}->{$match->{'dl_vlan'}}->[$i];
                $self->{'logger'}->debug("Comparing to: " . $flow->to_human());
                if($command->compare_match( flow_rule =>  $flow)){
                    $self->{'logger'}->debug("Match matches!");
                    $found = 1;
                    if($command->compare_actions( flow_rule => $flow)){
                        #we found a matching flow! sweet do nothing!
                        $self->{'logger'}->debug("it matches doing nothing");
                        $self->{'flows'}++;
                        delete $current_flows->{$match->{'in_port'}}->{$match->{'dl_vlan'}}->[$i];
                    }else{
                        #the matches match but the actions do not... replace
                        $self->{'logger'}->debug("replacing with new flow");
                        $stats{'mods'}++;
                        $self->{'flows'}++;
                        push(@rule_queue,{remove => $flow, add => $command});
                        delete $current_flows->{$match->{'in_port'}}->{$match->{'dl_vlan'}}->[$i];
                    }
                }
            }
        }

	if(!$found){
            $self->{'logger'}->debug("adding to the switch");
	    #doh... add this rule
	    $stats{'adds'}++;
	    push(@rule_queue,{add => $command});
	}
    }
    
    $self->{'logger'}->debug("Done processing rules expected...");

    #if we have any flows remaining the must be removed!
    foreach my $port (keys %{$current_flows}){
        foreach my $vlan (keys %{$current_flows->{$port}}){
            foreach my $flow (@{$current_flows->{$port}->{$vlan}}){
                next if(!defined($flow));
                $self->{'flows'}++;
                $stats{'rems'}++;
                unshift(@rule_queue,{remove => $flow});
            }
        }
    }
    
    $self->{'logger'}->debug("Done processing what shouldn't be there");

    my $total = $stats{'mods'} + $stats{'adds'} + $stats{'rems'};
    $self->{'logger'}->info("sw:" . $self->{'node'}->{'name'} . " dpid:" . $self->{'node'}->{'dpid_str'} . " diff plan $total changes.  mods:".$stats{'mods'}. " adds:".$stats{'adds'}. " removals:".$stats{'rems'});
    
    #--- process the rule_queue
    my $res = FWDCTL_SUCCESS;
    $self->{'logger'}->debug("before calling _replace_flowmod in loop with rule_queue:". @rule_queue);
    foreach my $args (@rule_queue) {
        my $new_result = $self->_replace_flowmod($args);
        if (defined($new_result) && ($new_result != FWDCTL_SUCCESS)) {
            $res = $new_result;
        }
    }

    if($self->{'node'}->{'bulk_barrier'}){
        my $xid = $self->{'nox'}->send_barrier(Net::DBus::dbus_uint64($self->{'dpid'}));
        $self->{'logger'}->info("diff barrier with dpid: " . $self->{'dpid'});
        my $result = $self->_poll_node_status();
        if($result != FWDCTL_SUCCESS){
            $res = $result;
        }
    }

    if ($res == FWDCTL_SUCCESS) {
        $self->{'logger'}->info("sw:" . $self->{'node'}->{'name'} . " dpid:" . $self->{'node'}->{'dpid_str'} . " diff completed $total changes");
    } else {
        $self->{'logger'}->error("sw:" . $self->{'node'}->{'name'} . " dpid:" . $self->{'node'}->{'dpid_str'} . " diff did not complete");
    }
    return $res;
}

=head2 rules_per_switch

=cut

sub rules_per_switch{
    my $self = shift;

    return $self->{'flows'};
}

sub _process_stats_to_flows{
    my $self = shift;
    my $dpid = shift;
    my $flows = shift;

    my %new_flows;
    foreach my $flow (@$flows){	
	my $new_flow = OESS::FlowRule::parse_stat( dpid => $dpid, stat => $flow );
        my $match = $new_flow->get_match();
        $self->{'logger'}->debug("Adding flow with match to flow hash: " . Data::Dumper::Dumper($match));
        if(!defined($new_flows{$match->{'in_port'}}{$match->{'dl_vlan'}})){
            $new_flows{$match->{'in_port'}}{$match->{'dl_vlan'}} = [];
        }
        push(@{$new_flows{$match->{'in_port'}}{$match->{'dl_vlan'}}},$new_flow);
    }

    return \%new_flows;

}

=head2 get_flow_stats

=cut

sub get_flow_stats{
    my $self = shift;

    if($self->{'needs_diff'}){
        my ($time,$stats) = $self->{'nox'}->get_flow_stats($self->{'dpid'});
	$self->{'logger'}->debug("FlowStats: " . Dumper($stats));
        if ($time == -1) {
            #we don't have flow data yet
            $self->{'logger'}->info("no flow stats cached yet for dpid: " . $self->{'dpid'});
            return;
        }
        
        $self->{'needs_diff'} = 0;
        #---process the flow_rules into a lookup hash
        my $flows = $self->_process_stats_to_flows( $self->{'dpid'}, $stats);

        #--- now that we have the lookup hash of flow_rules
        #--- do the diff
        $self->_do_diff($flows);
    }
}

sub _poll_node_status{
    my $self          = shift;

    my $result  = FWDCTL_SUCCESS;
    my $timeout = time() + 15;

    while (time() < $timeout) {
        
        my ($output,$failed_flows) = $self->{'nox'}->get_node_status(Net::DBus::dbus_uint64($self->{'dpid'}));
        $self->{'logger'}->debug($output);
        #-- pending, retry later
        $self->{'logger'}->trace("Status of node: " . $self->{'node'}->{'name'} . " DPID: " . $self->{'node'}->{'dpid_str'} . " is " . $output);
        if ($output != FWDCTL_WAITING){
            #--- one failed , some day have handler passed in hash
            $self->{'logger'}->debug("Have a response for node: " . $self->{'node'}->{'name'} . " DPID: " . $self->{'node'}->{'dpid_str'} . " and is " . $output);
            return $output;
        }
        #--- if we got here lets take a short nap
        usleep(100);
    }

    $self->{'logger'}->warn("Switch: " . $self->{'node'}->{'name'} . " DPID: " . $self->{'node'}->{'dpid_str'} . " did not respond before the timout");
    return $result;
}


1;
