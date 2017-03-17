#!/usr/bin/perl
##------ NDDI OESS Forwarding Control
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

use GRNOC::WebService::Regex;
use Data::Dumper;
use Socket;
use POSIX;
use Log::Log4perl;
use Switch;

use Time::HiRes qw(gettimeofday tv_interval);

use OESS::FlowRule;
use OESS::FWDCTL::Switch;
use OESS::Database;
use OESS::Topology;
use OESS::Circuit;

use GRNOC::RabbitMQ::Method;
use GRNOC::RabbitMQ::Client;
use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Client;
use AnyEvent;
use AnyEvent::Fork;


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
    my $self = \%params;
    bless $self, $class;

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.FWDCTL.MASTER');

    if(!defined($self->{'config'})){
        $self->{'config'} = "/etc/oess/database.xml";
    }

    $self->{'db'} = OESS::Database->new( config_file => $self->{'config'} );

    my $fwdctl_dispatcher = GRNOC::RabbitMQ::Dispatcher->new( host => $self->{'db'}->{'rabbitMQ'}->{'host'},
							      port => $self->{'db'}->{'rabbitMQ'}->{'port'},
							      user => $self->{'db'}->{'rabbitMQ'}->{'user'},
							      pass => $self->{'db'}->{'rabbitMQ'}->{'pass'},
							      exchange => 'OESS',
							      queue => 'OF-FWDCTL',
							      topic => "OF.FWDCTL.RPC");

    $self->register_rpc_methods( $fwdctl_dispatcher );
    $self->register_nox_events( $fwdctl_dispatcher );
    
    $self->{'fwdctl_dispatcher'} = $fwdctl_dispatcher;


    $self->{'fwdctl_events'} = GRNOC::RabbitMQ::Client->new( host => $self->{'db'}->{'rabbitMQ'}->{'host'},
							     port => $self->{'db'}->{'rabbitMQ'}->{'port'},
							     user => $self->{'db'}->{'rabbitMQ'}->{'user'},
							     pass => $self->{'db'}->{'rabbitMQ'}->{'pass'},
							     exchange => 'OESS',
							     topic => 'OF.FWDCTL.event');
    $self->{'logger'}->info("RabbitMQ ready to go!");

    # When this process receives sigterm send an event to notify all
    # children to exit cleanly.
    $SIG{TERM} = sub {
        $self->stop();
    };

    #from TOPO startup
    my $nodes = $self->{'db'}->get_current_nodes();
    foreach my $node (@$nodes) {
	next if (!$node->{'openflow'});
        $self->{'db'}->update_node_operational_state(node_id => $node->{'node_id'}, state => 'down');
    }

    my $topo = OESS::Topology->new( db => $self->{'db'} );
    if (! $topo) {
        $self->{'logger'}->fatal("Could not initialize topo library");
        exit(1);
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

    $self->update_cache({
        success_callback => sub {
            $self->{'logger'}->info("Initial call to update_cache was a success!");
        },
        error_callback => sub {
            $self->{'logger'}->error("Initial call to update_cache was a failure!");
        }},
        {circuit_id => {value => -1}}
    );

    $self->{'logger'}->info("FWDCTL INIT COMPLETE");
    return $self;
}

sub register_nox_events{
    my $self = shift;
    my $d = shift;
    
    my $method = GRNOC::RabbitMQ::Method->new( name => "datapath_leave",
					       topic => "OF.NOX.event",
					       callback => sub { $self->datapath_leave_handler(@_) },
					       description => "signals a node has left the controller");

    $method->add_input_parameter( name => "dpid",
				  description => "The DPID of the switch which left",
				  required => 1,
				  pattern => $GRNOC::WebService::Regex::NUMBER_ID);

    $d->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => "datapath_join",
                                            topic => "OF.NOX.event",
                                            callback => sub { $self->datapath_join_handler(@_) },
                                            description => "signals a node has joined the controller");

    $method->add_input_parameter( name => "dpid",
				  description => "The DPID of the switch which joined",
				  required => 1,
				  pattern => $GRNOC::WebService::Regex::NUMBER_ID);

    $method->add_input_parameter( name => "ip",
				  description => "The IP of the swich which has joined",
				  required => 1,
				  pattern => $GRNOC::WebService::Regex::NUMBER_ID);

    $method->add_input_parameter( name => "ports",
                                  description => "Array of OpenFlow port structs",
                                  required => 1,
                                  schema => { 'type'  => 'array',
                                              'items' => [ 'type' => 'object',
                                                           'properties' => { 'hw_addr'    => {'type' => 'number'},
                                                                             'curr'       => {'type' => 'number'},
                                                                             'name'       => {'type' => 'string'},
                                                                             'speed'      => {'type' => 'number'},
                                                                             'supported'  => {'type' => 'number'},
                                                                             'enabled'    => {'type' => 'number'}, # bool
                                                                             'flood'      => {'type' => 'number'}, # bool
                                                                             'state'      => {'type' => 'number'},
                                                                             'link'       => {'type' => 'number'}, # bool
                                                                             'advertised' => {'type' => 'number'},
                                                                             'peer'       => {'type' => 'number'},
                                                                             'config'     => {'type' => 'number'},
                                                                             'port_no'    => {'type' => 'number'}
                                                                           }
                                                         ]
                                            } );
    $d->register_method($method);

    
    $method = GRNOC::RabbitMQ::Method->new( name => "link_event",
					    topic => "OF.NOX.event",
					    callback => sub { $self->link_event(@_) },
					    description => "signals a link event has happened");
    $method->add_input_parameter( name => "dpsrc",
				  description => "The DPID of the switch which fired the link event",
				  required => 1,
				  pattern => $GRNOC::WebService::Regex::NAME_ID);
    $method->add_input_parameter( name => "dpdst",
				  description => "The DPID of the switch which fired the link event",
				  required => 1,
				  pattern => $GRNOC::WebService::Regex::NAME_ID);
    $method->add_input_parameter( name => "dport",
				  description => "The port id of the dst port which fired the link event",
				  required => 1,
				  pattern => $GRNOC::WebService::Regex::INTEGER);
    $method->add_input_parameter( name => "sport",
				  description => "The port id of the src port which fired the link event",
				  required => 1,
				  pattern => $GRNOC::WebService::Regex::INTEGER);
    $method->add_input_parameter( name => "action",
				  description => "The reason of the link event",
				  required => 1,
				  pattern => $GRNOC::WebService::Regex::TEXT);
    $d->register_method($method); 
    
    $method = GRNOC::RabbitMQ::Method->new( name => "port_status",
					    topic => "OF.NOX.event",
					    callback => sub { $self->port_status(@_) },
					    description => "signals a port status event has happened");
    
    $method->add_input_parameter( name => "dpid",
				  description => "The DPID of the switch which fired the port status event",
				  required => 1,
				  pattern => $GRNOC::WebService::Regex::NAME_ID);

    $method->add_input_parameter( name => "ofp_port_reason",
				  description => "The reason for the port status must be one of OFPPR_ADD OFPPR_DELETE OFPPR_MODIFY",
				  required => 1,
				  pattern => $GRNOC::WebService::Regex::INTEGER	);

    $method->add_input_parameter( name => "attrs",
				  description => "Details about the port that had the port status message generated on it",
				  required => 1,
				  schema => { 'type' => 'object',
					      'properties' => { 'hw_addr'     => {'type' => 'number'},
								'curr'        => {'type' => 'number'},
								'port_no'     => {'type' => 'number'},
								'link'        => {'type' => 'number'},
								'name'        => {'type' => 'string'},
								'speed'       => {'type' => 'number'},
								'supported'   => {'type' => 'number'},
								'enabled'     => {'type' => 'boolean'},
								'state'       => {'type' => 'number'},
								'link'        => {'type' => 'boolean'},
								'advertised'  => {'type' => 'number'},
								'peer'        => {'type' => 'number'},
								'config'      => {'type' => 'number'},
								'admin_state' => {'type' => 'string'},
								'status'      => {'type' => 'string'}}});
				  
    $d->register_method($method);
    
    
}

