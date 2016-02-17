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
package OESS::FWDCTL::Master;

use strict;
use Net::DBus::Exporter qw(org.nddi.fwdctl);
use Net::DBus qw(:typing);
use Net::DBus::Annotation qw(:call);
use base qw(Net::DBus::Object);

use Data::Dumper;
use POSIX;
use Log::Log4perl;
use Switch;
use OESS::FlowRule;
use OESS::FWDCTL::Switch;
use OESS::Database;
use OESS::Topology;
use OESS::Circuit;
use OESS::DBus;
use AnyEvent::Fork;
use AnyEvent::Fork::RPC;
use AnyEvent;
use JSON::XS;
use XML::Simple;
use Time::HiRes qw( usleep );
use Data::UUID;

use constant TIMEOUT => 3600;

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

sub _log {
    my $string = shift;

    my $logger = Log::Log4perl->get_logger("OESS.FWDCTL.MASTER")->warn($string);

}

=head2 OFPPR_ADD
=cut
=head2 OFPPR_DELETE
=cut


=head2 new

    create a new OESS Master process

=cut

sub new {
    my $class = shift;
    my %params = @_;
    my $service = $params{'service'};
    my $config  = $params{'config'}; 
    my $self = $class->SUPER::new($service, '/controller1');
    bless $self, $class;


    $self->{'logger'} = Log::Log4perl->get_logger('OESS.FWDCTL');
    #my $config = shift;
    if(!defined($config)){
        $config = "/etc/oess/database.xml";
    }

    $db->{'logger'} = Log::Log4perl->get_logger('OESS.Database');    
    my $db = $params{'cache'}->{'db'};
    $db->reconnect();

    if (! $db) {
        $self->{'logger'}->fatal("Could not make database object");
        exit(1);
    }
    $self->{'db'} = $db;

    my $topo = OESS::Topology->new( db => $self->{'db'} );
    if (! $topo) {
        $self->{'logger'}->fatal("Could not initialize topo library");
        exit(1);
    }

    foreach my $ckt (keys (%{$params{'cache'}->{'circuit'}})){
        $params{'cache'}->{'circuit'}->{$ckt}->{'logger'} = Log::Log4perl->get_logger('OESS.Circuit');
    }

    $self->{'topo'} = $topo;

    $self->{'uuid'} = new Data::UUID;

    if(!defined($self->{'share_file'})){
        $self->{'share_file'} = '/var/run/oess/share';
    }

    $self->{'circuit'} = {};
    $self->{'node_rules'} = {};
    $self->{'link_status'} = {};
    $self->{'circuit_status'} = {};
    $self->{'node_info'} = {};
    $self->{'link_maintenance'} = {};

    $self->{'logger'}->error("No cache specified! Possible race condition... dying") && $self->{'logger'}->logconfess() if(!defined($params{'cache'}));

    $self->{'circuit'} = $params{'cache'}->{'circuit'};
    $self->{'link_status'} = $params{'cache'}->{'link_status'};
    $self->{'node_info'} = $params{'cache'}->{'node_info'};
    $self->{'circuit_status'} = $params{'cache'}->{'circuit_status'};
   
    #remote method calls people can make to the master
    dbus_method("addVlan", ["uint32"], ["int32","string"]);
    dbus_method("deleteVlan", ["string"], ["int32","string"]);
    dbus_method("changeVlanPath", ["string"], ["int32","string"]);
    dbus_method("topo_port_status",["uint64","uint32",["dict","string","string"]]);
    dbus_method("rules_per_switch",["uint64"],["uint32"]);
    dbus_method("fv_link_event",["string","int32"],["int32"]);
    dbus_method("update_cache",["int32"],["int32", "string"]);
    dbus_method("force_sync",["uint64"],["int32","string"]);
    dbus_method("get_event_status",["string"],["int32"]);
    dbus_method("check_child_status",[],["int32","string"]);
    dbus_method("node_maintenance", ["int32", "string"], ["int32"]);
    dbus_method("link_maintenance", ["int32", "string"], ["int32"]);
    
    #exported for the circuit notifier
    dbus_signal("circuit_notification", [["dict","string",["variant"]]],['string']);

    return $self;
}


=head2 node_maintenance
Given a node_id and maintenance state of 'start' or 'end', configure
each interface of every link on the given datapath by calling
link_maintenance.
=cut
sub node_maintenance {
    my $self  = shift;
    my $node_id  = shift;
    my $state = shift;

    my $links = $self->{'db'}->get_links_by_node(node_id => $node_id);
    if (!defined $links) {
        return 0;
    }

    # It is possible for a link to be in maintenace, and connected to a
    # node under maintenance. When node maintenance has ended but one
    # of the links was separately placed in maintenance, do not modify
    # forwarding behavior on that link.
    my %store;
    my $maintenances = $self->{'db'}->get_link_maintenances();
    foreach my $maintenance (@$maintenances) {
        $self->{'logger'}->warn("Link $maintenance->{'link'}->{'id'} in maintenance.");
        $store{$maintenance->{'link'}->{'id'}} = 1;
    }

    foreach my $link (@$links) {
        if ($state eq 'end' && defined $store{$link->{'link_id'}}) {
            $self->{'logger'}->warn("Link $link->{'link_id'} will remain under maintenance.");
        } else {
            $self->link_maintenance($link->{'link_id'}, $state);
        }
    }
    $self->{'logger'}->warn("Node $node_id maintenance state is $state.");
    return 1;
}

