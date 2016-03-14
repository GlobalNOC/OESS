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

use GRNOC::WebService::Regex;
use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;
use GRNOC::RabbitMQ::Client;
use OESS::FlowRule;
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
    
    my $self = \%args;

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.FWDCTL.Switch.' . sprintf("%x",$self->{'dpid'}));

    my $ar = GRNOC::RabbitMQ::Client->new( host => $args{'rabbitMQ_host'},
					   port => $args{'rabbitMQ_port'},
					   user => $args{'rabbitMQ_user'},
					   pass => $args{'rabbitMQ_pass'},
					   topic => 'OF.NOX.RPC',
					   exchange => 'OESS');
    $self->{'rabbit_mq'} = $ar;
    
    my $topic = 'OF.FWDCTL.Switch.' . sprintf("%x", $self->{'dpid'});

    $self->{'logger'}->error("Listening to topic: " . $topic);

    my $dispatcher = GRNOC::RabbitMQ::Dispatcher->new( host => $args{'rabbitMQ_host'},
						       port => $args{'rabbitMQ_port'},
						       user => $args{'rabbitMQ_user'},
						       pass => $args{'rabbitMQ_pass'},
						       topic => $topic,
						       queue => $topic,
						       exchange => 'OESS');

    my $method = GRNOC::RabbitMQ::Method->new( name => "add_vlan",
					       async => 1,
					       description => "adds a vlan for this switch",
					       callback => sub { $self->add_vlan(@_) }	);

    $method->add_input_parameter( name => "circuit_id",
                                  description => "circuit_id to be added",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::NUMBER_ID);

    $dispatcher->register_method($method);
    
    $method = GRNOC::RabbitMQ::Method->new( name => "remove_vlan",
					    async => 1,
					    description => "removes a vlan for this switch",
					    callback => sub { $self->remove_vlan(@_) }     );
    
    $method->add_input_parameter( name => "circuit_id",
                                  description => "circuit_id to be removed",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::NUMBER_ID);



    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => "change_path",
					    description => "changes the path on the specified circuits",
					    callback => sub { $self->change_path(@_) }     );
    
    $method->add_input_parameter( name => "circuit_id",
                                  description => "The message and paramteres to be run by the child",
                                  required => 1,
				  multiple => 1,
				  async => 1,
                                  pattern => $GRNOC::WebService::Regex::NUMBER_ID);


    $dispatcher->register_method($method);


    $method = GRNOC::RabbitMQ::Method->new( name => "echo",
					    description => " just an echo to check to see if we are aliave",
					    callback => sub { return {status => 1, msg => "I'm alive!", total_rules => $self->{'flows'}}});

    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => "datapath_join",
                                            description => " handle datapath join event",
					    callback => sub { $self->datapath_join_handler(); return {status => 1, msg => "default drop/forward installed, diffing scheduled", total_rules => $self->{'flows'}}});

    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => "force_sync",
                                            description => " handle force_sync event",
					    callback => sub { $self->{'logger'}->warn("received a force_sync command");
							      $self->_update_cache();
							      $self->{'needs_diff'} = time();
							      return {status => 1, msg => "diff scheduled!", total_rules => $self->{'flows'}}; });

    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => "update_cache",
                                            description => " handle thes update cahce call",
                                            callback => sub { $self->_update_cache();
							      return {status => 1, msg => "cache updated", total_rules => $self->{'flows'}}});

    $dispatcher->register_method($method);

    #--- set a default discovery vlan that can be overridden later if needed.
    $self->{'settings'}->{'discovery_vlan'} = -1;

    bless $self, $class;

    $self->_update_cache();
    $self->datapath_join_handler();
    
    $self->{'timer'} = AnyEvent->timer( after => 10, interval => 60, 
                                        cb => sub { 
                                            $self->{'logger'}->debug("Processing FlowStat Timer event");
                                            $self->get_flow_stats();
                                        } );

    $self->{'logger'}->error("Switch process: " . $self->{'dpid'} . " is ready to go!");

    AnyEvent->condvar->recv;
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
        $ckt = int($ckt);
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
    my $m_ref = shift;
    my $p_ref = shift;


    my $circuits = $p_ref->{'circuit_id'}{'value'};
    
    $self->_update_cache();
    
    my @pending_commands;

    foreach my $circuit (@$circuits){
        
        my $commands    = $self->_generate_commands($circuit,FWDCTL_CHANGE_PATH);
        my $active_path = $self->{'ckts'}{$circuit}{'details'}{'active_path'};

        foreach my $command (@$commands){
            next unless defined($command);
            next unless ($command->get_dpid() == $self->{'dpid'});
            $self->{'logger'}->info("Modifying endpoint flow to $active_path path: " . $command->to_human());
	    push(@pending_commands, $command);
	}
    }


    $self->send_flows( flows => \@pending_commands,
		       command => OFPFC_MODIFY_STRICT,
		       cb => sub {
			   $self->{'rabbit_mq'}->send_barrier( dpid => int($self->{'dpid'}),
							       async_callback => sub {
								   $self->get_node_status( $m_ref->{'success_callback'} )
							       });
		       });
    
    
    
}