sub register_rpc_methods{
    my $self = shift;
    my $d = shift;

    my $method = GRNOC::RabbitMQ::Method->new( name => "addVlan",
                                               async => 1,
					       callback => sub { $self->addVlan(@_) },
					       description => "adds a VLAN to the network that exists in OESS DB");

    $method->add_input_parameter( name => "circuit_id",
				  description => "the circuit ID to add",
				  required => 1,
				  pattern => $GRNOC::WebService::Regex::INTEGER);

    $d->register_method($method);
    
    $method = GRNOC::RabbitMQ::Method->new( name => "deleteVlan",
                                            async => 1,
					    callback => sub { $self->deleteVlan(@_) },
					    description => "deletes a VLAN to the network that exists in OESS DB");
    
    $method->add_input_parameter( name => "circuit_id",
                                  description => "the circuit ID to delete",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::INTEGER);
    
    $d->register_method($method);
    
    
    $method = GRNOC::RabbitMQ::Method->new( name => "changeVlanPath",
                                            async => 1,
					    callback => sub { 
                                                $self->changeVlanPath(@_);
                                            },
					    description => "changes a vlan to alternate path");
    
    $method->add_input_parameter( name => "circuit_id",
                                  description => "the circuit ID to changePaths on",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::INTEGER);    
    $d->register_method($method);


    $method = GRNOC::RabbitMQ::Method->new( name => 'rules_per_switch',
					    callback => sub { $self->rules_per_switch(@_) },
					    description => "Returns the total number of flow rules currently installed on this switch");
    

    $method->add_input_parameter( name => "dpid",
                                  description => "dpid of the switch to fetch the number of rules on",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::INTEGER);

    $d->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => 'fv_link_event',
                                            async => 1,
					    callback => sub { $self->fv_link_event(@_) },
					    description => "Handles Forwarding Verfiication LInk events");
    
    $method->add_input_parameter( name => "link_name",
				  description => "the name of the link for the forwarding event",
				  required => 1,
				  pattern => $GRNOC::WebService::Regex::NAME);

    $method->add_input_parameter( name => "state",
                                  description => "the current state of the specified link",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::INTEGER);


    $d->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => 'update_cache',
                                            async => 1,
					    callback => sub { $self->update_cache(@_) },
					    description => 'Updates the circuit cache');

    
    $method->add_input_parameter( name => "circuit_id",
                                  description => "the circuit ID to delete",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::INTEGER);

    $d->register_method($method);


    $method = GRNOC::RabbitMQ::Method->new( name => 'force_sync',
                                            async => 1,
					    callback => sub { $self->force_sync(@_) },
					    description => "Forces a synchronization of the device to the cache");

    $method->add_input_parameter( name => "dpid",
                                  description => "the DPID to force sync",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::INTEGER);
    $d->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => 'get_event_status',
					    callback => sub { $self->get_event_status(@_) },
					    description => "Returns the current status of the event");

    $method->add_input_parameter( name => "event_id",
                                  description => "the event id to fetch the current state of",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::NAME_ID);

    $d->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => 'check_child_status',
                                            callback => sub { $self->check_child_status(@_) },
					    description => "Returns an event id which will return the final status of all children");
    
    $d->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => 'node_maintenance',
                                            callback => sub { $self->node_maintenance(@_) },
                                            description => "Returns an event id which will return the final status of all children");

    $method->add_input_parameter( name => "node_id",
                                  description => "the id of the node to put in maintenance",
                                  required => 1,
				  pattern => $GRNOC::WebService::Regex::INTEGER);
    
    $method->add_input_parameter( name => "state",
                                  description => "the current state of the specified link",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::TEXT);

    $d->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => 'link_maintenance',
                                            callback => sub { $self->link_maintenance(@_) },
                                            description => "Returns an event id which will return the final status of all children");

    $method->add_input_parameter( name => "link_id",
                                  description => "the id of the link to put in maintenance",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::INTEGER);

    $method->add_input_parameter( name => "state",
                                  description => "the current state of the specified link",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::TEXT);

    $d->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => 'echo',
                                            callback => sub { $self->echo(@_) },
                                            description => "Always returns 1" );
    $d->register_method($method);
}


=head2 node_maintenance

Given a node_id and maintenance state of 'start' or 'end', configure
each interface of every link on the given datapath by calling
link_maintenance.

=cut
sub node_maintenance {
    my $self  = shift;
    my $m_ref = shift;
    my $p_ref = shift;
    
    my $node_id  = $p_ref->{'node_id'}{'value'};
    my $state = $p_ref->{'state'}{'value'};;

    my $links = $self->{'db'}->get_links_by_node(node_id => $node_id);
    if (!defined $links) {
        return {status => 0};
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
        next if (!$link->{'openflow'});
        if ($state eq 'end' && defined $store{$link->{'link_id'}}) {
            $self->{'logger'}->warn("Link $link->{'link_id'} will remain under maintenance.");
        } else {
            # Insert hack here:
            # With dbus we could call methods directly. This meant that
            # dbus called functions the same way that any other code
            # would. RabbitMQ passes structs to each method. So here we
            # simulate a RabbitMQ struct to allow us to reuse
            # $self->link_maintenance.
            my $p_ref = { link_id => { value => $link->{'link_id'} },
                          state   => { value => $state } };
            $self->link_maintenance(undef, $p_ref);
        }
    }
    $self->{'logger'}->warn("Node $node_id maintenance state is $state.");
    return {status => 1};
}

=head2 link_maintenance

Given a link_id and maintenance state of 'start' or 'end' configure
each interface of a link. If state is 'start' trigger port_status events
signaling the the interfaces have went down, and store the interface_ids
in $interface_maintenance. If the state is 'end' remove the
interface_ids from $interface_maintenance.

=cut
sub link_maintenance {
    my $self  = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    my $link_id = $p_ref->{'link_id'}{'value'};
    my $state   = $p_ref->{'state'}{'value'};

    $self->{'logger'}->info("Calling link_maintenance $state on link $link_id.");

    my $link = $self->{'db'}->get_link(link_id => $link_id);
    if(!$link->{'openflow'}){
        $self->{'logger'}->error("Link " . $link->{'name'} . " is not an OpenFlow link");
        return;
    }
    

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
        return { status => 0 };
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
        return { status => 0 };
    }

    if ($state eq 'end') {
        $self->{'logger'}->debug("Simulating link down on endpoints $e1->{'id'} and $e2->{'id'}.");
        
        # It is possible for a link to be in maintenance, and connected
        # to a node under maintenance. When link maintenance has ended
        # but node maintenance has not, forwarding behavior should not
        # be modified.
        my $maintenances = $self->{'db'}->get_node_maintenances();
        foreach my $maintenance (@$maintenances) {
            my $node_id = $maintenance->{'node'}->{'id'};
            if (@$endpoints[0]->{'node_id'} == $node_id || @$endpoints[1]->{'node_id'} == $node_id) {
                $self->{'logger'}->warn("Link $link_id will remain under maintenance.");
                return {status => 1};
            }
        }

        # Once maintenance has ended remove $link_id from our
        # link_maintenance hash, and call port_status including the true
        # link state.
        if (exists $self->{'link_maintenance'}->{$link_id}) {
            delete $self->{'link_maintenance'}->{$link_id};
        }

        $self->port_status(undef,
                           {
                             dpid            => { 'value' => $node1->{'dpid'} },
                             ofp_port_reason => { 'value' => OFPPR_MODIFY } ,
                             attrs           => { 'value' => $e1 }
                           },
                           undef);
        $self->port_status(undef,
                           {
                             dpid            => { 'value' => $node2->{'dpid'} } ,
                             ofp_port_reason => { 'value' => OFPPR_MODIFY },
                             attrs           => { 'value' => $e2 }
                           },
                           undef);
        $self->{'logger'}->info("Link $link_id maintenance has ended.");
    } else {
        $self->{'logger'}->debug("Simulating link down on endpoints $e1->{'id'} and $e2->{'id'}.");
        
        # Simulate link down event by passing false link state to
        # port_status.
        $e1->{'link'} = OESS_LINK_DOWN;
        $e2->{'link'} = OESS_LINK_DOWN;

        my $link_name;
        $link_name = $self->port_status(undef,
                                        {
                                          dpid            => { 'value' => $node1->{'dpid'} },
                                          ofp_port_reason => { 'value' => OFPPR_MODIFY },
                                          attrs           => { 'value' => $e1 }
                                        },
                                        undef);
        $link_name = $self->port_status(undef,
                                        {
                                          dpid            => { 'value' => $node2->{'dpid'} },
                                          ofp_port_reason => { 'value' => OFPPR_MODIFY },
                                          attrs           => { 'value' => $e2 }
                                        },
                                        undef);

        $self->{'link_maintenance'}->{$link_id} = 1;
        $self->{'link_status'}->{$link_name} = $link_state; # Record true link state.
        $self->{'logger'}->info("Link $link_id maintenance has begun.");
    }

    return { status => 1 };
}