=head2 link_maintenance
Given a link_id and maintenance state of 'start' or 'end' configure
each interface of a link. If state is 'start' trigger port_status events
signaling the the interfaces have went down, and store the interface_ids
in $interface_maintenance. If the state is 'end' remove the
interface_ids from $interface_maintenance.
=cut
sub link_maintenance {
    my $self    = shift;
    my $link_id = shift;
    my $state   = shift;

    my $endpoints = $self->{'db'}->get_link_endpoints(link_id => $link_id);
    my $link_state;
    if (@$endpoints[0]->{'operational_state'} eq 'up' && @$endpoints[1]->{'operational_state'} eq 'up') {
        $link_state = OESS_LINK_UP;
    } else {
        $link_state = OESS_LINK_DOWN;
    }
    
    my $e1 = {
        id      => @$endpoints[0]->{'interface_id'},
        name    => @$endpoints[0]->{'interface_name'},
        port_no => @$endpoints[0]->{'port_number'},
        link    => $link_state
    };
    my $node1 = $self->{'db'}->get_node_by_interface_id(interface_id => $e1->{'id'});
    if (!defined $node1) {
        $self->{'logger'}->warn("Link maintenance can't be performed. Could not find link endpoint.");
        return 0;
    }

    my $e2 = {
        id      => @$endpoints[1]->{'interface_id'},
        name    => @$endpoints[1]->{'interface_name'},
        port_no => @$endpoints[1]->{'port_number'},
        link    => $link_state
    };
    my $node2 = $self->{'db'}->get_node_by_interface_id(interface_id => $e2->{'id'});
    if (!defined $node2) {
        $self->{'logger'}->warn("Link maintenance can't be performed on remote links.");
        return 0;
    }

    if ($state eq 'end') {
        # It is possible for a link to be in maintenance, and connected
        # to a node under maintenance. When link maintenance has ended
        # but node maintenance has not, forwarding behavior should not
        # be modified.
        my $maintenances = $self->{'db'}->get_node_maintenances();
        foreach my $maintenance (@$maintenances) {
            my $node_id = $maintenance->{'node'}->{'id'};
            if (@$endpoints[0]->{'node_id'} == $node_id || @$endpoints[1]->{'node_id'} == $node_id) {
                $self->{'logger'}->warn("Link $link_id will remain under maintenance.");
                return 1;
            }
        }

        # Once maintenance has ended remove $link_id from our
        # link_maintenance hash, and call port_status including the true
        # link state.
        if (exists $self->{'link_maintenance'}->{$link_id}) {
            delete $self->{'link_maintenance'}->{$link_id};
        }

        $self->port_status($node1->{'dpid'}, OFPPR_MODIFY, $e1);
        $self->port_status($node2->{'dpid'}, OFPPR_MODIFY, $e2);
        $self->{'logger'}->warn("Link $link_id maintenance has ended.");
    } else {
        # Simulate link down event by passing false link state to
        # port_status.
        $e1->{'link'} = OESS_LINK_DOWN;
        $e2->{'link'} = OESS_LINK_DOWN;

        my $link_name;
        $link_name = $self->port_status($node1->{'dpid'}, OFPPR_MODIFY, $e1);
        $link_name = $self->port_status($node2->{'dpid'}, OFPPR_MODIFY, $e2);

        $self->{'link_maintenance'}->{$link_id} = 1;
        $self->{'link_status'}->{$link_name} = $link_state; # Record true link state.
        $self->{'logger'}->warn("Link $link_id maintenance has begun.");
    }
    return 1;
}

=head2 rules_per_switch

=cut

sub rules_per_switch{
    my $self = shift;
    my $dpid = shift;
    
    if(defined($dpid) && defined($self->{'node_rules'}->{$dpid})){
        return $self->{'node_rules'}->{$dpid};
    }
}

=head2 force_sync

method exported to dbus to force sync a node

=cut

sub force_sync{
    my $self = shift;
    my $dpid = shift;

    my $event_id = $self->_generate_unique_event_id();
    $self->send_message_to_child($dpid,{action => 'force_sync'},$event_id);
    return (FWDCTL_SUCCESS,$event_id);        
}

=head2 update_cache

updates the cache for all of the children

=cut

sub update_cache{
    my $self = shift;
    my $circuit_id = shift;

    if(!defined($circuit_id) || $circuit_id == -1){
        $self->{'logger'}->debug("Updating Cache for entire network");
        my $res = build_cache(db => $self->{'db'}, logger => $self->{'logger'});
        $self->{'circuit'} = $res->{'ckts'};
        $self->{'link_status'} = $res->{'link_status'};
        $self->{'circuit_status'} = $res->{'circuit_status'};
        $self->{'node_info'} = $res->{'node_info'};
        $self->{'logger'}->debug("Cache update complete");

    }else{
        $self->{'logger'}->debug("Updating cache for circuit: " . $circuit_id);
        my $ckt = $self->get_ckt_object($circuit_id);
        if(!defined($ckt)){
            return (FWDCTL_FAILURE,$self->_generate_unique_event_id());
        }
        $ckt->update_circuit_details();
        $self->{'logger'}->debug("Updating cache for circuit: " . $circuit_id . " complete");
    }

    #write the cache for our children
    $self->_write_cache();
    my $event_id = $self->_generate_unique_event_id();
    foreach my $child (keys %{$self->{'children'}}){
            $self->send_message_to_child($child,{action => 'update_cache'},$event_id);
    }
    
    return (FWDCTL_SUCCESS,$event_id);
}

=head2 build_cache

    a static method that builds the cache and is used by fwdctl.pl as well as
    called internally by FWDCTL::Master.

=cut

sub build_cache{
    my %params = @_;
    
    
    my $db = $params{'db'};
    my $logger = $params{'logger'};

    die if(!defined($logger));

    #basic assertions
    $logger->error("DB was not defined") && $logger->logcluck() && exit 1 if !defined($db);
    $logger->error("DB Version does not match expected version") && $logger->logcluck() && exit 1 if !$db->compare_versions();
    
    
    $logger->debug("Fetching State from the DB");
    my $circuits = $db->get_current_circuits();

    #init our objects
    my %ckts;
    my %circuit_status;
    my %link_status;
    my %node_info;
    foreach my $circuit (@$circuits) {
        my $id = $circuit->{'circuit_id'};
        my $ckt = OESS::Circuit->new( db => $db,
                                      circuit_id => $id );
        $ckts{ $ckt->get_id() } = $ckt;
        
        my $operational_state = $circuit->{'details'}->{'operational_state'};
        if ($operational_state eq 'up') {
            $circuit_status{$id} = OESS_CIRCUIT_UP;
        } elsif ($operational_state  eq 'down') {
            $circuit_status{$id} = OESS_CIRCUIT_DOWN;
        } else {
            $circuit_status{$id} = OESS_CIRCUIT_UNKNOWN;
        }
    }
        
    my $links = $db->get_current_links();
    foreach my $link (@$links) {
        if ($link->{'status'} eq 'up') {
            $link_status{$link->{'name'}} = OESS_LINK_UP;
        } elsif ($link->{'status'} eq 'down') {
            $link_status{$link->{'name'}} = OESS_LINK_DOWN;
        } else {
            $link_status{$link->{'name'}} = OESS_LINK_UNKNOWN;
        }
    }
        
    my $nodes = $db->get_current_nodes();
    foreach my $node (@$nodes) {
        my $details = $db->get_node_by_dpid(dpid => $node->{'dpid'});
        $details->{'dpid_str'} = sprintf("%x",$node->{'dpid'});
        $details->{'name'} = $node->{'name'};
        $node_info{$node->{'dpid'}} = $details;
    }

    return {ckts => \%ckts, circuit_status => \%circuit_status, link_status => \%link_status, node_info => \%node_info};

}
        

