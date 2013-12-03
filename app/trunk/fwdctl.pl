#!/Usr/bin/perl
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

use Log::Log4perl;
use Switch;
use OESS::FlowRule;
use OESS::Database;
use OESS::Topology;
use OESS::Circuit;
use XML::Simple;
use Time::HiRes qw( usleep );

use constant FWDCTL_ADD_VLAN     => 0;
use constant FWDCTL_REMOVE_VLAN  => 1;
use constant FWDCTL_CHANGE_PATH  => 2;

use constant FWDCTL_ADD_RULE     => 0;
use constant FWDCTL_REMOVE_RULE  => 1;

#port_status reasons
use constant OFPPR_ADD => 0;
use constant OFPPR_DELETE => 1;
use constant OFPPR_MODIFY => 2;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;

#link statuses
use constant OESS_LINK_UP       => 1;
use constant OESS_LINK_DOWN     => 0;
use constant OESS_LINK_UNKNOWN  => 2;

#circuit statuses
use constant OESS_CIRCUIT_UP    => 1;
use constant OESS_CIRCUIT_DOWN  => 0;
use constant OESS_CIRCUIT_UNKNOWN => 2;

#SYSTEM USER
use constant SYSTEM_USER        => 1;

$| = 1;

my %node;
my %link_status;
my %circuit_status;
my $node_details;
sub _log {
    my $string = shift;

    my $logger = Log::Log4perl->get_logger("OESS::FWDCTL")->warn($string);

}

sub new {
    my $class = shift;
    my $service = shift;
    my $self = $class->SUPER::new($service, '/controller1');
    bless $self, $class;

    $self->{'of_controller'} = shift;

    my $db = new OESS::Database();

    if (! $db) {
        $self->{'logger'}->fatal("Could not make database object");
        exit(1);
    }
    $self->{'nodes_needing_diff'} = {};
    $self->{'db'} = $db;

    my $topo = OESS::Topology->new( db => $self->{'db'} );
    if (! $topo) {
        $self->{'logger'}->fatal("Could not initialize topo library");
        exit(1);
    }

    $self->{'topo'} = $topo;

    $self->{'logger'} = Log::Log4perl->get_logger('OESS::FWDCTL');
    $self->{'circuits'} = {};
    dbus_method("addVlan", ["uint32"], ["string"]);
    dbus_method("deleteVlan", ["string"], ["string"]);
    dbus_method("changeVlanPath", ["string"], ["string"]);
    dbus_method("topo_port_status",["uint64","uint32",["dict","string","string"]],["string"]);
    dbus_method("rules_per_switch",["uint64"],["uint32"]);
    #for notification purposes
    dbus_signal("circuit_notification", [["dict","string",["variant"]]],['string']);

    return $self;
}

sub _sync_database_to_network {
    my $self = shift;

    $self->{'logger'}->debug("Syncing DB to network");
    my $circuits = $self->{'db'}->get_current_circuits();
    foreach my $circuit (@$circuits) {

	my $ckt = OESS::Circuit->new( db => $self->{'db'},
				      circuit_id => $circuit->{'circuit_id'} );

	$self->{'logger'}->trace("Ckt: " . Data::Dumper::Dumper($ckt));

	$self->{'circuits'}->{ $ckt->get_id() } = $ckt;

        if ($circuit->{'operational_state'} eq 'up') {
            $circuit_status{$circuit->{'circuit_id'}} = OESS_CIRCUIT_UP;
        } elsif ($circuit->{'operational_state'}  eq 'down') {
            $circuit_status{$circuit->{'circuit_id'}} = OESS_CIRCUIT_DOWN;
        } else {
            $circuit_status{$circuit->{'circuit_id'}} = OESS_CIRCUIT_UNKNOWN;
        }
    }

    my $links = $self->{'db'}->get_current_links();
    foreach my $link (@$links) {
        if ($link->{'status'} eq 'up') {
            $link_status{$link->{'name'}} = OESS_LINK_UP;
        } elsif ($link->{'status'} eq 'down') {
            $link_status{$link->{'name'}} = OESS_LINK_DOWN;
        } else {
            $link_status{$link->{'name'}} = OESS_LINK_UNKNOWN;
        }
    }

    my $nodes = $self->{'db'}->get_current_nodes();
    foreach my $node (@$nodes) {
        $node->{'full_diff'} = 1;
        $self->{'nodes_needing_diff'}{$node->{'dpid'}} = $node;
	$node_details->{$node->{'dpid'}} = $node;
    }
}


sub _generate_commands{
    my $self = shift;
    my $circuit_id = shift;
    my $action = shift;

    my $ckt;
    $self->{'logger'}->debug("generating flows for circuit_id: " . $circuit_id);
    if(!defined($self->{'circuit'}->{$circuit_id})){

	$ckt = OESS::Circuit->new( circuit_id => $circuit_id,
				   db => $self->{'db'});
	$self->{'logger'}->trace("ckt: " . Data::Dumper::Dumper($ckt));
	$self->{'circuit'}->{$circuit_id} = $ckt;
    }
    
    $ckt = $self->{'circuit'}->{$circuit_id};

    $self->{'logger'}->trace("ckt: " . Data::Dumper::Dumper($ckt));

    switch($action){
	case (FWDCTL_ADD_VLAN){

	    my $flows = $ckt->get_flows();
	    return $flows;

	}case (FWDCTL_REMOVE_VLAN){

	    my $flows = $ckt->get_flows();
	    return $flows;

	}case (FWDCTL_CHANGE_PATH){

	    my $primary_flows = $ckt->get_endpoint_flows( path => 'primary');
	    my $backup_flows =  $ckt->get_endpoint_flows( path => 'backup');
	    my @commands;

	    foreach my $flow (@$primary_flows){
		if($ckt->get_current_path() eq 'primary'){
		    $flow->{'sw_act'} = FWDCTL_ADD_RULE;
		}else{
		    $flow->{'sw_act'} = FWDCTL_REMOVE_RULE;
		}
		push(@commands,$flow);
	    }

	    foreach my $flow (@$backup_flows){
		if($flow->{'sw_act'} eq 'primary'){
		    $flow->{'sw_act'} = FWDCTL_REMOVE_RULE;
		}else{
		    $flow->{'sw_act'} = FWDCTL_ADD_RULE;
		}
		push(@commands,$flow);
	    }

	    return \@commands;

	}
    }
}