=head2 rules_per_switch

=cut

sub rules_per_switch{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;
    my $state = shift;

    my $dpid = $p_ref->{'dpid'}{'value'};

    $self->{'logger'}->error("Get Rules on Node: $dpid . " . Data::Dumper::Dumper($self->{'node_rules'}));
    
    if(defined($dpid) && defined($self->{'node_rules'}->{$dpid})){
        return {dpid => $dpid, rules_on_switch => $self->{'node_rules'}->{$dpid}};
    }

    return {error => "Unable to find DPID: " . $dpid};
}

=head2 force_sync

method exported to dbus to force sync a node

=cut

sub force_sync{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    my $success = $m_ref->{'success_callback'};
    my $error   = $m_ref->{'error_callback'};

    my $dpid = $p_ref->{'dpid'}->{'value'};

    $self->{'fwdctl_events'}->{'topic'} = "OF.FWDCTL.Switch." . sprintf("%x", $dpid);
    $self->{'fwdctl_events'}->force_sync(
        async_callback => sub {
            my $res = shift;
            if (defined $res->{'error'}) {
                return &$error($res);
            }

            return &$success($res);
        });
}

=head2 update_cache

updates the cache for all of the children

=cut

sub update_cache{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;
    
    my $circuit_id = $p_ref->{'circuit_id'}->{'value'};

    my $success = $m_ref->{'success_callback'};
    my $error   = $m_ref->{'error_callback'};

    if(!defined($circuit_id) || $circuit_id == -1){
        $self->{'logger'}->info("Updating Cache for entire network");
        my $res = build_cache(db => $self->{'db'}, logger => $self->{'logger'});
        $self->{'circuit'} = $res->{'ckts'};
        $self->{'link_status'} = $res->{'link_status'};
        $self->{'circuit_status'} = $res->{'circuit_status'};
        $self->{'node_info'} = $res->{'node_info'};
        $self->{'logger'}->debug("Cache update complete");

    } else {
        $self->{'logger'}->info("Updating cache for circuit: " . $circuit_id);
        my $ckt = $self->get_ckt_object($circuit_id);
        if(!defined($ckt)){
            return &$error("Couldn't get circuit $circuit_id");
        }
        $ckt->update_circuit_details();
        $self->{'logger'}->debug("Updating cache for circuit: " . $circuit_id . " complete");
    }

    #write the cache for our children
    $self->_write_cache();

    my $cv  = AnyEvent->condvar;
    my $err = '';

    $cv->begin( sub {
        if ($err ne '') {
            $self->{'logger'}->error("Failed to fully update cache: $err");
            &$error($err);
        } else {
            &$success({ status => FWDCTL_SUCCESS });
        }
    });

    foreach my $dpid (keys %{$self->{'children'}}){
        $cv->begin();

        $self->{'fwdctl_events'}->{'topic'} = "OF.FWDCTL.Switch." . sprintf("%x", $dpid);
        $self->{'fwdctl_events'}->update_cache(
            async_callback => sub {
                my $res = shift;

                if (defined $res->{'error'}) {
                    $self->{'logger'}->error($res->{'error'});
                    $err .= $res->{'error'} . "\n";
                }
                $cv->end();
            });
    }
    
    $self->{'logger'}->debug("Completed sending message to children!");
    $cv->end();
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
	next if(!$node->{'openflow'});
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
        if(!defined($ckt)){
            $self->{'logger'}->error("No Circuit could be created or found for circuit: " . $ckt_id);
            next;
        }
	next if ($ckt->get_type() eq 'mpls');

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

        my $primary_flows = $ckt->get_endpoint_flows(path => 'primary');
        foreach my $flow (@{$primary_flows}){
            push(@{$dpids{$flow->get_dpid()}{$ckt_id}{'flows'}{'endpoint'}{'primary'}}, $flow->to_canonical());
        }

        my $backup_flows = $ckt->get_endpoint_flows(path => 'backup');
        foreach my $flow (@{$backup_flows}) {
            push(@{$dpids{$flow->get_dpid()}{$ckt_id}{'flows'}{'endpoint'}{'backup'}}, $flow->to_canonical());
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
        my $p_ref = { node_id => { value => $maintenance->{'node'}->{'id'} },
                      state   => { value => "start" } };
        $self->node_maintenance(undef, $p_ref);
    }

    my $link_maintenances = $self->{'db'}->get_link_maintenances();
    foreach my $maintenance (@$link_maintenances) {
        my $p_ref = { link_id => { value => $maintenance->{'link'}->{'id'} },
                      state   => { value => "start" } };
        $self->link_maintenance(undef, $p_ref);
    }

    foreach my $node (keys %{$self->{'node_info'}}){
        #fire off the datapath join handler
        $self->datapath_join_handler($node);
    }

    # Change me
    $self->{'logger'}->info("Init complete!");
}


sub message_callback {
    my $self     = shift;
    my $dpid     = shift;
    my $event_id = shift;

    return sub {
        my $results = shift;
        $self->{'logger'}->debug("Received a response from child: " . $dpid . " for event: " . $event_id . " Dumper: " . Data::Dumper::Dumper($results));
        $self->{'pending_results'}->{$event_id}->{'dpids'}->{$dpid} = FWDCTL_UNKNOWN;
        if (!defined $results) {
            $self->{'logger'}->error("Undefined result received in message_callback.");
        } elsif (defined $results->{'error'}) {
            $self->{'logger'}->error($results->{'error'});
        }
        $self->{'node_rules'}->{$dpid} = $results->{'results'}->{'total_flows'};
	$self->{'logger'}->debug("Event: $event_id for DPID: " . $event_id . " status: " . $results->{'results'}->{'status'});
        $self->{'pending_results'}->{$event_id}->{'dpids'}->{$dpid} = $results->{'results'}->{'status'};
    }
}

=head2 send_message_to_child

send a message to a child

=cut