sub _write_cache{
    my $self = shift;

    my %dpids;

    my %circuits;
    foreach my $ckt_id (keys (%{$self->{'circuit'}})){
        my $found = 0;
        $self->{'logger'}->debug("writing circuit: " . $ckt_id . " to cache");
        
        my $ckt = $self->get_ckt_object($ckt_id);
        my $details = $ckt->get_details();

        $circuits{$ckt_id} = {};

        $circuits{$ckt_id}{'details'} = {active_path => $details->{'active_path'},
                                         state => $details->{'state'},
                                         name => $details->{'name'},
                                         description => $details->{'description'} };
        
        my @flows = @{$ckt->get_flows()};
        foreach my $flow (@flows){
            push(@{$dpids{$flow->get_dpid()}{$ckt_id}{'flows'}{'current'}},$flow->to_canonical());
        }

        foreach my $flow (@{$ckt->{'flows'}->{'endpoint'}->{'primary'}}){
            push(@{$dpids{$flow->get_dpid()}{$ckt_id}{'flows'}{'endpoint'}{'primary'}},$flow->to_canonical());
        }
        foreach my $flow (@{$ckt->{'flows'}->{'endpoint'}->{'backup'}}){
            push(@{$dpids{$flow->get_dpid()}{$ckt_id}{'flows'}{'endpoint'}{'backup'}},$flow->to_canonical());
        }

    }

        
    foreach my $dpid (keys %{$self->{'node_info'}}){
        my $data;
        my $ckts;
        foreach my $ckt (keys %circuits){
            $ckts->{$ckt} = $circuits{$ckt};
            $ckts->{$ckt}->{'flows'} = $dpids{$dpid}->{$ckt}->{'flows'};
        }
        $data->{'ckts'} = $ckts;
        $data->{'nodes'} = $self->{'node_info'};
        $data->{'settings'}->{'discovery_vlan'} = $self->{'db'}->{'discovery_vlan'};
        $self->{'logger'}->info("writing shared file for dpid: " . $dpid);
        
        my $file = $self->{'share_file'} . "." . sprintf("%x",$dpid);
        open(my $fh, ">", $file) or $self->{'logger'}->error("Unable to open $file " . $!);
        print $fh encode_json($data);
        close($fh);
    }

}

sub _sync_database_to_network {
    my $self = shift;

    $self->{'logger'}->info("Init starting!");

    $self->_write_cache();
    my $event_id = $self->_generate_unique_event_id();
    foreach my $child (keys %{$self->{'children'}}){
	$self->send_message_to_child($child,{action => 'update_cache'},$event_id);
    }
    
    my $node_maintenances = $self->{'db'}->get_node_maintenances();
    foreach my $maintenance (@$node_maintenances) {
        $self->node_maintenance($maintenance->{'node'}->{'id'}, "start");
    }

    my $link_maintenances = $self->{'db'}->get_link_maintenances();
    foreach my $maintenance (@$link_maintenances) {
        $self->link_maintenance($maintenance->{'link'}->{'id'}, "start");
    }

    foreach my $node (keys %{$self->{'node_info'}}){
        #fire off the datapath join handler
        $self->datapath_join_handler($node);
    }

    $self->{'logger'}->info("Init complete!");
}


=head2 send_message_to_child

send a message to a child

=cut

sub send_message_to_child{
    my $self = shift;
    my $dpid = shift;
    my $message = shift;
    my $event_id = shift;

    my $rpc = $self->{'children'}->{$dpid}->{'rpc'};

    if(!defined($rpc)){
        $self->{'logger'}->error("No RPC exists for DPID: " . sprintf("%x", $dpid));
	$self->make_baby($dpid);
	return;
    }

    $self->{'pending_results'}->{$event_id}->{'ts'} = time();
    $self->{'pending_results'}->{$event_id}->{'dpids'}->{$dpid} = FWDCTL_WAITING;
    
    $rpc->(encode_json($message), sub{
        my $resp = shift;
        my $result;
        eval{
            $result = decode_json($resp);
        };
        if(!defined($result)){
            $self->{'logger'}->error("Something bad happened processing response from child: " . $resp);
            $self->{'pending_results'}->{$event_id}->{'dpids'}->{$dpid} = FWDCTL_UNKNOWN;
            return;
        }
        $self->{'pending_results'}->{$event_id}->{'dpids'}->{$dpid} = $result->{'success'};
        $self->{'node_rules'}->{$dpid} = $result->{'total_rules'};
           });
}

=head2 check_child_status

    sends an echo request to the child

=cut

sub check_child_status{
    my $self = shift;
    $self->{'logger'}->debug("Checking on child status");
    my $event_id = $self->_generate_unique_event_id();
    foreach my $dpid (keys %{$self->{'children'}}){
        $self->{'logger'}->debug("checking on child: " . $dpid);
        my $child = $self->{'children'}->{$dpid};
        my $corr_id = $self->send_message_to_child($dpid,{action => 'echo'},$event_id);            
    }
    return (1,$event_id);
}

=head2 reap_old_events

=cut

sub reap_old_events{
    my $self = shift;

    my $time = time();
    foreach my $event (keys (%{$self->{'pending_events'}})){

        if($self->{'pending_events'}->{$event}->{'ts'} + TIMEOUT > $time){
            delete $self->{'pending_events'}->{$event};
        }

    }


}