=head2 add_vlan

=cut

sub add_vlan{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    $self->{'logger'}->debug("in add_vlan");

    my $circuit = $p_ref->{'circuit_id'}{'value'};

    $self->{'logger'}->debug("Adding VLAN: " . Data::Dumper::Dumper($p_ref));

    $self->_update_cache();

    my $commands = $self->_generate_commands($circuit,FWDCTL_ADD_VLAN);
    
    my $res = FWDCTL_SUCCESS;

    $self->send_flows( flows => $commands,
                       command => OFPFC_ADD,
                       cb => sub {
                           $self->{'rabbit_mq'}->send_barrier( dpid => int($self->{'dpid'}),
                                                               async_callback => sub {
                                                                   $self->get_node_status( $m_ref->{'success_callback'} )
                                                               });
                       });

}

=head2 send_flows

=cut

sub send_flows{
    my $self = shift;
    my %params = @_;

    my $flows = $params{'flows'};
    my $cmd = $params{'command'};
    my $cb = $params{'cb'};

    if(scalar(@$flows) == 0){
	&$cb();
	return;
    }
    
    usleep($self->{'node'}->{'tx_delay_ms'} * 1000);
    
    #pull off the first flow...
    my $flow = shift(@$flows);


    if($cmd == OFPFC_ADD){
	$self->{'flows'}++;
    }elsif($cmd == OFPFC_DELETE_STRICT || $cmd == OFPFC_DELETE){
	$self->{'flows'}--;
    }else{
	#must be modify, in other words no del/or add
    }
    
    if($self->{'flows'} > $self->{'node'}->{'max_flows'}){
	$self->{'logger'}->error("Switch is currently at configured flow limit! Unable to install flows");
	&$cb({status => 0, error => "Switch is at flow limit"});
	return;
    }

    if($self->{'node'}->{'send_barrier_bulk'}){
	$self->{'rabbit_mq'}->send_datapath_flow(flow => $flow->to_dict( command => $cmd),
						 async_callback => sub { $self->send_flows( flows => $flows,
											    command => $cmd,
											    cb => $cb); });

    }else{
	
	$self->{'rabbit_mq'}->send_datapath_flow(flow => $flow->to_dict( command => $cmd),
						 async_callback => sub { 
						     $self->{'rabbit_mq'}->send_barrier( dpid => int($self->{'dpid'}),
											 async_callback => sub {
											     $self->get_node_status( sub{ $self->send_flows( flows => $flows,
																	     command => $cmd,
																	     cb => $self->send_flows( flows => $flows,
																				      cb => $cb,
																				      command => $cmd))
														     })
											 })
						 });

    }
    

}

=head2 remove_vlan

=cut