sub send_message_to_child{
    my $self = shift;
    my $dpid = shift;
    my $message = shift;
    my $event_id = shift;

    my $rpc    = $self->{'children'}->{$dpid}->{'rpc'};
    if(!defined($rpc)){
        $self->{'logger'}->error("No RPC exists for DPID: " . sprintf("%x", $dpid));
	$self->make_baby($dpid);
        $rpc = $self->{'children'}->{$dpid}->{'rpc'};
    }

    if(!defined($rpc)){
        $self->{'logger'}->error("OMG I couldn't create babies!!!!");
        return;
    }

    $message->{'async_callback'} = $self->message_callback($dpid, $event_id);
    my $method_name = $message->{'action'};
    delete $message->{'action'};

    $self->{'fwdctl_events'}->{'topic'} = "OF.FWDCTL.Switch." . sprintf("%x", $dpid);
    $self->{'fwdctl_events'}->$method_name( %$message );

    $self->{'pending_results'}->{$event_id}->{'ts'} = time();
    $self->{'pending_results'}->{$event_id}->{'dpids'}->{$dpid} = FWDCTL_WAITING;
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
    return {status => 1, event_id => $event_id};
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

=head2 _add_node_to_database

=cut

sub _update_node_database_state{
    my $self = shift;
    my $p_ref = shift;

    my $dpid = $p_ref->{'dpid'}{'value'};    
    my $ip = $p_ref->{'ip'}{'value'};

    $self->{'db'}->_start_transaction();
    my $node = $self->{'db'}->get_node_by_dpid(dpid => $dpid);
    my $node_id;
    if(defined($node)){
        #node exists
	$self->{'logger'}->debug("Existing node joined... updating operational state");
        #update operational state to up
        $self->{'db'}->update_node_operational_state(node_id => $node->{'node_id'}, state => 'up');
        #update admin state if it is planned (now it exists and we have some data to back this assertion)
        if ( $node->{'admin_state'} =~ /planned/){
            ##update old, create new
            $self->{'db'}->create_node_instance(node_id => $node->{'node_id'}, ipv4_addr => $ip, admin_state => 'available', dpid => $dpid, openflow => 1);
        }
        $node_id = $node->{'node_id'};

    }else{
        #insert and get the node_id
	$self->{'logger'}->info("Detected a new node... adding it to the database");
        my $node_name;
        my $addr = inet_aton($ip);
        # try to look up the name first to be all friendly like
        $node_name = gethostbyaddr($addr, AF_INET);

        # avoid any duplicate host names. The user can set this to whatever they want
        # later via the admin interface.
        my $i = 1;
        my $tmp = $node_name;
        while (my $result = $self->{'db'}->get_node_by_name(name => $tmp)){
            $tmp = $node_name . "-" . $i;
            $i++;
        }

        $node_name = $tmp;

        # default
        if (! $node_name){
            $node_name="unnamed-".$dpid;
        }

	#newtork_id 1 = local domain ALWAYS
        $node_id = $self->{'db'}->add_node(name => $node_name, operational_state => 'up', network_id => 1);
        if(!defined($node_id)){
            $self->{'db'}->_rollback();
            return;
        }
        $self->{'db'}->create_node_instance(node_id => $node_id, ipv4_addr => $ip, admin_state => 'available', dpid => $dpid, openflow => 1);
    }

    my $ports = $p_ref->{'ports'}{'value'};

    foreach my $port (@$ports){
        next if $port->{'port_no#'} > (2 ** 12);

        my $operational_state = 'up';
        my $operational_state_num = (int($port->{'state'}) & 0x1);

        if(1== $operational_state_num ){
            $operational_state='down';
        }
        my $admin_state = 'up';
        my $admin_state_num = (int($port->{'config'}) & 0x1);

        if(1 == $admin_state_num){
            $admin_state = 'down';
        }

        if($operational_state eq 'up'){
            $port->{'link'} = 1;
        }else{
            $port->{'link'} = 0;
        }

        my $int_id = $self->{'db'}->add_or_update_interface(node_id => $node_id,name => $port->{'name'}, description => $port->{'name'}, operational_state => $operational_state, port_num => $port->{'port_no'}, admin_state => $admin_state);
	
	my $link_info   = $self->{'db'}->get_link_by_dpid_and_port(dpid => $dpid,
								   port => $port->{'port_no'});
	if (defined(@$link_info[0])) {
	    my $link_id   = @$link_info[0]->{'link_id'};
	    my $link_name = @$link_info[0]->{'name'};
	    if($self->{'link_status'}->{$link_name} != $port->{'link'}){
		$self->port_status(undef,{dpid => {'value' => $dpid},
				          ofp_port_reason => {'value' => OFPPR_MODIFY},
				          attrs => {'value' => $port }},undef);
	    }
	}
    }
    $self->{'db'}->_commit();
    

}


=head2 datapath_leave_handler

=over 4

=item B<dpid> - Datapath ID of the disconnected node

=back

Called whenever a datapath disconnects from the controller.

=cut
sub datapath_leave_handler {
    my $self  = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    my $dpid = $p_ref->{'dpid'}{'value'};
    my $dpid_str = sprintf("%x",$dpid);

    $self->{'logger'}->info("Datapath LEAVE EVENT - $dpid_str");

    my $node = $self->{'db'}->get_node_by_dpid(dpid => $dpid);
    if (!defined $node) {
        $self->{'logger'}->warn("Datapath LEAVE EVENT - Datapath node is unknown to OESS.");
    }

    my $ok;
    $self->{'db'}->_start_transaction();
    $ok = $self->{'db'}->update_node_operational_state(node_id => $node->{'node_id'}, state => 'down');
    if (!$ok) {
        $self->{'logger'}->error("Could not set $dpid_str operational state to down.");
        $self->{'db'}->_rollback();
    }
    $self->{'db'}->_commit();

    return 1;
}


=head2 datapath_join_handler

=cut

sub datapath_join_handler{
    my $self   = shift;
    my $method_ref = shift;
    my $p_ref = shift;
    my $state = shift;

    my $dpid = $p_ref->{'dpid'}{'value'};
    my $dpid_str  = sprintf("%x",$dpid);

    $self->{'logger'}->error("Datapath JOIN EVENT - $dpid_str");

    $self->_update_node_database_state($p_ref);

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
    $args{'rabbitMQ_host'} = $self->{'db'}->{'rabbitMQ'}->{'host'}; 
    $args{'rabbitMQ_port'} = $self->{'db'}->{'rabbitMQ'}->{'port'};
    $args{'rabbitMQ_user'} = $self->{'db'}->{'rabbitMQ'}->{'user'};
    $args{'rabbitMQ_pass'} = $self->{'db'}->{'rabbitMQ'}->{'pass'};
    $args{'rabbitMQ_vhost'} = $self->{'db'}->{'rabbitMQ'}->{'vhost'};

    my $proc = AnyEvent::Fork->new->require("Log::Log4perl", "OESS::FWDCTL::Switch")->eval('
	use strict;
	use warnings;
        use Data::Dumper;
	my $switch;
	my $logger;
        Log::Log4perl::init_and_watch("/etc/oess/logging.conf",10);
	sub run{
	    my $fh = shift;
	    my %args = @_;
	    $logger = Log::Log4perl->get_logger("OESS.FWDCTL.MASTER");
	    $logger->info("Creating child for dpid: " . $args{"dpid"});
	    $switch = OESS::FWDCTL::Switch->new( %args );
	}
	')->fork->send_arg( %args )->run("run");

    $self->{'children'}->{$dpid}->{'rpc'} = 1;

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
        $self->{'logger'}->debug("Telling child: " . $dpid . " to change paths!");

        $self->{'fwdctl_events'}->{'topic'} = "OF.FWDCTL.Switch." . sprintf("%x", $dpid);
        $self->{'fwdctl_events'}->change_path(circuits       => $dpids{$dpid},
                                              async_callback => sub {
                                                  my $response = shift;

                                                  if (defined $response->{'error'} && defined $response->{'error_text'}) {
                                                      $self->{'logger'}->error($response->{'error_text'});
                                                  }
                                              });
    }

    #commit our changes to the database
    $self->{'db'}->_commit();
    if ( $circuit_notification_data && scalar(@$circuit_notification_data) ){
	$self->{'fwdctl_events'}->{'topic'} = "OF.FWDCTL.event";
        $self->{'fwdctl_events'}->circuit_notification( type      => 'link_up',
							link_name => $link_name,
							affected_circuits => $circuit_notification_data,
							no_reply  => 1);
    }
}

=head2 _fail_over_circuits

=cut

sub _fail_over_circuits{
    my $self = shift;
    my %params = @_;

    my $circuits    = $params{'circuits'};
    my $link_name   = $params{'link_name'};
    
    my %dpids;

    $self->{'logger'}->debug("Calling _fail_over_circuits on link $link_name with circuits: " . @{$circuits});
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
                    #$self->{'fwdctl_events'}->circuit_notification", $circuit_info );
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
                #$self->{'fwdctl_events'}->circuit_notification", $circuit_info );
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
            #$self->{'fwdctl_events'}->circuit_notification", $circuit_info);
            push (@$circuit_infos, $circuit_info);
            $self->{'circuit_status'}->{$circuit_id} = OESS_CIRCUIT_DOWN;
        }
    }
    my $event_id = $self->_generate_unique_event_id();

    #write the cache
    $self->{'logger'}->debug("Writing cache in _fail_over_circuits.");
    $self->_write_cache();

    foreach my $dpid (keys %dpids){
        $self->{'logger'}->debug("Telling child: " . $dpid . " to change paths!");

        $self->{'fwdctl_events'}->{'topic'} = "OF.FWDCTL.Switch." . sprintf("%x", $dpid);
        $self->{'fwdctl_events'}->change_path(circuits       => $dpids{$dpid},
                                              async_callback => sub {
                                                  my $response = shift;

                                                  if (defined $response->{'error'} && defined $response->{'error_text'}) {
                                                      $self->{'logger'}->error($response->{'error_text'});
                                                  }
                                              });
    }

    $self->{'db'}->_commit();
    $self->{'logger'}->debug("Committed path changes to the database in _fail_over_circuits.");
    $self->{'logger'}->debug("Completed sending the requests");
    
        
    if ($circuit_infos && scalar(@{$circuit_infos})) {
	$self->{'fwdctl_events'}->{'topic'} = "OF.FWDCTL.event";
        $self->{'fwdctl_events'}->circuit_notification( type => 'link_down',
                                                        link_name => $link_name,
                                                        affected_circuits => $circuit_infos,
							no_reply => 1 );
    }

    $self->{'logger'}->debug("Leaving _fail_over_circuits. Notification complete!");
}

