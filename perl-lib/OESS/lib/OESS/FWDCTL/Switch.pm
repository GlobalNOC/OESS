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

use Log::Log4perl;
use Switch;

use AnyEvent;
use OESS::FlowRule;
use OESS::DBus;
use Net::DBus;
use JSON;

use Data::Dumper;

use Time::HiRes qw( usleep );
use constant FWDCTL_ADD_VLAN     => 0;
use constant FWDCTL_REMOVE_VLAN  => 1;
use constant FWDCTL_CHANGE_PATH  => 2;

use constant FWDCTL_ADD_RULE     => 0;
use constant FWDCTL_REMOVE_RULE  => 1;

use constant OFPFC_ADD           => 0;
use constant OFPFC_MODIFY        => 1;
use constant OFPFC_MODIFY_STRICT => 2;
use constant OFPFC_DELETE        => 3;
use constant OFPFC_DELETE_STRICT => 4;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;

$| = 1;

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

    #--- set a default discovery vlan that can be overridden later if needed.
    $self->{'settings'}->{'discovery_vlan'} = -1;

    $self->{'nox'} = $nox->{'dbus'};

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.FWDCTL.Switch.' . sprintf("%x",$self->{'dpid'}));
    $self->{'logger'}->debug("I EXIST!!!");
    bless $self, $class;

    $self->_update_cache();
    $self->datapath_join_handler();
    
    $self->{'timer'} = AnyEvent->timer( after => 10, interval => 60, 
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

    if(!-e $self->{'share_file'}){
        $self->{'logger'}->error("No Cache file exists!!!");
        return;
    }

    my $str;
    open(my $fh, "<", $self->{'share_file'});
    while(my $line = <$fh>){
        $str .= $line;
    }
    
    my $data = from_json($str);
    $self->{'logger'}->debug("Fetched data!");
    $self->{'node'} = $data->{'nodes'}->{$self->{'dpid'}};
    $self->{'settings'} = $data->{'settings'};

    foreach my $ckt (keys %{ $self->{'ckts'} }){
        delete $self->{'ckts'}->{$ckt};
    }

    foreach my $ckt (keys %{ $data->{'ckts'}}){
        $self->{'logger'}->debug("processing cache for circuit: " . $ckt);

        $self->{'ckts'}->{$ckt}->{'details'} = $data->{'ckts'}->{$ckt}->{'details'};

        foreach my $obj (@{$data->{'ckts'}->{$ckt}->{'flows'}->{'current'}}){
            next unless($obj->{'dpid'} == $self->{'dpid'});
            my $flow = OESS::FlowRule->new( match => $obj->{'match'},
                                            actions => $obj->{'actions'},
                                            dpid => $obj->{'dpid'},
                                            priority => $obj->{'priority'});
            push(@{$self->{'ckts'}->{$ckt}->{'flows'}->{'current'}},$flow);
        }

        foreach my $obj (@{$data->{'ckts'}->{$ckt}->{'flows'}->{'endpoint'}->{'primary'}}){
            next unless($obj->{'dpid'} == $self->{'dpid'});
            my $flow = OESS::FlowRule->new( match => $obj->{'match'},
                                            actions => $obj->{'actions'},
                                            dpid => $obj->{'dpid'},
                                            priority =>$obj->{'priority'});
            push(@{$self->{'ckts'}->{$ckt}->{'flows'}->{'endpoint'}->{'primary'}},$flow);
        }

        foreach my $obj (@{$data->{'ckts'}->{$ckt}->{'flows'}->{'endpoint'}->{'backup'}}){
            next unless($obj->{'dpid'} == $self->{'dpid'});
            my $flow = OESS::FlowRule->new( match => $obj->{'match'},
                                            actions => $obj->{'actions'},
                                            dpid => $obj->{'dpid'},
                                            priority =>$obj->{'priority'});
            push(@{$self->{'ckts'}->{$ckt}->{'flows'}->{'endpoint'}->{'backup'}},$flow);
        }
        

    }

    $self->{'node'} = $data->{'nodes'}->{$self->{'dpid'}};

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.FWDCTL.Switch.' . $self->{'node'}->{'name'}) if($self->{'node'}->{'name'});

    $self->{'settings'} = $data->{'settings'};

}