sub remove_vlan{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    $self->{'logger'}->debug("in remove_vlan");

    my $circuit = $p_ref->{'circuit_id'}{'value'};

    $self->{'logger'}->debug("Removing VLAN: " . Data::Dumper::Dumper($p_ref));

    $self->_update_cache();

    my $commands = $self->_generate_commands($circuit,FWDCTL_REMOVE_VLAN);
    
    $self->send_flows( flows => $commands,
		       commnad => OFPFC_DELETE_STRICT,
		       cb => sub {
			   $self->{'rabbit_mq'}->send_barrier( dpid => int($self->{'dpid'}),
							       async_callback => sub {
								   $self->get_node_status( $m_ref->{'success_callback'} )
							       });
		       });    
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

    if (!defined($self->{'node'}->{'default_drop'}) || $self->{'node'}->{'default_drop'} == 1) {
        $self->{'logger'}->info("sw:" . $self->{'node'}->{'name'} . " dpid:" . $self->{'node'}->{'dpid_str'} ." pushing default drop rule");
        $self->{'rabbit_mq'}->install_default_drop( dpid => int($self->{'dpid'}),
						    async_callback => sub{ $self->{'flows'}++} );
    }
    
    if(!defined($self->{'node'}->{'default_forward'}) || $self->{'node'}->{'default_forward'} == 1) {
        my $status;
	
	my $discovery_vlan = -1;
	if(defined($self->{'settings'}->{'discovery_vlan'})){
	    $discovery_vlan = $self->{'settings'}->{'discovery_vlan'};
	}
	
	$self->{'logger'}->info("sw:" . $self->{'node'}->{'name'} . " dpid:" . $self->{'node'}->{'dpid_str'} ." pushing lldp forwarding rule for vlan $discovery_vlan");
	$status = $self->{'rabbit_mq'}->install_default_forward( dpid => int($self->{'dpid'}), 
								 discovery_vlan => int($self->{'settings'}->{'discovery_vlan'}),
								 async_callback => sub { $self->{'flows'} = $self->{'flows'} + 2; } );
    }

    $self->{'logger'}->info("Sending Barrier for node: " . $self->{'dpid'});
    $self->{'rabbit_mq'}->send_barrier(dpid => int($self->{'dpid'}),
				       async_callback => sub {
					   $self->get_node_status( sub {
					       my $results = shift;
					       if($results->{'status'} != FWDCTL_SUCCESS){
						   $self->{'logger'}->error("sw:" . $self->{'node'}->{'name'} . " dpid:" . $self->{'node'}->{'dpid_str'} . " failed to install default drop or lldp forward rules, may cause traffic to flood controller or discovery to fail");
					       } else {
						   $self->{'logger'}->info("sw:" . $self->{'node'}->{'name'} . " dpid:" . $self->{'node'}->{'dpid_str'} ." installed default drop rule and lldp forward rule");
					       }
					       $self->{'needs_diff'} = time();
								   })
				       });    
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
	$self->{'rabbit_mq'}->send_datapath_flow( flow => $commands->{'remove'}->to_json( command => OFPFC_DELETE_STRICT) );

        if(!$self->{'node'}->{'send_barrier_bulk'}){
	    $self->{'rabbit_mq'}->send_barrier(dpid => int($self->{'dpid'}) );
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

	$self->{'rabbit_mq'}->send_datapath_flow(flow => $commands->{'add'}->to_json( command => OFPFC_ADD));
	
        # send the barrier if the bulk flag is not set
        if (!$self->{'node'}->{'send_barrier_bulk'}) {
            $self->{'logger'}->info("Sending Barrier for node: " . $self->{'dpid'});
	    $self->{'rabbit_mq'}->send_barrier(dpid => int($self->{'dpid'}) );
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
	$self->{'rabbit_mq'}->send_barrier( dpid => int($self->{'dpid'}) );
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
        $self->{'rabbit_mq'}->get_flow_stats( dpid => $self->{'dpid'}, async_callback => $self->flow_stats_callback() );
    }
}

sub flow_stats_callback{
    my $self = shift;

    return sub {
	my $results = shift;

        
	my $time = $results->{'results'}[0]->{'time'};
	my $stats = $results->{'results'}[0]->{'flow_stats'}; 

        if ($time == -1) {
            #we don't have flow data yet
            $self->{'logger'}->info("no flow stats cached yet for dpid: " . $self->{'dpid'});
            return;
        }

        if($time > $self->{'needs_diff'}){
            #---process the flow_rules into a lookup hash
            my $flows = $self->_process_stats_to_flows( $self->{'dpid'}, $stats);
            
            #--- now that we have the lookup hash of flow_rules
            #--- do the diff
            $self->_do_diff($flows);
        }
    }
}

sub get_node_status{
    my $self          = shift;
    my $cb            = shift;

    my $result  = FWDCTL_SUCCESS;

    $self->{'rabbit_mq'}->get_node_status( dpid => int($self->{'dpid'}),
					   async_callback => sub { 
					       my $results = shift;
					       if($results->{'results'}->[0]->{'status'} == FWDCTL_WAITING){
						   $self->get_node_status( $cb );
					       }else{
						   &$cb({status => $results->{'results'}->[0]->{'status'}});
					       }
					   });
}


1;