=head2

=cut

sub _update_port_status{
    my $self = shift;

    my $p_ref = shift;

    my $dpid = $p_ref->{'dpid'}{'value'};
    my $info = $p_ref->{'attrs'}{'value'};
    my $reason = $p_ref->{'ofp_port_reason'}{'value'};

    $self->{'logger'}->info("Calling _update_port_status $reason on switch $dpid.");

    
    if ($reason == OFPPR_DELETE) {
	# Currently do nothing...
    } else {
        $self->{'db'}->_start_transaction();

	my $operational_state = 'up';
	my $operational_state_num=(int($info->{'state'}) & 0x1);
	if(1 == $operational_state_num){
	    $operational_state = 'down';
	}
	
	my $admin_state = 'up';
	my $admin_state_num = (int($info->{'config'}) & 0x1);
	
	if(1 == $admin_state_num){
	    $admin_state = 'down';
	}
	
	my $node = $self->{'db'}->get_node_by_dpid(dpid => $dpid);
	
	my $res = $self->{'db'}->add_or_update_interface(node_id => $node->{'node_id'}, name => $info->{'name'},
							 description => $info->{'name'}, operational_state => $operational_state,
							 port_num => $info->{'port_no'}, admin_state => $admin_state);
        $self->{'db'}->_commit();
    }

    $self->{'logger'}->info("Leaving _update_port_status.");
}


=head2 port_status
    listens to the port status event from NOX
    and determins if a fail-over needs to occur
    **NOTE - Not used for add/delete events

=cut

sub port_status{
    my $self   = shift;
    my $m_ref  = shift;
    my $p_ref  = shift;
    my $state_ref = shift;

    #all of our params are stored in the p_ref!
    my $dpid   = $p_ref->{'dpid'}{'value'};
    my $reason = $p_ref->{'ofp_port_reason'}{'value'};
    my $info   = $p_ref->{'attrs'}{'value'};

    $self->{'logger'}->info("Calling port_status $reason on switch $dpid.");
    $self->{'logger'}->debug("Calling port_status with port attributes: " . Data::Dumper::Dumper($info));

    my $port_name   = $info->{'name'};
    my $port_number = $info->{'port_no'};
    my $link_status = $info->{'link'};

    #basic assertions
    $self->{'logger'}->error("invalid port number") && $self->{'logger'}->logcluck() && exit 1 if(!defined($port_number) || $port_number > 65535 || $port_number < 0);
    $self->{'logger'}->error("dpid was not defined") && $self->{'logger'}->logcluck() && exit 1 if(!defined($dpid));
    $self->{'logger'}->error("invalid port status reason") && $self->{'logger'}->logcluck() && exit 1 if($reason < 0 || $reason > 2);
    $self->{'logger'}->error("invalid link status: '$link_status'") && $self->{'logger'}->logcluck() && exit 1 if(!defined($link_status) || $link_status < 0 || $link_status > 1);

    #failover chunk

    my $node_details = $self->{'db'}->get_node_by_dpid( dpid => $dpid );

    #assert we found the node in the db, its really bad if it isn't there!
    $self->{'logger'}->error("node with DPID: " . $dpid . " was not found in the DB") && $self->{'logger'}->logcluck() && exit 1 if(!defined($node_details));
    my $dpid_str  = sprintf("%x",$dpid);
    switch($reason){

        #port status was modified (either up or down)
        case(OFPPR_MODIFY){
	    my $link_info   = $self->{'db'}->get_link_by_dpid_and_port(dpid => $dpid,
								       port => $port_number);
	    
	    if(defined $link_info && @$link_info >= 1) {
	    
		my $link_id   = @$link_info[0]->{'link_id'};
		my $link_name = @$link_info[0]->{'name'};
		my $sw_name   = $node_details->{'name'};
		
		#--- when a port goes down, determine the set of ckts that traverse the port
		#--- for each ckt, fail over to the non-active path, after determining that the path
		#--- looks to be intact.
		if (! $link_status) {
		    $self->{'logger'}->warn("sw:$sw_name dpid:$dpid_str port $port_name trunk $link_name is down");
		    
		    my $affected_circuits = $self->{'db'}->get_affected_circuits_by_link_id(link_id => $link_id);
		    if (!defined $affected_circuits) {
			$self->{'logger'}->debug("Error getting affected circuits: " . $self->{'db'}->get_error());
		    }else{
			
			# Fail over affected circuits if link is not in maintenance mode.
			# Ignore traffic migration when in maintenance mode.
			if (!exists $self->{'link_maintenance'}->{$link_id}) {
			    $self->{'link_status'}->{$link_name} = OESS_LINK_DOWN;
			    $self->_fail_over_circuits( circuits => $affected_circuits, link_name => $link_name);
			    $self->_cancel_restorations( link_id => $link_id);
			}
			$self->{'db'}->update_link_state( link_id => $link_id, state => 'down');
		    }
		    $self->{'logger'}->debug("done handling port down!");
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
		    $self->{'db'}->update_link_state( link_id => $link_id, state => 'up');
		}
	    }

	    $self->{'logger'}->debug("update_port_status");
	    $self->_update_port_status($p_ref);

	}
        case(OFPPR_DELETE){
	    my $link_info   = $self->{'db'}->get_link_by_dpid_and_port(dpid => $dpid,
								       port => $port_number);
	    
	    if (! defined $link_info || @$link_info < 1) {
		#--- no link means edge port
		return;
	    }
	    
	    my $link_id   = @$link_info[0]->{'link_id'};
	    my $link_name = @$link_info[0]->{'name'};
	    my $sw_name   = $node_details->{'name'};
	    
	    if (defined($link_id) && defined($link_name)) {
		$self->{'logger'}->warn("sw:$sw_name dpid:$dpid_str port $port_name trunk $link_name has been removed");
	    } else {
		$self->{'logger'}->warn("sw:$sw_name dpid:$dpid_str port $port_name has been removed");
	    }

	    $self->_update_port_status($p_ref);
	}
	case(OFPPR_ADD) {
	    #just force sync the node and update the status!
	    $self->force_sync(undef, { dpid => {'value' => $dpid} });
	    $self->_update_port_status($p_ref);
	}else{
	    #uh we should not be able to get here!
	}
    }
    $self->{'logger'}->info("Leaving port_status for switch $dpid.");
}