#--- this and dp join need to be refactored to reuse code.
sub _initialize{
    my $self = shift;

    my $nodes = $self->{'db'}->get_node_dpid_hash();

    foreach my $node (keys (%{$nodes})) {
        my $dpid = $nodes->{$node};
        $self->{'nodes_needing_init'}{$dpid} = $node;
        $node{$dpid} = 0;
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
    $node{$dpid} = 0;
    my $sw_name = "";
    if (defined $node_details) {
        $sw_name = $node_details->{'name'};
    }

    $self->{'logger'}->info("sw:$sw_name dpid:$dpid_str datapath join");

    my %xid_hash;

    if (!defined($node_details) || $node_details->{'default_forward'} == 1) {
        my $status = $self->{'of_controller'}->install_default_forward($dpid,$self->{'db'}->{'discovery_vlan'});
        my $xid = $self->{'of_controller'}->send_barrier($dpid);
        $self->{'logger'}->debug("datapath_join_handler: send_barrier: with dpid: $dpid");
        if ($xid == FWDCTL_FAILURE) {
            #--- switch may not be connected yet or other error in controller
            _log("sw:$sw_name dpid:$dpid_str failed to install lldp forward to controller rule, discovery will fail");
            return;
        }
        $xid_hash{$dpid} = 1;
        $node{$dpid}++;
    }

    if (!defined($node_details) || $node_details->{'default_drop'} == 1) {
        my $status = $self->{'of_controller'}->install_default_drop($dpid);
        my $xid = $self->{'of_controller'}->send_barrier($dpid);
        $self->{'logger'}->debug("datapath_join_handler: send_barrier: with dpid: $dpid");
        if ($xid == FWDCTL_FAILURE) {
            #--- switch may not be connected yet or other error in controller
            $self->{'logger'}->error("sw:$sw_name dpid:$dpid_str failed to install default drop rule, traffic may flood controller");
            return;
        }
        $xid_hash{$dpid}  = 1;
        $node{$dpid}++;
    }


    my $result = $self->_poll_xids(\%xid_hash);

    if ($result != FWDCTL_SUCCESS) {
        $self->{'logger'}->error("sw:$sw_name dpid:$dpid_str failed to install default drop or lldp forward rules, may cause traffic to flood controller or discovery to fail");
        return;
    } else {
        $self->{'logger'}->info("sw:$sw_name dpid:$dpid_str installed default drop rule and lldp forward rule");
    }

    #schedule_for_flow_stats
    $self->{'nodes_needing_diff'}{$dpid} = {dpid => $dpid, full_diff => 1};
    delete $self->{'nodes_needing_init'}{$dpid};

}

sub _replace_flowmod{
    my $self = shift;
    my $commands = shift;

    if (!defined($commands->{'remove'}) && !defined($commands->{'add'})) {
        return undef;
    }

    my %xid_hash;
    #--- crude rate limiting

    if (defined($commands->{'remove'})) {
        #delete this flowmod
	$self->{'logger'}->info("Deleting flow: " . $commands->{'remove'}->to_human());
        my $status = $self->{'of_controller'}->delete_datapath_flow($commands->{'remove'}->to_dbus());
        if(!$node_details->{'send_barrier_bulk'}){
            my $xid = $self->{'of_controller'}->send_barrier($commands->{'remove'}->get_dpid());
            $self->{'logger'}->debug("replace flowmod: send_barrier: with dpid: " . $commands->{'remove'}->get_dpid());
            $xid_hash{$commands->{'remove'}->get_dpid()} = 1;
        }
        $node{$commands->{'remove'}->get_dpid()}--;
    }
    
    if (defined($commands->{'add'})) {
        if ( $node{$commands->{'add'}->get_dpid()} >= $node_details->{'max_flows'}) {
            my $dpid_str  = sprintf("%x",$commands->{'add'}->get_dpid());
            $self->{'logger'}->error("sw: dpipd:$dpid_str exceeding max_flows:".$node_details->{$commands->{'add'}->get_dpid()}->{'max_flows'}." replace flowmod failed");
            return FWDCTL_FAILURE;
        }
	$self->{'logger'}->info("Installing Flow: " . $commands->{'add'}->to_human());
        my $status = $self->{'of_controller'}->install_datapath_flow($commands->{'add'}->to_dbus());
	
        # send the barrier if the bulk flag is not set
        if (!$node_details->{'send_barrier_bulk'}) {
            my $xid = $self->{'of_controller'}->send_barrier(dbus_uint64($commands->{'add'}->get_dpid()));
            $self->{'logger'}->error("replace flowmod: send_barrier: with dpid: " . $commands->{'add'}->get_dpid());
            $xid_hash{$commands->{'add'}->get_dpid()} = 1;
        }
	
        $node{$commands->{'add'}->get_dpid()}++;
        #wait for the delete to take place
    }
    
    return;
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


    $self->{'logger'}->info("sw:$sw_name dpid:$dpid_str diff sw rules to oe-ss rules");
    #--- get the set of circuits
    my $current_circuits = $self->{'db'}->get_current_circuits();
    if (! defined $current_circuits) {
        $self->{'logger'}->error("!!! cant get the list of current circuits");
        return;
    }

    #--- process each ckt
    my @all_commands;
    foreach my $circuit (@$current_circuits) {
        my $circuit_id   = $circuit->{'circuit_id'};
        my $circuit_name = $circuit->{'name'};
        my $state        = $circuit->{'state'};

        next unless ($state eq "deploying" || $state eq "active");
        #--- get the set of commands needed to create this vlan per design
        my $commands = $self->_generate_commands($circuit_id,FWDCTL_ADD_VLAN);
        foreach my $command (@$commands) {
            push(@all_commands,$command);
        }
    }

    $node{$dpid} = 0;

    $self->_actual_diff($dpid,$sw_name, $current_flows, \@all_commands);
}


sub _actual_diff{
    my $self = shift;
    my $dpid = shift;
    my $sw_name = shift;
    my $current_flows = shift;
    my $commands = shift;

    my @rule_queue;         #--- temporary storage of forwarding rules
    my %stats = (
                 mods => 0,
                 adds => 0,
                 rems => 0
                );             #--- used to store stats about the diff

    my $node = $self->{'db'}->get_node_by_dpid( dpid => $dpid);
    my $dpid_str  = sprintf("%x",$dpid);

    foreach my $command (@$commands) {
        #---ignore rules not for this dpid
        next if($command->get_dpid() != $dpid);
	my $found = 0;

	for(my $i=0;$i<=$#{$current_flows};$i++){
	    my $current_flow = $current_flows->[$i];
	    if($command->compare_match( flow_rule => $current_flows->[$i])){
		$found = 1;
		if($command->compare_actions( flow_rule => $current_flows->[$i])){
		    #woohoo we match
		    delete $current_flow->[$i];
		    last;
		}else{
		    #doh... we don't match... remove current flow, add the other flow
		    $stats{'mods'}++;
		    push(@rule_queue,{remove => $current_flows->[$i], add => $command});
		    delete $current_flow->[$i];
		    last;
		}
	    }
	}

	if(!$found){
	    #doh... add this rule
	    $stats{'adds'}++;
	    push(@rule_queue,{add => $command});	    
	}
    }

    #if we have any flows remaining the must be removed!
    foreach my $current_flow (@$current_flows){
	$stats{'rems'}++;
	push(@rule_queue,{remove => $current_flow});
    }

    my $total = $stats{'mods'} + $stats{'adds'} + $stats{'rems'};
    $self->{'logger'}->info("sw:$sw_name dpid:$dpid_str diff plan  $total changes.  mods:".$stats{'mods'}. " adds:".$stats{'adds'}. " removals:".$stats{'rems'}."\n");

    #--- process the rule_queue
    #my $success_count=0;
    my %xid_hash;
    my $non_success_result;
    $self->{'logger'}->debug("before calling _replace_flowmod in loop with rule_queue:". @rule_queue);
    foreach my $args (@rule_queue) {
        my $new_result = $self->_replace_flowmod($args);
        if (defined($new_result) && ($new_result != FWDCTL_SUCCESS)) {
            $non_success_result = $new_result;
        }
    }

    my $xid = $self->{'of_controller'}->send_barrier(dbus_uint64($dpid));
    $xid_hash{$dpid} = 1;
    $self->{'logger'}->info("diff barrier with dpid: $dpid");

    my $result = $self->_poll_xids(\%xid_hash);

    if ($result == FWDCTL_SUCCESS) {
        $self->{'logger'}->info("sw:$sw_name dpid:$dpid_str diff completed $total changes\n");
    } else {
        $self->{'logger'}->error("sw:$sw_name dpid:$dpid_str diff did not complete\n");
    }

}


=head2 _restore_down_circuits

=cut

sub _restore_down_circuits{

    my $self = shift;
    my %params = @_;
    my $circuits = $params{'circuits'};
    my $link_name = $params{'link_name'};

    #this loop is for automatic restoration when both paths are down
    my %dpid_hash;
    my %new_dpids;
    my $new_result;
    my $non_success_result;
    $self->{'logger'}->debug("In _restore_down_circuits with circuits: ".@$circuits);
    my $circuit_notification_data = [];
    foreach my $circuit (@$circuits) {
        my $paths = $self->{'db'}->get_circuit_paths( circuit_id => $circuit->{'circuit_id'} );
        if ($#{$paths} >= 1) {

            #ok we have 2 paths
            my $backup_path;
            my $primary_path;
            foreach my $path (@$paths) {
                if ($path->{'path_type'} eq 'primary') {
                    $primary_path = $path;
                } else {
                    $backup_path = $path;
                }
            }


            #if the restored path is the backup
            if ($circuit->{'path_type'} eq 'backup') {

                if ($self->{'topo'}->is_path_up(path_id => $primary_path->{'path_id'}, link_status => \%link_status ) == OESS_LINK_DOWN) {
                    #if the primary path is down and the backup path is up and is not active fail over
                    if ($self->{'topo'}->is_path_up( path_id => $backup_path->{'path_id'}, link_status => \%link_status ) && $backup_path->{'path_state'} ne 'active') {
                        #bring it back to this path
                        my $success = $self->{'db'}->switch_circuit_to_alternate_path( circuit_id => $circuit->{'circuit_id'});
                        $self->{'logger'}->warning("vlan:" . $circuit->{'name'} ." id:" . $circuit->{'circuit_id'} . " affected by trunk:$link_name moving to alternate path");

                        if (! $success) {
                            $self->{'logger'}->error("vlan:" . $circuit->{'name'} . " id:" . $circuit->{'circuit_id'} . " affected by trunk:$link_name has NOT been moved to alternate path due to error: " . $self->{'db'}->get_error());
                            next;
                        }

                        ($new_result, %new_dpids) = $self->_changeVlanPath($circuit->{'circuit_id'});
                        # if send barriers happend and if they were not successful then set the error_result parameter
                        if (defined($new_result) && ($new_result != FWDCTL_SUCCESS)) {
                            $non_success_result = $new_result;
                        }
                        @dpid_hash{keys %new_dpids} = values %new_dpids; # merge the new dpids in with the total

                        $circuit_status{$circuit->{'circuit_id'}} = OESS_CIRCUIT_UP;
                        #send notification
                        $circuit->{'status'} = 'up';
                        $circuit->{'reason'} = 'the backup path has been restored';
                        $circuit->{'type'} = 'restored';
                        #$self->emit_signal("circuit_notification", $circuit );
                        push (@$circuit_notification_data, $circuit)
                    } elsif ($self->{'topo'}->is_path_up( path_id => $backup_path->{'path_id'}, link_status => \%link_status) && $backup_path->{'path_state'} eq 'active') {
                        #circuit was on backup path, and backup path is now up
                        $self->{'logger'}->warn("vlan:" . $circuit->{'name'} ." id:" . $circuit->{'circuit_id'} . " affected by trunk:$link_name was restored");
                        next if $circuit_status{$circuit->{'circuit_id'}} == OESS_CIRCUIT_UP;
                        #send notification on restore
                        $circuit->{'status'} = 'up';
                        $circuit->{'reason'} = 'the backup path has been restored';
                        $circuit->{'type'} = 'restored';
                        #$self->emit_signal("circuit_notification", $circuit);
                        push (@$circuit_notification_data, $circuit);
                          $circuit_status{$circuit->{'circuit_id'}} = OESS_CIRCUIT_UP;
                    } else {
                        #both paths are down...
                        #do not do anything
                    }
                }

            } else {
                #the primary path is the one that was restored

                if ($primary_path->{'path_state'} eq 'active') {
                    #nothing to do here as we are already on the primary path
                    $self->{'logger'}->debug("ckt:" . $circuit->{'circuit_id'} . " primary path restored and we were alread on it");
                    next if($circuit_status{$circuit->{'circuit_id'}} == OESS_CIRCUIT_UP);
                    $circuit_status{$circuit->{'circuit_id'}} = OESS_CIRCUIT_UP;
                    #send notifcation on restore
                    $circuit->{'status'} = 'up';
                    $circuit->{'reason'} = 'the primary path has been restored';
                    $circuit->{'type'} = 'restored';
                    #$self->emit_signal("circuit_notification", $circuit );
                    push (@$circuit_notification_data, $circuit)
                } else {

                    if ($self->{'topo'}->is_path_up( path_id => $primary_path->{'path_id'}, link_status => \%link_status )) {
                        if ($self->{'topo'}->is_path_up( path_id => $backup_path->{'path_id'}, link_status => \%link_status)) {
                            #ok the backup path is up and active... and restore to primary is not 0
                            if ($circuit->{'restore_to_primary'} > 0) {
                                #schedule the change path
                                $self->{'logger'}->warn("vlan: " . $circuit->{'name'} . " id: " . $circuit->{'circuit_id'} . " is currently on backup path, scheduling restore to primary for " . $circuit->{'restore_to_primary'} . " minutes from now");
                                $self->{'db'}->schedule_path_change( circuit_id => $circuit->{'circuit_id'},
                                                                     path => 'primary',
                                                                     when => time() + (60 * $circuit->{'restore_to_primary'}),
                                                                     user_id => SYSTEM_USER,
                                                                     workgroup_id => $circuit->{'workgroup_id'},
                                                                     reason => "circuit configuration specified restore to primary after " . $circuit->{'restore_to_primary'} . "minutes"  );
                            } else {
                                #restore to primary is off
                            }
                        } else {
                            #ok the primary path is up and the backup is down and active... lets move now
                            my $success = $self->{'db'}->switch_circuit_to_alternate_path( circuit_id => $circuit->{'circuit_id'});
                            $self->{'logger'}->warn("vlan:" . $circuit->{'name'} ." id:" . $circuit->{'circuit_id'} . " affected by trunk:$link_name moving to alternate path");
                            if (! $success) {
                                $self->{'logger'}->error("vlan:" . $circuit->{'name'} . " id:" . $circuit->{'circuit_id'} . " affected by trunk:$link_name has NOT been moved to alternate path due to error: " . $self->{'db'}->get_error());
                                next;
                            }

                            ($new_result, %new_dpids) = $self->_changeVlanPath($circuit->{'circuit_id'});
                            # if send barriers happend and if they were not successful then set the error_result parameter
                            if (defined($new_result) && ($new_result != FWDCTL_SUCCESS)) {
                                $non_success_result = $new_result;
                            }
                            @dpid_hash{keys %new_dpids} = values %new_dpids; # merge the new dpids in with the total

                            $circuit_status{$circuit->{'circuit_id'}} = OESS_CIRCUIT_UP;
                            #send restore notification
                            $circuit->{'status'} = 'up';
                            $circuit->{'reason'} = 'the primary path has been restored';
                            $circuit->{'type'} = 'restored';
                            #$self->emit_signal("circuit_notification", $circuit );
                            push (@$circuit_notification_data, $circuit);
                        }
                    }
                }
            }
        } else {
            next if($circuit_status{$circuit->{'circuit_id'}} == OESS_CIRCUIT_UP);
            $circuit_status{$circuit->{'circuit_id'}} = OESS_CIRCUIT_UP;
            #send restore notification
            $circuit->{'status'} = 'up';
            $circuit->{'reason'} = 'the primary path has been restored';
            $circuit->{'type'} = 'restored';
            #$self->emit_signal("circuit_notification", $circuit );
            push (@$circuit_notification_data, $circuit);
        }
    }
    if ( $circuit_notification_data && scalar(@$circuit_notification_data) ){
        $self->emit_signal("circuit_notification", {
                                                    "type" => 'link_up',
                                                    "link_name" => $link_name,
                                                    "affected_circuits" => $circuit_notification_data
                                                   }
                          );
    }

    # send the barrier for all the unique dpids
    my %xid_hash;
    foreach my $dpid (keys %dpid_hash) {
        my $xid = $self->{'of_controller'}->send_barrier($dpid);
        $self->{'logger'}->debug("_restore_down_circuits: send_bulk_barrier: with dpid: $dpid");
        $xid_hash{$dpid} = 1;
    }
    my $result = $self->_poll_xids(\%xid_hash);
    if ($result != FWDCTL_SUCCESS || defined($non_success_result)) {
	$self->{'logger'}->error("failed to restore downed circuits ");
    }


}

=head2 _fail_over_circuits

=cut

sub _fail_over_circuits{
    my $self = shift;
    my %params = @_;

    my $circuits = $params{'circuits'};
    my $link_name = $params{'link_name'};

    my %new_dpids;
    my %dpid_hash;
    my $new_result;
    my $non_success_result;

    $self->{'logger'}->debug("in _fail_over_circuits with circuits: ".@$circuits);
    my $circuit_infos;
    
    foreach my $circuit_info (@$circuits) {
        my $circuit_id   = $circuit_info->{'id'};
        my $circuit_name = $circuit_info->{'name'};
	
	my $circuit = $self->{'circuits'}->{$circuit_id};
	
	if(!defined($circuit)){
	    $circuit = OESS::Circuit->new( circuit_id => $circuit_id, db => $self->{'db'});
	}
	if(!defined($circuit)){
	    $self->error("unable to build circuit object for circuit_id: " . $circuit_id);
	    next;
	}
	
	if($circuit->has_backup_path()){
	    
	    my $current_path = $circuit->get_active_path();
	    
	    #if we know the current path, then the alternate is the other
	    my $alternate_path = 'primary';
	    if($current_path eq 'primary'){
		$alternate_path = 'backup';
	    }

	    #check the alternate paths status
	    if($circuit->get_path_status( path => $alternate_path)){
		my $success = $circuit->change_path();
		$self->{'logger'}->warn("vlan:$circuit_name id:$circuit_id affected by trunk:$link_name moving to alternate path");

		#failed to move the path
		if (! $success) {
                    $circuit_info->{'status'} = "unknown";
                    $circuit_info->{'reason'} = "Attempted to switch to alternate path, however an unknown error occured.";
                    $circuit_info->{'circuit_id'} = $circuit_info->{'id'};
                    $self->{'logger'}->error("vlan:$circuit_name id:$circuit_id affected by trunk:$link_name has NOT been moved to alternate path due to error: " . $self->{'db'}->get_error());
                    #$self->emit_signal("circuit_notification", $circuit_info );
                    push(@$circuit_infos, $circuit_info);
                    $circuit_status{$circuit_id} = OESS_CIRCUIT_UNKNOWN;
                    next;
                }

		($new_result, %new_dpids) = $self->_changeVlanPath($circuit_id);
                if (defined($new_result) && ($new_result != FWDCTL_SUCCESS)) {
                    $non_success_result = $new_result;
                }
                @dpid_hash{keys %new_dpids} = values %new_dpids; # merge the new dpids in with the total

                #--- no way to now if this succeeds???
                $circuit_info->{'status'} = "up";
                $circuit_info->{'reason'} = "Failed to Alternate Path";
                $circuit_info->{'circuit_id'} = $circuit_info->{'id'};
                #$self->emit_signal("circuit_notification", $circuit_info );
                push (@$circuit_infos, $circuit_info);
                $circuit_status{$circuit_id} = OESS_CIRCUIT_UP;
		
	    }else{
		
		$self->{'logger'}->warn("vlan:$circuit_name id:$circuit_id affected by trunk:$link_name has a backup path, but it is down as well.  Not failing over");
                $circuit_info->{'status'} = "down";
                $circuit_info->{'reason'} = "Attempted to fail to alternate path, however the primary and backup path are both down";
                $circuit_info->{'circuit_id'} = $circuit_info->{'id'};
                next if($circuit_status{$circuit_id} == OESS_CIRCUIT_DOWN);
                #$self->emit_signal("circuit_notification", $circuit_info );
                push (@$circuit_infos, $circuit_info);
                $circuit_status{$circuit_id} = OESS_CIRCUIT_DOWN;
                next;

	    }
	}else{
	    
	    # this is probably where we would put the dynamic backup calculation
            # when we get there.
            $self->{'logger'}->info("vlan:$circuit_name id:$circuit_id affected by trunk:$link_name has no alternate path and is down");
            $circuit_info->{'status'} = "down";
            $circuit_info->{'reason'} = "Could not fail over: no backup path configured";

            $circuit_info->{'circuit_id'} = $circuit_info->{'id'};
            next if($circuit_status{$circuit_id} == OESS_CIRCUIT_DOWN);
            #$self->emit_signal("circuit_notification", $circuit_info);
            push (@$circuit_infos, $circuit_info);
            $circuit_status{$circuit_id} = OESS_CIRCUIT_DOWN;

	}

	if ( $circuit_infos && scalar(@$circuit_infos) ) {
	    $self->emit_signal("circuit_notification", {
		"type" => 'link_down',
		"link_name" => $link_name,
		"affected_circuits" => $circuit_infos
			       });
	}
	
    }

    # send the barrier for all the unique dpids
    my %xid_hash;
    foreach my $dpid (keys %dpid_hash) {
        my $xid = $self->{'of_controller'}->send_barrier($dpid);
        $self->{'logger'}->debug("_fail_over_circuits: send_bulk_barrier: with dpid: $dpid");
        $xid_hash{$dpid} = 1;
    }
    my $result = $self->_poll_xids(\%xid_hash);
    if ($result != FWDCTL_SUCCESS || defined($non_success_result)) {
        $self->{'logger'}->error("failed to fail over circuits ");
    }

    return;
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

    my $port_name   = $info->{'name'};
    my $port_number = $info->{'port_no'};
    my $link_status = $info->{'link'};

    my $node_details = $self->{'db'}->get_node_by_dpid( dpid => $dpid );


    my $link_info   = $self->{'db'}->get_link_by_dpid_and_port(dpid => $dpid,
                                                               port => $port_number);

    if (! defined $link_info || @$link_info < 1) {
        #--- no link means edge port
        #_log("Could not find link info for dpid = $dpid and port_no = $port_number");
        return;
    }

    my $link_id   = @$link_info[0]->{'link_id'};
    my $link_name = @$link_info[0]->{'name'};
    my $sw_name   = $node_details->{'name'};
    my $dpid_str  = sprintf("%x",$dpid);

    switch($reason){

        #port status was modified (either up or down)
        case(OFPPR_MODIFY){
            #--- when a port goes down, determine the set of ckts that traverse the port
            #--- for each ckt, fail over to the non-active path, after determining that the path
            #--- looks to be intact.
            if (! $link_status) {
                $self->{'logger'}->warn("sw:$sw_name dpid:$dpid_str port $port_name trunk $link_name is down");

                my $affected_circuits = $self->{'db'}->get_affected_circuits_by_link_id(link_id => $link_id);

                if (! defined $affected_circuits) {
                    $self->{'logger'}->error("Error getting affected circuits: " . $self->{'db'}->get_error());
                    return;
                }

                $link_status{$link_name} = OESS_LINK_DOWN;
                #fail over affected circuits
                $self->_fail_over_circuits( circuits => $affected_circuits, link_name => $link_name );
                $self->_cancel_restorations( link_id => $link_id);

            }

            #--- when a port comes back up determine if any circuits that are currently down
            #--- can be restored by bringing it back up over to this path, we do not restore by default
            else {
                $self->{'logger'}->warn("sw:$sw_name dpid:$dpid_str port $port_name trunk $link_name is up");
                $link_status{$link_name} = OESS_LINK_UP;
                my $circuits = $self->{'db'}->get_circuits_on_link( link_id => $link_id);
                $self->_restore_down_circuits( circuits => $circuits, link_name => $link_name );

            }
        }
        case(OFPPR_DELETE){
            if (defined($link_id) && defined($link_name)) {
                $self->{'logger'}->warn("sw:$sw_name dpid:$dpid_str port $port_name trunk $link_name has been removed");
            } else {
                $self->{'logger'}->warn("sw:$sw_name dpid:$dpid_str port $port_name has been removed");
            }
            $self->{'nodes_needing_diff'}{$dpid} = {full_diff => 1, dpid => $dpid};
            #note that this will cause the flow_stats_in handler to handle this data
        } else {
            #this is the add case and we don't want to do anything here, as TOPO will tell us

        }
    }
}

sub _cancel_restorations{
    my $self = shift;
    my %args = @_;

    if (!defined($args{'link_id'})) {
        return;
    }

    my $circuits = $self->{'db'}->get_circuits_on_link( link_id => $args{'link_id'} , path => 'primary');

    foreach my $circuit (@$circuits) {
        my $scheduled_events = $self->{'db'}->get_circuit_scheduled_events( circuit_id => $circuit->{'circuit_id'},
                                                                            show_completed => 0 );

        foreach my $event (@$scheduled_events) {
            if ($event->{'user_id'} == SYSTEM_USER) {
                #this is probably us... verify
                my $xml = XMLin($event->{'layout'});
                next if $xml->{'action'} ne 'change_path';
                next if $xml->{'path'} ne 'primary';
                $self->{'db'}->cancel_scheduled_action( scheduled_action_id => $event->{'scheduled_action_id'} );
                $self->{'logger'}->warn("Canceling restore to primary for circuit: " . $circuit->{'circuit_id'} . " because primary path is down");
            }
        }
    }

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
    if (defined($link)) {

        my $affected_link_circuits = $self->{'db'}->get_affected_circuits_by_link_id( link_id => $link->[0]->{'link_id'} );

        foreach my $ckt (@$affected_link_circuits) {
            push(@$affected_circuits,$ckt);
        }
    }

    my @port_commands;
    foreach my $ckt (@$affected_circuits) {
        my $circuit_id   = $ckt->{'id'};
        my $circuit_name = $ckt->{'name'};
        my $state        = $ckt->{'state'};

        next unless ($state eq "deploying" || $state eq "active" || !defined($state));
        _log("vlan:$circuit_name id:$circuit_id depends on dpid:$dpid_str port:$port_number");

        my $commands = $self->_generate_commands($circuit_id,FWDCTL_ADD_VLAN);
        foreach my $command (@$commands) {
            #ignore rules not for this dpid
            next if($command->{'dpid'}->value() != $dpid);

            #include rules that have a match on this port
            if ($command->{'attr'}->{'IN_PORT'}->value() == $port_number) {
                push(@port_commands,$command);
                next;
            }

            #include rules that have an action on this port
            foreach my $action (@{$command->{'action'}}) {
                if ($action->[0]->value() == OESS::FlowRule::OFPAT_OUTPUT && $action->[1]->[1]->value() == $port_number) {
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

    _log("sw: dpid:$dpid_str diff sw rules to oe-ss rules for port:".$node->{'port_number'});

    my %current_flows;

    $current_flows{$node->{'port_number'}} = $current_rules->{$node->{'port_number'}};

    #first we need to filter this down to flows on our interfaces
    foreach my $port (keys (%{$current_rules})) {
        next if($port == $node->{'port_number'});

        foreach my $vlan (keys (%{$current_rules->{$port}})) {
            my $actions = $current_rules->{$port}->{$vlan}->{'actions'};
            foreach my $action (@$actions) {
                if ($action->{'type'} == OESS::FlowRule::OFPAT_OUTPUT && $action->{'port'} == $node->{'port_number'}) {
                    $current_flows{$port}{$vlan} = $current_rules->{$port}->{$vlan};
                }
            }
        }
    }

    #get a list of all the rules that we want on the port
    my $rules = $self->_get_rules_on_port( port_number => $node->{'port_number'}, dpid => $node->{'dpid'} );

    $self->_actual_diff( $node->{'dpid'},$node->{'name'}, \%current_flows, $rules, 0);
    _log("sw: dpid:$dpid_str diff sw rules to oe-ss rules for port:".$node->{'port_number'}." complete");
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

	my $link_id;
	my $link_name;

	if (defined(@$link_info[0])) {
	    $link_id   = @$link_info[0]->{'link_id'};
	    $link_name = @$link_info[0]->{'name'};
	}

	my $sw_name   = $node->{'name'};
	my $dpid_str  = sprintf("%x",$dpid);


	switch ($reason) {
	    #add case
	    case OFPPR_ADD {
            if (defined($link_id) && defined($link_name)) {
                _log("sw:$sw_name dpid:$dpid_str port $port_name trunk $link_name has been added");
            } else {
                _log("sw:$sw_name dpid:$dpid_str port $port_name has been added");
            }

            $self->{'nodes_needing_diff'}{$dpid} = {full_diff => 1, dpid => $dpid};
            #note that this will cause the flow_stats_in handler to handle this data
	    }case OFPPR_DELETE {
            if (defined($link_id) && defined($link_name)) {
                _log("sw:$sw_name dpid:$dpid_str port $port_name trunk $link_name has been removed");
            } else {
                _log("sw:$sw_name dpid:$dpid_str port $port_name has been removed");
            }
            $self->{'nodes_needing_diff'}{$dpid} = {full_diff => 1, dpid => $dpid};
            #note that this will cause the flow_stats_in handler to handle this data
	    } else {
            $self->port_status($dpid,$reason,$info);
	    }
	}
	return 1;

}


sub rules_per_switch{
    my $self = shift;
    my $dpid = shift;

    #    print STDERR "Looking for DPID: " . Dumper($dpid) . "\n";
    #    print STDERR Dumper(%node);
    print STDERR "Node: " . $dpid . " has " . $node{$dpid} . " flowmods";
    return $node{$dpid};
}

sub _process_stats_to_flows{
    my $dpid = shift;
    my $flows = shift;
    
    my @new_flows;
    foreach my $flow (@$flows){
	
	my $new_flow = OESS::FlowRule::parse_stat( dpid => $dpid, stat => $flow );
	push(@new_flows,$new_flow);
    }

    return \@new_flows;
    
}

sub _process_flows_to_hash{
    my $flows = shift;
    my $tmp = {};

    foreach my $flow (@$flows) {
        my $match = $flow->{'match'};
        if (!defined($match->{'in_port'})) {
            next;
        }


        #--- internally we represet untagged as -1
        my $vid = $match->{'dl_vlan'};
        if ($vid == 65535) {
            $vid = -1;
        }
        $tmp->{$match->{'in_port'}}->{$vid} = {seen => 0,actions => $flow->{'actions'}};
    }

    return $tmp;
}


sub get_flow_stats{
    my $self = shift;
    foreach my $dpid (keys (%{$self->{'nodes_needing_diff'}})) {
        my $node = $self->{'nodes_needing_diff'}{$dpid};
        my ($time,$stats) = $self->{'of_controller'}->get_flow_stats($dpid);

        if ($time == -1) {
            #we don't have flow data yet
            _log("no flow stats cached yet for dpid: " . $dpid);
            next;
        }


        #---process the flow_rules into a lookup hash
        #my $hash = _process_flows_to_hash($flows);
        my $flows = _process_stats_to_flows( $dpid, $stats);

        #--- now that we have the lookup hash of flow_rules
        #--- do the diff

        $self->_do_diff($node,$flows);

        delete $self->{'nodes_needing_diff'}{$dpid};
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
    my $xid_hash_ref  = shift; #-- some day hash will be useful if we have to do aysnch error handling

    my $result  = FWDCTL_SUCCESS;
    my $timeout = time() + 15;

    while (time() < $timeout) {
        foreach my $xid (keys %$xid_hash_ref) {
            my $output = $self->{'of_controller'}->get_xid_result($xid);

            #-- pending, retry later
            next if ($output == FWDCTL_WAITING);

            #--- one failed , some day have handler passed in hash
            if ($output == FWDCTL_FAILURE) {
                $result = FWDCTL_FAILURE;
            }
            #--- must be success, remove from hash
            delete $xid_hash_ref->{$xid};

        }
        if (scalar keys %$xid_hash_ref == 0) {
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

    $self->{'logger'}->info("addVlan: $circuit_id");

    #--- get the set of commands needed to create this vlan per design
    my $commands = $self->_generate_commands($circuit_id,FWDCTL_ADD_VLAN);

    my %xid_hash;
    my %dpid_hash;

    foreach my $command (@{$commands}) {
        #---!_!_! this needs to not make redudant queries
        my $node = $self->{'db'}->get_node_by_dpid( dpid => $command->get_dpid());
        if (defined $dpid && $dpid != $command->get_dpid()) {
            #--- if we are restricting the call to a specific dpid
            #--- then ignore commands to non-matching dpids
            #--- this is used when trying to synch up a specific switch
            next;
        }
        #first delay by some configured value in case the device can't handle it
        usleep($node->{'tx_delay_ms'} * 1000);
        if ($node{$command->get_dpid()} >= $node->{'max_flows'}) {
            my $dpid_str  = sprintf("%x",$command->get_dpid());
            _log("sw: dpipd:$dpid_str exceeding max_flows:".$node->{'max_flows'}." adding vlan failed");
            $circuit_status{$circuit_id} = OESS_CIRCUIT_UNKNOWN;
            return FWDCTL_FAILURE;

        }
	$self->{'logger'}->info("Installing Flow: " . $command->to_human());
        my $status = $self->{'of_controller'}->install_datapath_flow($command->to_dbus());
        # send the barrier now if need be
        if (!$node->{'send_barrier_bulk'}) {
            my $xid = $self->{'of_controller'}->send_barrier($command->get_dpid());
            my $dpid_str  = sprintf("%x",$command->get_dpid());
            _log("addVlan: send_barrier: with dpid: $dpid_str");
            $xid_hash{$command->get_dpid()} = 1;
        } else {
            $dpid_hash{$command->get_dpid()} = 1;
        }
        $node{$command->get_dpid()}++;
    }
    my $initial_result;
    if (%xid_hash) {
        $initial_result = $self->_poll_xids(\%xid_hash);
    }
    foreach my $dpid (keys %dpid_hash) {
        my $xid = $self->{'of_controller'}->send_barrier($dpid);
        _log("addVlan: send_bulk_barrier: with dpid: $dpid");
        $xid_hash{$dpid} = 1;
    }

    my $result = $self->_poll_xids(\%xid_hash);
    # if the initial poll_xid method was called and it returned a failure treat the second one as a failure as well
    if (defined($initial_result) && ($initial_result != FWDCTL_SUCCESS)) {
        $result = $initial_result;
    }

    if ($result == FWDCTL_SUCCESS) {

        my $details = $self->{'db'}->get_circuit_details(circuit_id => $circuit_id);


        if ($details->{'state'} eq "deploying" || $details->{'state'} eq "scheduled") {

            my $state = $details->{'state'};

            $self->{'db'}->update_circuit_state(circuit_id          => $circuit_id,
                                                old_state           => $state,
                                                new_state           => 'active',
                                                modified_by_user_id => $details->{'user_id'}
                                               );
        }
        $self->{'db'}->update_circuit_path_state(circuit_id  => $circuit_id,
                                                 old_state   => 'deploying',
                                                 new_state   => 'active',
                                                );

        $circuit_status{$circuit_id} = OESS_CIRCUIT_UP;
    } else {
        _log("addVlan fwdctl fail");

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
    my %dpid_hash;

    foreach my $command (@{$commands}) {
        #--- issue each command to controller
        #first delay by some configured value in case the device can't handle it
	$self->{'logger'}->debug("Flow " . Data::Dumper::Dumper($command));
        my $node = $self->{'db'}->get_node_by_dpid( dpid => $command->get_dpid());
        usleep($node->{'tx_delay_ms'} * 1000);
	$self->{'logger'}->info("Removing Flow: " . $command->to_human());
        my $status = $self->{'of_controller'}->delete_datapath_flow($command->to_dbus());
        # send a barrier now if need be
        if (!$node->{'send_barrier_bulk'}) {
            my $xid = $self->{'of_controller'}->send_barrier($command->get_dpid());
            _log("deleteVlan: send_barrier: with dpid: ".$command->get_dpid());
            $xid_hash{$command->get_dpid()} = 1;
        } else {
            $dpid_hash{$command->get_dpid()} = 1;
        }
        $node{$command->get_dpid()}--;
    }
    # if any barrier were sent poll the xids first
    my $initial_result;
    if (%xid_hash) {
        $initial_result = $self->_poll_xids(\%xid_hash);
    }

    foreach my $dpid (keys %dpid_hash) {
        my $xid = $self->{'of_controller'}->send_barrier($dpid);
        _log("deleteVlan: send_bulk_barrier: with dpid: $dpid");
        $xid_hash{$dpid} = 1;
    }

    my $result = $self->_poll_xids(\%xid_hash);
    # if the initial poll xids method was called and it failed return its result
    if (defined($initial_result) && ($initial_result != FWDCTL_SUCCESS)) {
        $result = $initial_result;
    }
    if ($result != FWDCTL_SUCCESS) {
        _log("deleteVlan fwdctl fail");
    }

    return $result;
}

# the internal method that does not send the barrier
sub _changeVlanPath {

    my $self = shift;
    my $circuit_id = shift;
    #--- get the set of commands needed to create this vlan per design
    my $commands = $self->_generate_commands($circuit_id,FWDCTL_CHANGE_PATH);
    my %dpid_hash;
    my %xid_hash;
    # we have to make sure to do the removes first
    $self->{'logger'}->debug("In _changeVlanPath with commands: ".@$commands);
    foreach my $command (@$commands) {
        my $node = $self->{'db'}->get_node_by_dpid( dpid => $command->get_dpid());
        if ($command->{'sw_act'} eq FWDCTL_REMOVE_RULE) {
            #first delay by some configured value in case the device can't handle it
            usleep($node->{'tx_delay_ms'} * 1000);
	    $self->{'logger'}->info("Deleting flow: " . $command->to_human());
            my $status = $self->{'of_controller'}->delete_datapath_flow($command->to_dbus());
            $node{$command->get_dpid()}--;

            # send the barrier now if the bulk flag is not set
            if (!$node->{'send_barrier_bulk'}) {
                my $xid = $self->{'of_controller'}->send_barrier($command->get_dpid());
                $self->{'logger'}->debug("_changeVlanPath: send_barrier: with dpid: ".$command->get_dpid());
                $xid_hash{$command->get_dpid()} = 1;
            } else {
                $dpid_hash{$command->get_dpid()} = 1;
            }
        }

    }

    foreach my $command (@$commands) {
        if ($command->{'sw_act'} ne FWDCTL_REMOVE_RULE) {
            my $node = $self->{'db'}->get_node_by_dpid( dpid => $command->get_dpid());
            #first delay by some configured value in case the device can't handle it
            usleep($node->{'tx_delay_ms'} * 1000);
            if ($node{$command->get_dpid()} >= $node->{'max_flows'}) {
                my $dpid_str  = sprintf("%x",$command->get_dpid());
                _log("sw: dpipd:$dpid_str exceeding max_flows:".$node->{'max_flows'}." changing path failed");
                return FWDCTL_FAILURE;
            }
	    $self->{'logger'}->info("Installing Flow: " . $command->to_human());
            my $status = $self->{'of_controller'}->install_datapath_flow($command->to_dbus());
            $node{$command->get_dpid()}++;

            if (!$node->{'send_barrier_bulk'}) {
                my $xid = $self->{'of_controller'}->send_barrier($command->get_dpid());
                $self->{'logger'}->debug("_changeVlanPath: send_barrier: with dpid: ".$command->get_dpid());
                $xid_hash{$command->get_dpid()} = 1;
            } else {
                $dpid_hash{$command->get_dpid()} = 1;
            }
        }

    }
    # if we sent any barriers immediately, poll the xids
    my $result;
    if (%xid_hash) {
        $result = $self->_poll_xids(\%xid_hash);
        if ($result != FWDCTL_SUCCESS) {
            $self->{'logger'}->error("failed to install flows in _changeVlanPath");
        }
    }

    return ($result, %dpid_hash);
}

#dbus_method("changeVlanPath", ["string"], ["string"]);

sub changeVlanPath {
    my $self = shift;
    my $circuit_id = shift;
    my %xid_hash;
    my ($initial_result, %dpid_hash) = $self->_changeVlanPath($circuit_id);


    foreach my $dpid (keys %dpid_hash) {
        my $xid = $self->{'of_controller'}->send_barrier($dpid);
        $self->{'logger'}->debug("changeVlanPath: send_bulk_barrier: with dpid: $dpid");
        $xid_hash{$dpid} = 1;
    }
    my $result = $self->_poll_xids(\%xid_hash);
    #if the initial poll xids method wqs called and it was not successful send its return
    if (defined($initial_result) && ($initial_result != FWDCTL_SUCCESS)) {
        $result = $initial_result;
    }
    if ($result != FWDCTL_SUCCESS) {
        $self->{'logger'}->error("changeVlanPath fwdctl fail! Circuit ID: " . $circuit_id);
    }

    return $result;
}


1;
###############################################################################
package main;

use OESS::DBus;
use Log::Log4perl;
use Net::DBus::Exporter qw(org.nddi.fwdctl);
use Net::DBus qw(:typing);
use base qw(Net::DBus::Object);
use English;
use Getopt::Long;
use Proc::Daemon;

my $log;

my $srv_object = undef;

sub core{

    my $dbus = OESS::DBus->new( service => "org.nddi.openflow", instance => "/controller1");
    
    if (! defined $dbus) {
        $log->fatal("Could not connect to openflow service, aborting.");
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
        $log->warn("sw: dpipd:$dpid_str datapath_join");
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

    sub get_flow_stats_callback{
        $srv_object->get_flow_stats();
    }

    $dbus->connect_to_signal("datapath_join",\&datapath_join_callback);
    $dbus->connect_to_signal("port_status",\&port_status_callback);
    $dbus->connect_to_signal("link_event",\&link_event_callback);

    $log->info("all signals connected");

    $dbus->start_reactor( timeouts => [{ interval => 10000, callback => Net::DBus::Callback->new(
                                                                                                 method => sub {
                                                                                                     get_flow_stats_callback();
                                                                                                 })
                                       }]);
}

sub main{
    my $is_daemon = 0;
    my $verbose;
    my $username;

    my $result = GetOptions (   #"length=i" => \$length, # numeric
                             #"file=s"   => \$data, # string
                             "user|u=s"  => \$username,
                             "verbose"   => \$verbose, #flag
                             "daemon|d"  => \$is_daemon,
                            );


    #now change username/
    if (defined $username) {
        my $new_uid=getpwnam($username);
        my $new_gid=getgrnam($username);
        $EGID=$new_gid;
        $EUID=$new_uid;
    }

    if ($is_daemon != 0) {
        my $daemon;
        if ($verbose) {
            $daemon = Proc::Daemon->new(
                                        pid_file => '/var/run/oess/fwdctl.pid',
                                        child_STDOUT => '/var/log/oess/fwdctl.out',
                                        child_STDERR => '/var/log/oess/fwdctl.log',
                                       );
        } else {
            $daemon = Proc::Daemon->new(
                                        pid_file => '/var/run/oess/fwdctl.pid'
                                       );
        }
        my $kid_pid = $daemon->Init;

        if ($kid_pid) {
            return;
        }

        core();
    }
    #not a deamon, just run the core;
    else {
	$SIG{HUP} = sub{ exit(0); };
	$log->debug("Starting Core");
        core();
    }

}

Log::Log4perl::init_and_watch('/etc/oess/logging.conf',10);
$log = Log::Log4perl->get_logger("FWDCTL");
$log->info("FWDCTL Start");

main();

1;