=head2 datapath_join_handler

=cut

sub datapath_join_handler{
    my $self   = shift;
    my $dpid   = shift;

    my $dpid_str  = sprintf("%x",$dpid);

    if(!$self->{'node_info'}->{$dpid}){
        $self->{'node_info'}->{$dpid}->{'dpid_str'} = sprintf("%x",$dpid);
        $self->{'logger'}->warn("Detected a new unconfigured switch with DPID: " . $dpid . " initializing... ");
        $self->_write_cache();
    }

    $self->{'logger'}->warn("switch with dpid: " . $dpid_str . " has join");
    my $event_id = $self->_generate_unique_event_id();
    if(defined($self->{'children'}->{$dpid}->{'rpc'})){
        #process is running nothing to do!
        $self->{'logger'}->debug("Child already exists... send datapath join event");
        $self->send_message_to_child($dpid,{action => 'datapath_join'},$event_id);
    }else{
        $self->{'logger'}->debug("Child does not exist... creating");
        #sherpa will you make my babies!
        $self->make_baby($dpid);
        $self->{'logger'}->debug("Baby was created!");
    }

    $self->{'logger'}->info("End DP Join handler for : " . $dpid_str);

}

=head2 make_baby
make baby is a throw back to sherpa...
have to give Ed the credit for most 
awesome function name ever

=cut
sub make_baby{
    my $self = shift;
    my $dpid = shift;
    
    $self->{'logger'}->debug("Before the fork");
    my %args;
    $args{'dpid'} = $dpid;
    $args{'share_file'} = $self->{'share_file'}. "." . sprintf("%x",$dpid);


    my $proc = AnyEvent::Fork->new->require("AnyEvent::Fork::RPC::Async","OESS::FWDCTL::Switch","JSON")->eval('
use strict;
use warnings;
use JSON::XS;
Log::Log4perl::init_and_watch("/etc/oess/logging.conf",10);
my $switch;
my $logger;

sub new{
    my %args = @_;

    $logger = Log::Log4perl->get_logger("OESS.FWDCTL.MASTER");
    $logger->info("Creating child for dpid: " . $args{"dpid"});
    $switch = OESS::FWDCTL::Switch->new( dpid => $args{"dpid"},
                                         share_file => $args{"share_file"});
}

sub run{
    my $fh = shift;
    my $message = shift;

    my $action;
    eval{
        $action = decode_json($message);
    };
    if(!defined($action)){
        $logger->error("invalid JSON blob: " . $message);
        return;
    }
    my $res = $switch->process_event($action);
    $fh->(encode_json($res));
}
')->fork->send_arg(%args)->AnyEvent::Fork::RPC::run("run",
                                                                   async => 1,
                                                                   on_event => sub { $self->{'logger'}->debug("Received an Event!!!: " . $_[0]);},
                                                                   on_error => sub { $self->{'logger'}->warn("Receive an error from child" . $_[0])},
                                                                   on_destroy => sub { $self->{'logger'}->warn("OH NO!! CHILD DIED"); $self->{'children'}->{$dpid}->{'rpc'} = undef; $self->datapath_join_handler($dpid);},
                                                                   init => "new");
    $self->{'logger'}->debug("After the fork");
    $self->{'children'}->{$dpid}->{'rpc'} = $proc;
    return;
    
}

=head2 _restore_down_circuits

=cut