sub _cancel_restorations{
    my $self = shift;
    my %args = @_;

    my $link_id     = $args{'link_id'};

    if (!defined $link_id) {
        $self->{'logger'}->error("Bailing on _cancel_restorations. Argument link_id is undefined.");
        return;
    }
    
    $self->{'logger'}->debug("Calling _cancel_restorations on link $link_id.");

    my $circuits = $self->{'db'}->get_circuits_on_link( link_id => $args{'link_id'} , path => 'primary');

    $self->{'db'}->_start_transaction();

    foreach my $circuit (@{$circuits}) {
        $self->{'logger'}->debug("Getting scheduled events for circuit $circuit->{'circuit_id'} in _cancel_restorations.");
        my $scheduled_events = $self->{'db'}->get_circuit_scheduled_events( circuit_id     => $circuit->{'circuit_id'},
                                                                            show_completed => 0 );

        foreach my $event (@$scheduled_events) {
            if ($event->{'user_id'} == SYSTEM_USER) {
                #this is probably us... verify
                my $xml = XMLin($event->{'layout'});
                next if $xml->{'action'} ne 'change_path';
                next if $xml->{'path'} ne 'primary';
                $self->{'db'}->cancel_scheduled_action( scheduled_action_id => $event->{'scheduled_action_id'} );
                $self->{'logger'}->warn("Canceling restore to primary for circuit: " . $circuit->{'circuit_id'} . " because primary path is down in _cancel_restorations.");
            }
        }
    }

    $self->{'db'}->_commit();
    $self->{'logger'}->debug("Leaving _cancel_restorations.");
}


=head2 link_event

=cut