sub _generate_commands {
    my $self       = shift;
    my $circuit_id = shift;
    my $action     = shift;
    
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
            #we already performed the DB change so that means
            #whatever path is active is actually what we are moving to
            my $active_path     = $self->{'ckts'}{$circuit_id}{'details'}{'active_path'};
            my $endpoint_flows  = $self->{'ckts'}{$circuit_id}{'flows'}{'endpoint'}{$active_path};

            return $endpoint_flows;
        }else{

        }
    }
}

=head2 force_sync

=cut

sub force_sync{
    my $self = shift;

    $self->_update_cache();
    $self->{'needs_diff'} = time();

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
            $self->{'needs_diff'} = time();
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
        
        my $commands    = $self->_generate_commands($circuit,FWDCTL_CHANGE_PATH);
        my $active_path = $self->{'ckts'}{$circuit}{'details'}{'active_path'};

        foreach my $command (@$commands){
            next unless defined($command);
            next unless ($command->get_dpid() == $self->{'dpid'});
            $self->{'logger'}->info("Modifying endpoint flow to $active_path path: " . $command->to_human());
            $self->{'nox'}->send_datapath_flow($command->to_dbus( command => OFPFC_MODIFY ));

            #if not doing bulk barrier send a barrier and wait
            if(!$self->{'node'}->{'send_barrier_bulk'}){
                $self->{'logger'}->info("Sending Barrier for node: " . $self->{'dpid'});
                $self->{'nox'}->send_barrier(Net::DBus::dbus_uint64($self->{'dpid'}));
                #assume failure , use diff to be resilient to failure
                $self->{'needs_diff'} = time();
                
                my $result = $self->_poll_node_status();
                if($result != FWDCTL_SUCCESS){
                    $res = FWDCTL_FAILURE;
                }
            }
            
            usleep($self->{'node'}->{'tx_delay_ms'} * 1000);
        }
    }

    #send our final barrier and wait for reply
    $self->{'logger'}->info("Sending Barrier for node: " . $self->{'dpid'});
    $self->{'nox'}->send_barrier(Net::DBus::dbus_uint64($self->{'dpid'}));
    #assume failure , use diff to be resilient to failure
    $self->{'needs_diff'} = time();
    my $result = $self->_poll_node_status();
    if($result != FWDCTL_SUCCESS){
        $res = FWDCTL_FAILURE;
    }

    if($res == FWDCTL_SUCCESS){
        return {success => 1, msg => "All circuits successfully changed path"};
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

            $self->{'nox'}->send_datapath_flow($command->to_dbus( command => OFPFC_ADD ));
            $self->{'flows'}++;
                        
        }else{
 
            $self->{'logger'}->error("Node: " . $self->{'node'}->{'name'} . " is at or over its maximum flow mod limit, unable to send flow rule for circuit: " . $circuit);
            $res = FWDCTL_FAILURE;
            
        }

        #if not doing bulk barrier send a barrier and wait
        if(!$self->{'node'}->{'send_barrier_bulk'}){
            $self->{'logger'}->info("Sending Barrier for node: " . $self->{'dpid'});
            $self->{'nox'}->send_barrier(Net::DBus::dbus_uint64($self->{'dpid'}));
            #assume failure , use diff to be resilient to failure
            $self->{'needs_diff'} = time();
            my $result = $self->_poll_node_status();
            if($result != FWDCTL_SUCCESS){
                $res = FWDCTL_FAILURE;
            }
        }
        usleep($self->{'node'}->{'tx_delay_ms'} * 1000);
    }

    #send our final barrier and wait for reply
    $self->{'logger'}->info("Sending Barrier for node: " . $self->{'dpid'});
    $self->{'nox'}->send_barrier(Net::DBus::dbus_uint64($self->{'dpid'}));
    #assume failure , use diff to be resilient to failure
    $self->{'needs_diff'} = time();
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
        $self->{'nox'}->send_datapath_flow($command->to_dbus( command => OFPFC_DELETE_STRICT ));
        $self->{'flows'}--;
        
        #if not doing bulk barrier send a barrier and wait
        if(!$self->{'node'}->{'send_barrier_bulk'}){
            $self->{'logger'}->info("Sending Barrier for node: " . $self->{'dpid'});
            $self->{'nox'}->send_barrier(Net::DBus::dbus_uint64($self->{'dpid'}));
            #assume failure , use diff to be resilient to failure
            $self->{'needs_diff'} = time();
            my $result = $self->_poll_node_status();
            if($result != FWDCTL_SUCCESS){
                $res = FWDCTL_FAILURE;
            }
        }

        usleep($self->{'node'}->{'tx_delay_ms'} * 1000);

    }    

    #send our final barrier and wait for reply
    $self->{'logger'}->info("Sending Barrier for node: " . $self->{'dpid'});
    $self->{'nox'}->send_barrier(Net::DBus::dbus_uint64($self->{'dpid'}));
    #assume failure , use diff to be resilient to failure
    $self->{'needs_diff'} = time();
    my $result = $self->_poll_node_status();
    $self->{'logger'}->info("Got a barrier reply");
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
    
    if(!defined($self->{'node'}->{'default_forward'}) || $self->{'node'}->{'default_forward'} == 1) {
        my $status;

        #--- make sure there is a discovery vlan set. else send -1.
        if($self->{'settings'}->{'discovery_vlan'}){ 
            $self->{'logger'}->info("sw:" . $self->{'node'}->{'name'} . " dpid:" . $self->{'node'}->{'dpid_str'} ." pushing lldp forwarding rule for vlan $self->{'settings'}->{'discovery_vlan'}");
            $status = $self->{'nox'}->install_default_forward(Net::DBus::dbus_uint64($self->{'dpid'}),$self->{'settings'}->{'discovery_vlan'});
        }
        else{
            $self->{'logger'}->info("sw:" . $self->{'node'}->{'name'} . " dpid:" . $self->{'node'}->{'dpid_str'} ." pushing lldp forwarding rule for vlan -1");
            $status = $self->{'nox'}->install_default_forward(Net::DBus::dbus_uint64($self->{'dpid'}),-1);
        }

        $self->{'flows'}++;
    }

    if (!defined($self->{'node'}->{'default_drop'}) || $self->{'node'}->{'default_drop'} == 1) {
        $self->{'logger'}->info("sw:" . $self->{'node'}->{'name'} . " dpid:" . $self->{'node'}->{'dpid_str'} ." pushing default drop rule");
        my $status = $self->{'nox'}->install_default_drop(Net::DBus::dbus_uint64($self->{'dpid'}));
        $self->{'flows'}++;
    }
    $self->{'logger'}->info("Sending Barrier for node: " . $self->{'dpid'});
    my $xid = $self->{'nox'}->send_barrier(Net::DBus::dbus_uint64($self->{'dpid'}));

    my $result = $self->_poll_node_status();
    
    if ($result != FWDCTL_SUCCESS) {
        $self->{'logger'}->error("sw:" . $self->{'node'}->{'name'} . " dpid:" . $self->{'node'}->{'dpid_str'} . " failed to install default drop or lldp forward rules, may cause traffic to flood controller or discovery to fail");
    } else {
        $self->{'logger'}->info("sw:" . $self->{'node'}->{'name'} . " dpid:" . $self->{'node'}->{'dpid_str'} ." installed default drop rule and lldp forward rule");
    }
    
    $self->{'needs_diff'} = time();
    
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
        my $status = $self->{'nox'}->send_datapath_flow($commands->{'remove'}->to_dbus( command => OFPFC_DELETE_STRICT ));

        if(!$self->{'node'}->{'send_barrier_bulk'}){
            my $xid = $self->{'nox'}->send_barrier(Net::DBus::dbus_uint64($commands->{'remove'}->get_dpid()));
            $self->{'logger'}->debug("replace flowmod: send_barrier: with dpid: " . $commands->{'remove'}->get_dpid());
            #assume failure , use diff to be resilient to failure
            $self->{'needs_diff'} = time();
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
	    $self->{'logger'}->info("Installing Flow: " . $commands->{'add'}->to_human());
        my $status = $self->{'nox'}->send_datapath_flow($commands->{'add'}->to_dbus( command => OFPFC_ADD ));
	
        # send the barrier if the bulk flag is not set
        if (!$self->{'node'}->{'send_barrier_bulk'}) {
            $self->{'logger'}->info("Sending Barrier for node: " . $self->{'dpid'});
            my $xid = $self->{'nox'}->send_barrier(Net::DBus::dbus_uint64($commands->{'add'}->get_dpid()));
            #assume failure , use diff to be resilient to failure
            $self->{'needs_diff'} = time();
            $self->{'logger'}->error("replace flowmod: send_barrier: with dpid: " . $commands->{'add'}->get_dpid());
            my $res = $self->_poll_node_status();
            if($res != FWDCTL_SUCCESS){
                $state = FWDCTL_FAILURE;
            }
        }	
        $self->{'flows'}++;
    }
    usleep($self->{'node'}->{'tx_delay_ms'} * 1000 );
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

    if (!defined($node_info->{'default_forward'}) || $node_info->{'default_forward'} == 1) {
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
    
    #start at one for the default drop and the fvd
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
            for(my $i=0;$i<= $#{$current_flows->{$match->{'in_port'}}->{$match->{'dl_vlan'}}}; $i++){
                my $flow = $current_flows->{$match->{'in_port'}}->{$match->{'dl_vlan'}}->[$i];
                next if(!defined($flow));
                $self->{'logger'}->debug("Comparing to: " . $flow->to_human());
                        #skip diffing traceroute related flowrules
                
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
    
    if ($total == 0){
        $self->{'logger'}->info("sw:" . $self->{'node'}->{'name'} . " dpid:" . $self->{'node'}->{'dpid_str'} ."has 0 changes, returning FWDCTL_SUCCESS" );
        $self->{'needs_diff'} = 0;
        return FWDCTL_SUCCESS;
    }
    #--- process the rule_queue
    my $res = FWDCTL_SUCCESS;
    $self->{'logger'}->debug("before calling _replace_flowmod in loop with rule_queue:". @rule_queue);
    foreach my $args (@rule_queue) {
        my $new_result = $self->_replace_flowmod($args);
        if (defined($new_result) && ($new_result != FWDCTL_SUCCESS)) {
            $res = $new_result;
        }
        usleep($self->{'node'}->{'tx_delay_ms'} * 1000);
    }

    if($self->{'node'}->{'bulk_barrier'}){
        my $xid = $self->{'nox'}->send_barrier(Net::DBus::dbus_uint64($self->{'dpid'}));
        $self->{'logger'}->info("diff barrier with dpid: " . $self->{'dpid'});
        my $result = $self->_poll_node_status();
        $self->{'logger'}->debug("node_status");
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
        #Allow Traceroute to manage its own flow rules
        if ($match->{'dl_type'} && $match->{'dl_type'} == 34997){
                    next;
        }
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
        if ($time == -1) {
            #we don't have flow data yet
            $self->{'logger'}->info("no flow stats cached yet for dpid: " . $self->{'dpid'});
            return;
        }

        if($time > $self->{'needs_diff'}){
            #$self->{'needs_diff'} = 0;
            #---process the flow_rules into a lookup hash
            my $flows = $self->_process_stats_to_flows( $self->{'dpid'}, $stats);
            
            #--- now that we have the lookup hash of flow_rules
            #--- do the diff
            $self->_do_diff($flows);
        }
    }
}

sub _poll_node_status{
    my $self          = shift;

    my $result  = FWDCTL_SUCCESS;
    my $timeout = time() + 15;

    while (time() < $timeout) {
        
        my ($output,$failed_flows) = $self->{'nox'}->get_node_status(Net::DBus::dbus_uint64($self->{'dpid'}));
        $self->{'logger'}->debug("poll node status output: $output");
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
    
    $result = FWDCTL_UNKNOWN;
    $self->{'logger'}->warn("Switch: " . $self->{'node'}->{'name'} . " DPID: " . $self->{'node'}->{'dpid_str'} . " did not respond before the timout");
    return $result;
}


1;