sub _restore_down_circuits{

    my $self = shift;
    my %params = @_;
    my $circuits = $params{'circuits'};
    my $link_name = $params{'link_name'};

    #this loop is for automatic restoration when both paths are down
    my %dpids;

    $self->{'logger'}->debug("In _restore_down_circuits with circuits: ".@$circuits);
    my $circuit_notification_data = [];

    $self->{'db'}->_start_transaction();

    foreach my $circuit (@$circuits) {

        my $ckt = $self->get_ckt_object( $circuit->{'circuit_id'});
        
        if(!defined($ckt)){
            $self->{'logger'}->error("No Circuit could be created or found for circuit: " . $circuit->{'circuit_id'});
            next;
        }

        if($ckt->has_backup_path()){

            #if the restored path is the backup
            if ($circuit->{'path_type'} eq 'backup') {

                if ($ckt->get_path_status(path => 'primary', link_status => $self->{'link_status'} ) == OESS_LINK_DOWN) {
                    #if the primary path is down and the backup path is up and is not active fail over
                    
                    if ($ckt->get_path_status( path => 'backup', link_status => $self->{'link_status'} ) && $ckt->get_active_path() ne 'backup'){
                        #bring it back to this path
                        my $success = $ckt->change_path( do_commit => 0, user_id => SYSTEM_USER, reason => "CHANGE PATH: restored trunk:$link_name moving to backup path");
                        $self->{'logger'}->warn("vlan:" . $ckt->get_name() ." id:" . $ckt->get_id() . " affected by trunk:$link_name moving to alternate path");

                        if (! $success) {
                            $self->{'logger'}->error("vlan:" . $ckt->get_name() . " id:" . $ckt->get_id() . " affected by trunk:$link_name has NOT been moved to alternate path due to error: " . $ckt->error());
                            next;
                        }

                        my @dpids = $self->_get_endpoint_dpids($ckt->get_id());
                        foreach my $dpid (@dpids){
                            push(@{$dpids{$dpid}},$ckt->get_id());
                        }

                        $self->{'circuit_status'}->{$ckt->get_id()} = OESS_CIRCUIT_UP;
                        #send notification
                        $circuit->{'status'} = 'up';
                        $circuit->{'reason'} = 'the backup path has been restored';
                        $circuit->{'type'} = 'restored';
                        #$self->emit_signal("circuit_notification", $circuit );
                        push (@$circuit_notification_data, $circuit)
                    } elsif ($ckt->get_path_status(path => 'backup', link_status => $self->{'link_status'}) && $ckt->get_active_path() eq 'backup'){
                        #circuit was on backup path, and backup path is now up
                        $self->{'logger'}->warn("vlan:" . $ckt->get_name() ." id:" . $ckt->get_id() . " affected by trunk:$link_name was restored");
                        next if $self->{'circuit_status'}->{$circuit->{'circuit_id'}} == OESS_CIRCUIT_UP;
                        #send notification on restore
                        $circuit->{'status'} = 'up';
                        $circuit->{'reason'} = 'the backup path has been restored';
                        $circuit->{'type'} = 'restored';
                        #$self->emit_signal("circuit_notification", $circuit);
                        push (@$circuit_notification_data, $circuit);
                        $self->{'circuit_status'}->{$circuit->{'circuit_id'}} = OESS_CIRCUIT_UP;
                } else {
                        #both paths are down...
                        #do not do anything
                    }
                }

            } else {
                #the primary path is the one that was restored

                if ($ckt->get_active_path() eq 'primary'){
                    #nothing to do here as we are already on the primary path
                    $self->{'logger'}->debug("ckt:" . $circuit->{'circuit_id'} . " primary path restored and we were alread on it");
                    next if($self->{'circuit_status'}{$circuit->{'circuit_id'}} == OESS_CIRCUIT_UP);
                    $self->{'circuit_status'}->{$circuit->{'circuit_id'}} = OESS_CIRCUIT_UP;
                    #send notifcation on restore
                    $circuit->{'status'} = 'up';
                    $circuit->{'reason'} = 'the primary path has been restored';
                    $circuit->{'type'} = 'restored';
                    #$self->emit_signal("circuit_notification", $circuit );
                    push (@$circuit_notification_data, $circuit)
                } else {

                    if ($ckt->get_path_status( path => 'primary', link_status => $self->{'link_status'} )) {
                        if ($ckt->get_path_status(path => 'backup', link_status => $self->{'link_status'})) {
                            #ok the backup path is up and active... and restore to primary is not 0
                            if ($ckt->get_restore_to_primary() > 0) {
                                #schedule the change path
                                $self->{'logger'}->warn("vlan: " . $ckt->get_name() . " id: " . $ckt->get_id() . " is currently on backup path, scheduling restore to primary for " . $ckt->get_restore_to_primary() . " minutes from now");
                                $self->{'db'}->schedule_path_change( circuit_id => $ckt->get_id(),
                                                                     path => 'primary',
                                                                     when => time() + (60 * $ckt->get_restore_to_primary()),
                                                                     user_id => SYSTEM_USER,
                                                                     workgroup_id => $circuit->{'workgroup_id'},
                                                                     reason => "circuit configuration specified restore to primary after " . $ckt->get_restore_to_primary() . "minutes"  );
                            } else {
                                #restore to primary is off
                            }
                        } else {
                            #ok the primary path is up and the backup is down and active... lets move now
                            my $success = $ckt->change_path( do_commit => 0, user_id => SYSTEM_USER, reason => "CHANGE PATH: restored trunk:$link_name moving to primary path");
                            $self->{'logger'}->warn("vlan:" . $ckt->get_id() ." id:" . $ckt->get_id() . " affected by trunk:$link_name moving to alternate path");
                            if (! $success) {
                                $self->{'logger'}->error("vlan:" . $ckt->get_id() . " id:" . $ckt->get_id() . " affected by trunk:$link_name has NOT been moved to alternate path due to error: " . $ckt->error());
                                next;
                            }

                            my @dpids = $self->_get_endpoint_dpids($ckt->get_id());
                            foreach my $dpid (@dpids){
                                push(@{$dpids{$dpid}},$ckt->get_id());
                            }

                            $self->{'circuit_status'}->{$circuit->{'circuit_id'}} = OESS_CIRCUIT_UP;
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
            next if($self->{'circuit_status'}->{$circuit->{'circuit_id'}} == OESS_CIRCUIT_UP);
            $self->{'circuit_status'}->{$circuit->{'circuit_id'}} = OESS_CIRCUIT_UP;
            #send restore notification
            $circuit->{'status'} = 'up';
            $circuit->{'reason'} = 'the primary path has been restored';
            $circuit->{'type'} = 'restored';
            #$self->emit_signal("circuit_notification", $circuit );
            push (@$circuit_notification_data, $circuit);
        }
    }

    my $event_id = $self->_generate_unique_event_id();
    #write the cache
    $self->_write_cache();
    my $result = FWDCTL_SUCCESS;
    #signal all the children

    foreach my $dpid (keys %dpids){
        $self->{'logger'}->debug("Telling child: " . $dpid . " that its time to work!");
        $self->send_message_to_child($dpid,{action => 'change_path', circuits => $dpids{$dpid}},$event_id);
    }

    #commit our changes to the database
    $self->{'db'}->_commit();
    if ( $circuit_notification_data && scalar(@$circuit_notification_data) ){
        $self->emit_signal("circuit_notification", {
                                                    "type" => 'link_up',
                                                    "link_name" => $link_name,
                                                    "affected_circuits" => $circuit_notification_data
                                                   }
                          );
    }
}

=head2 _fail_over_circuits

=cut

sub _fail_over_circuits{
    my $self = shift;
    my %params = @_;

    my $circuits = $params{'circuits'};
    my $link_name = $params{'link_name'};

    my %dpids;

    $self->{'logger'}->debug("in _fail_over_circuits with circuits: ".@$circuits);
    my $circuit_infos;
    
    $self->{'db'}->_start_transaction();

    foreach my $circuit_info (@$circuits) {
        my $circuit_id   = $circuit_info->{'id'};
        my $circuit_name = $circuit_info->{'name'};
        
        my $circuit = $self->get_ckt_object( $circuit_id );
        
        if(!defined($circuit)){
            $self->{'logger'}->error("Unable to create or find a circuit object for $circuit_id");
            next;
        }

        if($circuit->has_backup_path()){
            
            my $current_path = $circuit->get_active_path();
            
            $self->{'logger'}->debug("Circuits current active path: " . $current_path);
            #if we know the current path, then the alternate is the other
            my $alternate_path = 'primary';
            if($current_path eq 'primary'){
                $alternate_path = 'backup';
            }
            
            #check the alternate paths status
            if($circuit->get_path_status( path => $alternate_path, link_status => $self->{'link_status'})){
                my $success = $circuit->change_path( do_commit => 0, user_id => SYSTEM_USER, reason => "CHANGE PATH: affected by trunk:$link_name moving to $alternate_path path");
                $self->{'logger'}->warn("vlan:$circuit_name id:$circuit_id affected by trunk:$link_name moving to alternate path");
                
                #failed to move the path
                if (! $success) {
                    $circuit_info->{'status'} = "unknown";
                    $circuit_info->{'reason'} = "Attempted to switch to alternate path, however an unknown error occured.";
                    $circuit_info->{'circuit_id'} = $circuit_info->{'id'};
                    $self->{'logger'}->error("vlan:$circuit_name id:$circuit_id affected by trunk:$link_name has NOT been moved to alternate path due to error: " . $circuit->error());
                    #$self->emit_signal("circuit_notification", $circuit_info );
                    push(@$circuit_infos, $circuit_info);
                    $self->{'circuit_status'}->{$circuit_id} = OESS_CIRCUIT_UNKNOWN;
                    next;
                }
                
                my @dpids = $self->_get_endpoint_dpids($circuit_id);
                foreach my $dpid (@dpids){
                    push(@{$dpids{$dpid}},$circuit_id);
                }
                
                
                $circuit_info->{'status'} = "up";
                $circuit_info->{'reason'} = "Failed to Alternate Path";
                $circuit_info->{'circuit_id'} = $circuit_info->{'id'};
                push (@$circuit_infos, $circuit_info);
                $self->{'circuit_status'}->{$circuit_id} = OESS_CIRCUIT_UP;
                
            }
            else{
                
                $self->{'logger'}->warn("vlan:$circuit_name id:$circuit_id affected by trunk:$link_name has a backup path, but it is down as well.  Not failing over");
                $circuit_info->{'status'} = "down";
                $circuit_info->{'reason'} = "Attempted to fail to alternate path, however the primary and backup path are both down";
                $circuit_info->{'circuit_id'} = $circuit_info->{'id'};
                next if($self->{'circuit_status'}->{$circuit_id} == OESS_CIRCUIT_DOWN);
                #$self->emit_signal("circuit_notification", $circuit_info );
                push (@$circuit_infos, $circuit_info);
                $self->{'circuit_status'}->{$circuit_id} = OESS_CIRCUIT_DOWN;
                next;
                
            }
        }
        else{
            
            # this is probably where we would put the dynamic backup calculation
            # when we get there.
            $self->{'logger'}->info("vlan:$circuit_name id:$circuit_id affected by trunk:$link_name has no alternate path and is down");
            $circuit_info->{'status'} = "down";
            $circuit_info->{'reason'} = "Could not fail over: no backup path configured";
            
            $circuit_info->{'circuit_id'} = $circuit_info->{'id'};
            next if($self->{'circuit_status'}->{$circuit_id} == OESS_CIRCUIT_DOWN);
            #$self->emit_signal("circuit_notification", $circuit_info);
            push (@$circuit_infos, $circuit_info);
            $self->{'circuit_status'}->{$circuit_id} = OESS_CIRCUIT_DOWN;
            
        }
        
    }
    my $event_id = $self->_generate_unique_event_id();

    #write the cache
    $self->_write_cache();

    my $result = FWDCTL_SUCCESS;

    foreach my $dpid (keys %dpids){
        $self->send_message_to_child($dpid,{action => 'change_path', circuits => $dpids{$dpid}}, $event_id);
    }

    $self->{'db'}->_commit();
    $self->{'logger'}->debug("Completed sending the requests");
    
        
    if ( $circuit_infos && scalar(@$circuit_infos) ) {
        $self->emit_signal("circuit_notification", { "type" => 'link_down',
                                                     "link_name" => $link_name,
                                                     "affected_circuits" => $circuit_infos
                           });
    }
    
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

    $self->{'logger'}->error("Port Status event!");

    my $port_name   = $info->{'name'};
    my $port_number = $info->{'port_no'};
    my $link_status = $info->{'link'};

    #basic assertions
    $self->{'logger'}->error("invalid port number") && $self->{'logger'}->logcluck() && exit 1 if(!defined($port_number) || $port_number > 65535 || $port_number < 0);
    $self->{'logger'}->error("dpid was not defined") && $self->{'logger'}->logcluck() && exit 1 if(!defined($dpid));
    $self->{'logger'}->error("invalid port status reason") && $self->{'logger'}->logcluck() && exit 1 if($reason < 0 || $reason > 2);
    $self->{'logger'}->error("invalid link status: '$link_status'") && $self->{'logger'}->logcluck() && exit 1 if(!defined($link_status) || $link_status < 0 || $link_status > 1);

    my $node_details = $self->{'db'}->get_node_by_dpid( dpid => $dpid );

    #assert we found the node in the db, its really bad if it isn't there!
    $self->{'logger'}->error("node with DPID: " . $dpid . " was not found in the DB") && $self->{'logger'}->logcluck() && exit 1 if(!defined($node_details));
    
    my $link_info   = $self->{'db'}->get_link_by_dpid_and_port(dpid => $dpid,
                                                               port => $port_number);

    if (! defined $link_info || @$link_info < 1) {
        #--- no link means edge port
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
                if (!defined $affected_circuits) {
                    $self->{'logger'}->error("Error getting affected circuits: " . $self->{'db'}->get_error());
                    return;
                }

                # Fail over affected circuits if link is not in maintenance mode.
                # Ignore traffic migration when in maintenance mode.
                if (!exists $self->{'link_maintenance'}->{$link_id}) {
                    $self->{'link_status'}->{$link_name} = OESS_LINK_DOWN;
                    $self->_fail_over_circuits( circuits => $affected_circuits, link_name => $link_name );
                    $self->_cancel_restorations( link_id => $link_id);
                }
            }

            #--- when a port comes back up determine if any circuits that are currently down
            #--- can be restored by bringing it back up over to this path, we do not restore by default
            else {
                $self->{'logger'}->warn("sw:$sw_name dpid:$dpid_str port $port_name trunk $link_name is up");

                # Restore affected circuits if link is not in maintenance mode.
                # Ignore traffic migration when in maintenance mode.
                if (!exists $self->{'link_maintenance'}->{$link_id}) {
                    $self->{'link_status'}->{$link_name} = OESS_LINK_UP;
                    my $circuits = $self->{'db'}->get_circuits_on_link( link_id => $link_id);
                    $self->_restore_down_circuits( circuits => $circuits, link_name => $link_name );
                }
            }
        }
        case(OFPPR_DELETE){
            if (defined($link_id) && defined($link_name)) {
                $self->{'logger'}->warn("sw:$sw_name dpid:$dpid_str port $port_name trunk $link_name has been removed");
            } else {
                $self->{'logger'}->warn("sw:$sw_name dpid:$dpid_str port $port_name has been removed");
            }
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

    $self->{'db'}->_start_transaction();

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

    $self->{'db'}->_commit();

}

=head2 topo_port_status

=cut

sub topo_port_status{
    my $self   = shift;
    my $dpid   = shift;
    my $reason = shift;
    my $info   = shift;

    $self->{'logger'}->debug("TOPO Port status");

    my $port_name   = $info->{'name'};
    my $port_number = $info->{'port_no'};
    my $link_status = $info->{'link'};

    #basic assertions
    $self->{'logger'}->error("invalid port number") && $self->{'logger'}->logcluck() && exit 1 if(!defined($port_number) || $port_number > 65535 || $port_number < 0);
    $self->{'logger'}->error("dpid was not defined") && $self->{'logger'}->logcluck() && exit 1 if(!defined($dpid));
    $self->{'logger'}->error("invalid port status reason") && $self->{'logger'}->logcluck() && exit 1 && die if($reason < 0 || $reason > 2);
    $self->{'logger'}->error("invalid link status '$link_status'") && $self->{'logger'}->logcluck() && exit 1 if(!defined($link_status) || $link_status < 0 || $link_status > 1);

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

    my $ep = $self->{'db'}->get_link_endpoints( link_id => $link_id);

    my $sw_name   = $node->{'name'};
    my $dpid_str  = sprintf("%x",$dpid);

    switch ($reason) {
	#add case
	case OFPPR_ADD {
            if (defined($link_id) && defined($link_name)) {
                $self->{'logger'}->warn("sw:$sw_name dpid:$dpid_str port $port_name trunk $link_name has been added");
                
                #update all circuits involving this link.
                my $circuits = $self->{'db'}->get_circuits_on_link(link_id => $link_id);
                foreach my $circuit (@$circuits) {
                    my $circuit_id = $circuit->{'circuit_id'};
                    my $ckt = $self->get_ckt_object( $circuit_id );
                    $ckt->update_circuit_details( link_status => $self->{'link_status'});
                }
		$self->_write_cache();

		my $node_a = $self->{'db'}->get_node_by_interface_id( interface_id => $ep->[0]->{'interface_id'} );
		my $node_z = $self->{'db'}->get_node_by_interface_id( interface_id => $ep->[1]->{'interface_id'} );

                $self->force_sync($node_a->{'dpid'});
		$self->force_sync($node_z->{'dpid'});

                if($self->{'link_status'}->{$link_name} != $link_status){
                    $reason = OFPPR_MODIFY;
                    $self->port_status($dpid,$reason,$info);
                }else{
                    #do nothing... everything already lines up
                }

            } else {
                $self->{'logger'}->warn("sw:$sw_name dpid:$dpid_str port $port_name has been added");
                #need to signal a diff of the node...
                $self->force_sync($dpid);
            }

	}case OFPPR_DELETE {
            if (defined($link_id) && defined($link_name)) {
                $self->{'logger'}->warn("sw:$sw_name dpid:$dpid_str port $port_name trunk $link_name has been removed");
            } else {
                $self->{'logger'}->warn("sw:$sw_name dpid:$dpid_str port $port_name has been removed");
            }
            $reason = OFPPR_MODIFY;
            $self->port_status($dpid,$reason,$info);
            $self->force_sync($dpid);
	} else {
            #we should never get here!
            $self->port_status($dpid,$reason,$info);
            $self->force_sync($dpid);
	}
    }

    $self->{'logger'}->debug("TOPO Port status complete");

    return;

}

=head2 link_event

=cut

sub link_event{

}

=head2 fv_link_event

=cut

sub fv_link_event{
    my $self = shift;
    my $link_name = shift;
    my $state = shift;
    
    my $link = $self->{'db'}->get_link( link_name => $link_name);

    if(!defined($link)){
	$self->{'logger'}->error("FV determined link " . $link_name . " is down but DB does not contain a link with that name");
	return 0;
    }

    if ($state == OESS_LINK_DOWN) {

	$self->{'logger'}->warn("FV determined link " . $link_name . " is down");

	my $affected_circuits = $self->{'db'}->get_affected_circuits_by_link_id(link_id => $link->{'link_id'});

	if (! defined $affected_circuits) {
	    $self->{'logger'}->error("Error getting affected circuits: " . $self->{'db'}->get_error());
	    return 0;
	}
	
	$self->{'link_status'}->{$link_name} = OESS_LINK_DOWN;
	#fail over affected circuits
        if (!exists $self->{'link_maintenance'}->{$link->{'link_id'}}) {
            $self->_fail_over_circuits( circuits => $affected_circuits, link_name => $link_name );
            $self->_cancel_restorations( link_id => $link->{'link_id'});
            $self->{'logger'}->warn("FV Link down complete!");
        }
    }
    #--- when a port comes back up determine if any circuits that are currently down
    #--- can be restored by bringing it back up over to this path, we do not restore by default
    else {
	$self->{'logger'}->warn("FV has determined link $link_name is up");
	$self->{'link_status'}->{$link_name} = OESS_LINK_UP;

        if (!exists $self->{'link_maintenance'}->{$link->{'link_id'}}) {
            my $circuits = $self->{'db'}->get_circuits_on_link( link_id => $link->{'link_id'});
            $self->_restore_down_circuits( circuits => $circuits, link_name => $link_name );
            $self->{'logger'}->warn("FV Link Up completed");
        }
    }

    return 1;
}

=head2 addVlan

=cut

sub addVlan {
    my $self       = shift;
    my $circuit_id = shift;

    $self->{'logger'}->error("Circuit ID required") && $self->{'logger'}->logconfess() if(!defined($circuit_id));

    $self->{'logger'}->info("addVlan: $circuit_id");

    my $event_id = $self->_generate_unique_event_id();

    my $ckt = $self->get_ckt_object( $circuit_id );
    if(!defined($ckt)){
        return (FWDCTL_FAILURE,$event_id);
    }

    $ckt->update_circuit_details();
    if($ckt->{'details'}->{'state'} eq 'decom'){
	return (FWDCTL_FAILURE,$event_id);
    }

    $self->_write_cache();

    #get all the DPIDs involved and remove the flows
    my $flows = $ckt->get_flows();
    my %dpids;
    foreach my $flow (@$flows){
        $dpids{$flow->get_dpid()} = 1;
    }

    my $result = FWDCTL_SUCCESS;

    my $details = $self->{'db'}->get_circuit_details(circuit_id => $circuit_id);


    if ($details->{'state'} eq "deploying" || $details->{'state'} eq "scheduled") {
        
        my $state = $details->{'state'};
        
#        $self->{'db'}->update_circuit_state(circuit_id          => $circuit_id,
#                                            old_state           => $state,
#                                            new_state           => 'active',
#                                            modified_by_user_id => SYSTEM_USER,
#                                            reason              => 'Circuit successfully provisioned' );

        $self->{'logger'}->error($self->{'db'}->get_error());
    }

    #TODO: WHY IS THERE HERE??? Seems like we can remove this...
    $self->{'db'}->update_circuit_path_state(circuit_id  => $circuit_id,
                                             old_state   => 'deploying',
                                             new_state   => 'active');
    
    $self->{'circuit_status'}->{$circuit_id} = OESS_CIRCUIT_UP;

    foreach my $dpid (keys %dpids){
        $self->send_message_to_child($dpid,{action => 'add_vlan', circuit => $circuit_id}, $event_id);
    }

    return ($result,$event_id);
    
}

=head2 deleteVlan

=cut

sub deleteVlan {
    my $self = shift;
    my $circuit_id = shift;

    $self->{'logger'}->error("Circuit ID required") && $self->{'logger'}->logconfess() if(!defined($circuit_id));

    my $ckt = $self->get_ckt_object( $circuit_id );
    my $event_id = $self->_generate_unique_event_id();
    if(!defined($ckt)){
        return (FWDCTL_FAILURE,$event_id);
    }
    
    $ckt->update_circuit_details();

    if($ckt->{'details'}->{'state'} eq 'decom'){
	return (FWDCTL_FAILURE,$event_id);
    }
    

    #update the cache
    $self->_write_cache();
    
    #get all the DPIDs involved and remove the flows
    my $flows = $ckt->get_flows();
    my %dpids;
    foreach my $flow (@$flows){
        $dpids{$flow->get_dpid()} = 1;
    }
   
    my $result = FWDCTL_SUCCESS;

    foreach my $dpid (keys %dpids){
        $self->send_message_to_child($dpid,{action => 'remove_vlan', circuit => $circuit_id},$event_id);
    }

    return ($result,$event_id);
}


=head2 changeVlanPath

=cut

sub changeVlanPath {
    my $self = shift;
    my $circuit_id = shift;

    $self->{'logger'}->error("Circuit ID required") && $self->{'logger'}->logconfess() if(!defined($circuit_id));

    my $ckt = $self->get_ckt_object( $circuit_id );
    
    #update the ckt model (for us and the share)
    $ckt->update_circuit_details();
    $self->_write_cache();
    #we just need to know the devices to touch backup/primary they 
    #will be the same just different flows
    my $endpoint_flows = $ckt->get_endpoint_flows(path => 'primary');
    my %dpids;
    foreach my $flow (@$endpoint_flows){
        $dpids{$flow->get_dpid()} = 1;
    }
    
    my $event_id = $self->_generate_unique_event_id();

    my $result = FWDCTL_SUCCESS;
    foreach my $dpid (keys %dpids){
        $self->send_message_to_child($dpid,{action => 'change_path', circuits => [$circuit_id]}, $event_id);
    }
    $self->{'logger'}->warn("Event ID: " . $event_id);
    return ($result,$event_id);
}

=head2 get_event_status

=cut

sub get_event_status{
    my $self = shift;
    my $event_id = shift;

    $self->{'logger'}->debug("Looking for event: " . $event_id);
    if(defined($self->{'pending_results'}->{$event_id})){

        my $results = $self->{'pending_results'}->{$event_id}->{'dpids'};
        
        foreach my $dpid (keys %{$results}){
            $self->{'logger'}->debug("DPID: " . $dpid . " reports status: " . $results->{$dpid});
            if($results->{$dpid} == FWDCTL_WAITING){
                $self->{'logger'}->debug("Event: $event_id dpid $dpid reports still waiting");
                return FWDCTL_WAITING;
            }elsif($results->{$dpid} == FWDCTL_FAILURE){
                $self->{'logger'}->debug("Event : $event_id dpid $dpid reports error!");
                return FWDCTL_FAILURE;
            }
        }
        #done waiting and was success!
        $self->{'logger'}->debug("Event $event_id is complete!!");
        return FWDCTL_SUCCESS;
    }else{
        #no known event by that ID
        return FWDCTL_UNKNOWN;
    }
}

sub _get_endpoint_dpids{
    my $self = shift;
    my $ckt_id = shift;
    my $ckt = $self->get_ckt_object($ckt_id);
    
    my $endpoint_flows = $ckt->get_endpoint_flows(path => 'primary');
    my %dpids;
    foreach my $flow (@$endpoint_flows){
        $dpids{$flow->get_dpid()} = 1;
    }    
    
    return keys %dpids;

}

sub _generate_unique_event_id{
    my $self = shift;
    return $self->{'uuid'}->to_string($self->{'uuid'}->create());
}

=head2 get_ckt_object

=cut

sub get_ckt_object{
    my $self =shift;
    my $ckt_id = shift;
    
    my $ckt = $self->{'circuit'}->{$ckt_id};
    
    if(!defined($ckt)){
        $ckt = OESS::Circuit->new( circuit_id => $ckt_id, db => $self->{'db'});
        $self->{'circuit'}->{$ckt->get_id()} = $ckt;
    }
    
    if(!defined($ckt)){
        $self->{'logger'}->error("Error occured creating circuit: " . $ckt_id);
    }

    return $ckt;
}

1;