sub link_event{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;
    
    my $a_dpid = $p_ref->{'dpsrc'}{'value'};
    my $z_dpid = $p_ref->{'dpdst'}{'value'};

    my $a_port = $p_ref->{'sport'}{'value'};
    my $z_port = $p_ref->{'dport'}{'value'};

    my $status = $p_ref->{'action'}{'value'};

    switch($status){
	case "add"{
	    my $interface_a = $self->{'db'}->get_interface_by_dpid_and_port( dpid => $a_dpid, port_number => $a_port);
	    my $interface_z = $self->{'db'}->get_interface_by_dpid_and_port( dpid => $z_dpid, port_number => $z_port);
	    if(!defined($interface_a) || !defined($interface_z)){
		$self->{'logger'}->error("Either the A or Z endpoint was not found in the database while trying to add a link");
		$self->{'db'}->_rollback();
		return undef;
	    }

	    
	    my ($link_db_id, $link_db_state) = $self->{'db'}->get_active_link_id_by_connectors( interface_a_id => $interface_a->{'interface_id'}, interface_z_id => $interface_z->{'interface_id'} );
	    
	    if($link_db_id){
		##up the state?
		$self->{'logger'}->error("Link already exists doing nothing...");
		return;
	    }else{
                $self->{'logger'}->error("Doesn't match existing links");
		#first determine if any of the ports are currently used by another link... and connect to the same other node
		my $links_a = $self->{'db'}->get_link_by_interface_id( interface_id => $interface_a->{'interface_id'}, show_decom => 0);
		my $links_z = $self->{'db'}->get_link_by_interface_id( interface_id => $interface_z->{'interface_id'}, show_decom => 0);
		
		my $z_node = $self->{'db'}->get_node_by_id( node_id => $interface_z->{'node_id'} );
		my $a_node = $self->{'db'}->get_node_by_id( node_id => $interface_a->{'node_id'} );
		
		my $a_links;
		my $z_links;
		
		#lets first remove any circuits not going to the node we want on these interfaces
		foreach my $link (@$links_a){
		    my $other_int = $self->{'db'}->get_interface( interface_id => $link->{'interface_a_id'} );
		    if($other_int->{'interface_id'} == $interface_a->{'interface_id'}){
			$other_int = $self->{'db'}->get_interface( interface_id => $link->{'interface_z_id'} );
		    }
		    
		    my $other_node = $self->{'db'}->get_node_by_id( node_id => $other_int->{'node_id'} );
		    if($other_node->{'node_id'} == $z_node->{'node_id'}){
			push(@$a_links,$link);
		    }
		}
		
		foreach my $link (@$links_z){
		    my $other_int = $self->{'db'}->get_interface( interface_id => $link->{'interface_a_id'} );
		    if($other_int->{'interface_id'} == $interface_z->{'interface_id'}){
			$other_int = $self->{'db'}->get_interface( interface_id => $link->{'interface_z_id'} );
		    }
		    my $other_node = $self->{'db'}->get_node_by_id( node_id => $other_int->{'node_id'} );
		    if($other_node->{'node_id'} == $a_node->{'node_id'}){
			push(@$z_links,$link);
		    }
		}
		
		#ok... so we now only have the links going from a to z nodes
		# we pretty much have 4 cases... there are 2 or more links going from a to z
		# there is 1 link going from a to z (this is enumerated as 2 elsifs one for each side)
		# there is no link going from a to z
		$self->{'db'}->_start_transaction();
		if(defined($a_links->[0]) && defined($z_links->[0])){
		    #ok this is the more complex one to worry about
		    #pick one and move it, we will have to move another one later
		    my $link = $a_links->[0];
		    my $old_z = $link->{'interface_a_id'};
		    if($old_z == $interface_a->{'interface_id'}){
			$old_z = $link->{'interface_z_id'};
		    }
		    my $old_z_interface = $self->{'db'}->get_interface( interface_id => $old_z);
		    $self->{'db'}->decom_link_instantiation( link_id => $link->{'link_id'} );
		    $self->{'db'}->create_link_instantiation( link_id => $link->{'link_id'}, interface_a_id => $interface_a->{'interface_id'}, interface_z_id => $interface_z->{'interface_id'}, state => $link->{'state'} );
		    $self->{'db'}->_commit();
		    #do admin notify
		    
		    my $circuits = $self->{'db'}->get_circuits_on_link(link_id => $link->{'link_id'});
		    foreach my $circuit (@$circuits) {
			my $circuit_id = $circuit->{'circuit_id'};
			my $ckt = $self->get_ckt_object( $circuit_id );
			$ckt->update_circuit_details( link_status => $self->{'link_status'});
		    }
		    $self->_write_cache();
		    
		    my $node_a = $self->{'db'}->get_node_by_interface_id( interface_id => $interface_a->{'interface_id'} );
		    my $node_z = $self->{'db'}->get_node_by_interface_id( interface_id => $interface_z->{'interface_id'});
                    $self->{'logger'}->debug("About to diff: " . Dumper($node_a));
                    $self->{'logger'}->debug("About to diff: " . Dumper($node_z));

		    #diff
		    $self->force_sync(undef, {dpid => {'value' => $node_a->{'dpid'}}});
		    $self->force_sync(undef, {dpid => {'value' => $node_z->{'dpid'}}});
		    return;
			
		}elsif(defined($a_links->[0])){
		    $self->{'logger'}->warn("LINK has changed interface on z side");
		    #easy case update link_a so that it is now on the new interfaces
		    my $link = $a_links->[0];
		    my $old_z =$link->{'interface_a_id'};
		    if($old_z == $interface_a->{'interface_id'}){
			$old_z = $link->{'interface_z_id'};
		    }
		    my $old_z_interface= $self->{'db'}->get_interface( interface_id => $old_z);
		    #if its in the links_a that means the z end changed...
		    $self->{'db'}->decom_link_instantiation( link_id => $link->{'link_id'} );
		    $self->{'db'}->create_link_instantiation( link_id => $link->{'link_id'}, interface_a_id => $interface_a->{'interface_id'}, interface_z_id => $interface_z->{'interface_id'}, state => $link->{'state'} );
		    $self->{'db'}->_commit();
		    #do admin notification

                    my $circuits = $self->{'db'}->get_circuits_on_link(link_id => $link->{'link_id'});
                    foreach my $circuit (@$circuits) {
                        my $circuit_id = $circuit->{'circuit_id'};
                        my $ckt = $self->get_ckt_object( $circuit_id );
                        $ckt->update_circuit_details( link_status => $self->{'link_status'});
                    }
                    $self->_write_cache();

                    my $node_a = $self->{'db'}->get_node_by_interface_id( interface_id => $interface_a->{'interface_id'});
                    my $node_z = $self->{'db'}->get_node_by_interface_id( interface_id => $interface_z->{'interface_id'});

                    #diff
                    $self->force_sync(undef, {dpid => {'value' => $node_a->{'dpid'}}});
                    $self->force_sync(undef, {dpid => {'value' => $node_z->{'dpid'}}});
		    return;
		}elsif(defined($z_links->[0])){
		    #easy case update link_a so that it is now on the new interfaces
		    $self->{'logger'}->warn("Link has changed ports on the A side");
		    my $link = $z_links->[0];

		    my $old_a =$link->{'interface_a_id'};
		    if($old_a == $interface_z->{'interface_id'}){
			$old_a = $link->{'interface_z_id'};
		    }
		    my $old_a_interface= $self->{'db'}->get_interface( interface_id => $old_a);

		    $self->{'db'}->decom_link_instantiation( link_id => $link->{'link_id'});
		    $self->{'db'}->create_link_instantiation( link_id => $link->{'link_id'}, interface_a_id => $interface_a->{'interface_id'}, interface_z_id => $interface_z->{'interface_id'}, state => $link->{'state'});
		    $self->{'db'}->_commit();
		    #do admin notification
		    
                    my $circuits = $self->{'db'}->get_circuits_on_link(link_id => $link->{'link_id'});
                    foreach my $circuit (@$circuits) {
                        my $circuit_id = $circuit->{'circuit_id'};
                        my $ckt = $self->get_ckt_object( $circuit_id );
                        $ckt->update_circuit_details( link_status => $self->{'link_status'});
                    }
                    $self->_write_cache();

                    my $node_a = $self->{'db'}->get_node_by_interface_id( interface_id => $interface_a->{'interface_id'} );
                    my $node_z = $self->{'db'}->get_node_by_interface_id( interface_id => $interface_z->{'interface_id'});

                    #diff
                    $self->force_sync(undef, {dpid => {'value' => $node_a->{'dpid'}}});
                    $self->force_sync(undef, {dpid => {'value' => $node_z->{'dpid'}}});
		    return;
		}else{
		    $self->{'logger'}->warn("This is not part of any other link... making a new instance");
		    ##create a new one link as none of the interfaces were part of any link
		    
		    my $link_name = "auto-" . $a_dpid . "-" . $a_port . "--" . $z_dpid . "-" . $z_port;
		    my $link = $self->{'db'}->get_link_by_name(name => $link_name);
		    my $link_id;
		    
		    if(!defined($link)){
			$link_id = $self->{'db'}->add_link( name => $link_name );
		    }else{
			$link_id = $link->{'link_id'};
		    }

		    if(!defined($link_id)){
			$self->{'logger'}->error("Had a problem creating new link record");
			$self->{'db'}->_rollback();
			return undef;
		    }
		    
		    $self->{'db'}->create_link_instantiation( link_id => $link_id, state => 'available', interface_a_id => $interface_a->{'interface_id'}, interface_z_id => $interface_z->{'interface_id'});
		    $self->{'db'}->_commit();
		    return;
		}
	    }
	}case "remove"{
	    $self->{'logger'}->info("Link down event however we don't failover with this...\n");
	    return;
	}
    }
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
	return {status => 0};
    }

    if ($state == OESS_LINK_DOWN) {

	$self->{'logger'}->warn("FV determined link " . $link_name . " is down");

	my $affected_circuits = $self->{'db'}->get_affected_circuits_by_link_id(link_id => $link->{'link_id'});

	if (! defined $affected_circuits) {
	    $self->{'logger'}->error("Error getting affected circuits: " . $self->{'db'}->get_error());
	    return {status => 0};
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

    return {status => 1};
}

=head2 addVlan

=over 4

=item B<circuit_id> - Id of the circuit to schedule or install.

=back

Installs or schedules the installation of circuit $circuit_id.

=cut
sub addVlan {
    my $self  = shift;
    my $m_ref = shift;
    my $p_ref = shift;
    
    my $start = [gettimeofday];

    my $success_callback = $m_ref->{'success_callback'};
    my $error_callback   = $m_ref->{'error_callback'};

    my $circuit_id = $p_ref->{'circuit_id'}{'value'};

    $self->{'logger'}->error("Circuit ID required") && $self->{'logger'}->logconfess() if(!defined($circuit_id));
    $self->{'logger'}->info("Calling addVlan - circuit_id: $circuit_id");

    my $event_id = $self->_generate_unique_event_id();

    my $ckt = $self->get_ckt_object( $circuit_id );
    if(!defined($ckt)){
        &$success_callback({status => FWDCTL_FAILURE, event_id => $event_id});
    }

    if($ckt->get_type() eq 'mpls'){
	&$success_callback({status => FWDCTL_FAILURE, event_id => $event_id});
    }

    $ckt->update_circuit_details();
    if($ckt->{'details'}->{'state'} eq 'decom'){
	&$success_callback({status => FWDCTL_FAILURE, event_id => $event_id});
    }

    $self->_write_cache();

    #get all the DPIDs involved and remove the flows
    my $flows = $ckt->get_flows();
    my %dpids;
    foreach my $flow (@{$flows}){
        $dpids{$flow->get_dpid()} = 1;
    }

    my $result  = FWDCTL_SUCCESS;
    my $details = $self->{'db'}->get_circuit_details(circuit_id => $circuit_id);

    # Circuit must have state set to deploying before installation may
    # proceed. Circuits with a state of scheduled shall not be added.
    if ($details->{'state'} eq 'scheduled') {
        $self->{'logger'}->info("Elapsed time addVlan: " . tv_interval( $start, [gettimeofday]));
        &$success_callback({status => $result});
    }

    $self->{'circuit_status'}->{$circuit_id} = OESS_CIRCUIT_UP;

    my $cv  = AnyEvent->condvar;
    my $err = '';

    $cv->begin( sub {
        if ($err ne '') {
            foreach my $dpid (keys %dpids) {
                $self->{'fwdctl_events'}->{'topic'} = "OF.FWDCTL.Switch." . sprintf("%x", $dpid);
                $self->{'fwdctl_events'}->remove_vlan(circuit_id     => $circuit_id,
                                                      async_callback => sub {
                                                          $self->{'logger'}->error("Removed circuit $circuit_id from $dpid.");
                                                      });
            }

            $self->{'logger'}->error("Failed to add VLAN. Elapsed time: " . tv_interval($start, [gettimeofday]));
            &$error_callback($err);
        }

        $self->{'logger'}->info("Added VLAN. Elapsed time: " . tv_interval($start, [gettimeofday]));
        &$success_callback({status => FWDCTL_SUCCESS});
    });

    foreach my $dpid (keys %dpids){
        $cv->begin();

        $self->{'fwdctl_events'}->{'topic'} = "OF.FWDCTL.Switch." . sprintf("%x", $dpid);
        $self->{'fwdctl_events'}->add_vlan(
            circuit_id     => $circuit_id,
            async_callback => sub {
                my $res = shift;

                if (defined $res->{'error'}) {
                    $self->{'logger'}->error($res->{'error'});
                    $err .= $res->{'error'} . "\n";
                }
                $cv->end();
            });
    }

    $cv->end();
}

=head2 deleteVlan

=over 4

=item B<circuit_id> - Id of the circuit to schedule or uninstall.

=back

Uninstalls or schedules the uninstall of circuit $circuit_id.

=cut
sub deleteVlan {
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    my $success = $m_ref->{'success_callback'};
    my $error   = $m_ref->{'error_callback'};

    # Measure time spent in this method.
    my $start = [gettimeofday];

    my $circuit_id = $p_ref->{'circuit_id'}{'value'};

    $self->{'logger'}->error("Circuit ID required") && $self->{'logger'}->logconfess() if(!defined($circuit_id));
    $self->{'logger'}->info("Calling deleteVlan - circuit_id: $circuit_id.");

    my $ckt = $self->get_ckt_object( $circuit_id );
    if(!defined($ckt)){
        return &$error("Couldn't get circuit $circuit_id.");
    }
    
    $ckt->update_circuit_details();
    if($ckt->{'details'}->{'state'} eq 'decom'){
	return &$error("Circuit $circuit_id was already decommissioned.");
    }

    $self->_write_cache();
    
    #get all the DPIDs involved and remove the flows
    my $flows = $ckt->get_flows();
    my %dpids;
    foreach my $flow (@{$flows}) {
        $dpids{$flow->get_dpid()} = 1;
    }

    my $cv      = AnyEvent->condvar;
    my $details = $self->{'db'}->get_circuit_details(circuit_id => $circuit_id);
    my $err     = '';

    $cv->begin(sub {
        if ($err ne '') {
            foreach my $dpid (keys %dpids) {
                    $self->{'fwdctl_events'}->{'topic'} = "OF.FWDCTL.Switch." . sprintf("%x", $dpid);
                    $self->{'fwdctl_events'}->remove_vlan(circuit_id     => $circuit_id,
                                                          async_callback => sub {
                                                              $self->{'logger'}->error("Removed circuit $circuit_id from $dpid.");
                                                          });
            }

            $self->logger->error("Failed to delete VLAN. Elapased time: " . tv_interval( $start, [gettimeofday]));
            return &$error($err);
        }

        $self->{'logger'}->info("Deleted VLAN. Elapsed time: " . tv_interval( $start, [gettimeofday]));
        &$success({ status => FWDCTL_SUCCESS });
    });

    foreach my $dpid (keys %dpids){
        $cv->begin();

        $self->{'fwdctl_events'}->{'topic'} = "OF.FWDCTL.Switch." . sprintf("%x", $dpid);
        $self->{'fwdctl_events'}->remove_vlan(
            circuit_id     => $circuit_id,
            async_callback => sub {
                my $res = shift;

                if (defined $res->{'error'}) {
                    $self->{'logger'}->error($res->{'error'});
                    $err .= $res->{'error'} . "\n";
                }
                $cv->end();
            });
    }

    $cv->end();
}


=head2 changeVlanPath

=cut

sub changeVlanPath {
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;
    my $state = shift;

    my $success = $m_ref->{'success_callback'};
    my $error   = $m_ref->{'error_callback'};

    my $circuit_id = $p_ref->{'circuit_id'}{'value'};

    $self->{'logger'}->error("Circuit ID required") && $self->{'logger'}->logconfess() if(!defined($circuit_id));

    my $ckt = $self->get_ckt_object( $circuit_id );
    if(!defined($ckt)){
	$self->{'logger'}->error("No Circuit could be created or found for circuit: " . $circuit_id);
	next;
    }
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

    my $result  = FWDCTL_SUCCESS;
    my $share   = scalar keys %dpids;

    foreach my $dpid (keys %dpids){
        $self->{'fwdctl_events'}->{'topic'} = "OF.FWDCTL.Switch." . sprintf("%x", $dpid);
        $self->{'fwdctl_events'}->change_path(
            circuits       => [$circuit_id],
            async_callback => sub {
                my $response = shift;

                # {
                #   results => {
                #     msg => 'sent flows',
                #     status => '1',
                #     total_flows => '3'
                #   }
                # }

                if (defined $response->{'error'} && defined $response->{'error_text'}) {
                    $self->{'logger'}->error($response->{'error'});
                    return &$error($response->{'error'});
                }

                $share -= 1;
                if ($share == 0) {
                    return &$success($response);
                }
            }
        );
    }
}

=head2 get_event_status

=cut

sub get_event_status{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;
    my $state = shift;

    my $event_id = $p_ref->{'event_id'}->{'value'};

    $self->{'logger'}->debug("Looking for event: " . $event_id);
    $self->{'logger'}->debug("Pending Results: " . Data::Dumper::Dumper($self->{'pending_results'}));
    if(defined($self->{'pending_results'}->{$event_id})){

        my $results = $self->{'pending_results'}->{$event_id}->{'dpids'};
        
        foreach my $dpid (keys %{$results}){
            $self->{'logger'}->debug("DPID: " . $dpid . " reports status: " . $results->{$dpid});
            if($results->{$dpid} == FWDCTL_WAITING){
                $self->{'logger'}->debug("Event: $event_id dpid $dpid reports still waiting");
                return {status => FWDCTL_WAITING};
            }elsif($results->{$dpid} == FWDCTL_FAILURE){
                $self->{'logger'}->debug("Event : $event_id dpid $dpid reports error!");
                return {status => FWDCTL_FAILURE};
            }
        }
        #done waiting and was success!
        $self->{'logger'}->debug("Event $event_id is complete!!");
        return {status => FWDCTL_SUCCESS};
    }else{
        #no known event by that ID
        return {status => FWDCTL_UNKNOWN};
    }
}

sub _get_endpoint_dpids{
    my $self = shift;
    my $ckt_id = shift;
    my $ckt = $self->get_ckt_object($ckt_id);
    if(!defined($ckt)){
	$self->{'logger'}->error("No Circuit could be created or found for circuit: " . $ckt_id);
	return;
    }
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
        
	if(!defined($ckt)){
	    return;
	}
	$self->{'circuit'}->{$ckt->get_id()} = $ckt;
    }
    
    if(!defined($ckt)){
        $self->{'logger'}->error("Error occured creating circuit: " . $ckt_id);
    }

    return $ckt;
}

=head2 echo

Always returns 1.

=cut
sub echo {
    my $self = shift;
    return {status => 1};
}

=head2 stop

Sends a shutdown signal on OF.FWDCTL.event.stop. Child processes
should listen for this signal and cleanly exit when received.

=cut
sub stop {
    my $self = shift;

    $self->{'logger'}->info("Sending OF.FWDCTL.event.stop to listeners");
    $self->{'fwdctl_events'}->{'topic'} = "OF.FWDCTL.event";
    $self->{'fwdctl_events'}->stop();
}

1;
