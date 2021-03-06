#!/usr/bin/perl
use strict;
use warnings;

package OESS::Traceroute;

use bytes;
use Log::Log4perl;
use Graph::Directed;
use OESS::Database;
use GRNOC::WebService::Regex;
use OESS::Circuit;
use GRNOC::RabbitMQ::Client;
use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;
use OESS::RabbitMQ::Client;
use OESS::RabbitMQ::Dispatcher;
use OESS::Topology;

use JSON::XS;
use Time::HiRes qw(usleep);
use Data::Dumper;
use AnyEvent;
use Array::Utils qw(unique);

#temporary until add/delete is moved to FWDCTL.
use constant OFPFC_ADD           => 0;
use constant OFPFC_MODIFY        => 1;
use constant OFPFC_MODIFY_STRICT => 2;
use constant OFPFC_DELETE        => 3;
use constant OFPFC_DELETE_STRICT => 4;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;


#link statuses
use constant OESS_LINK_UP      => 1;
use constant OESS_LINK_DOWN    => 0;
use constant OESS_LINK_UNKNOWN => 2;

#node status
use constant OESS_NODE_UP   => 1;
use constant OESS_NODE_DOWN => 0;

=head1 NAME

OESS::Traceroute

=head1 SYNOPSIS

this is a module used by oess-traceroute to manage the addition of traceroute rules and acting on the packet-ins originating from that traceroute

    
=cut

=head2 new

    Creates a new OESS::Traceroute object

=cut

sub new {
    my $that = shift;
    my $class = ref($that) || $that;
    
    my $logger = Log::Log4perl->get_logger("OESS.Traceroute");
    
    my %args = (
        db => undef,
        @_
    );

    my $self  = \%args;
    bless $self, $class;
    
    foreach my $key (keys %args){
        $self->{$key} = $args{$key};
    }

    bless $self, $class;
    $self->{'first_run'} = 1;
    $self->{'logger'}    = $logger;
    $self->{'mac_address'} = OESS::Database::mac_hex2num('06:a2:90:26:50:09');
    $self->{transactions} = {};
    $self->{pending_packets} = {};

    
    if ($args{'db'}){
        $self->{'db'} = $args{'db'};
       
    } else {
        $self->{'db'} = OESS::Database->new();
    }
    if ( !defined($self->{'db'}) ) {
        $self->{'logger'}->error("error creating database object");
        return 0;
    }

    $self->{'topo'} = OESS::Topology->new( db => $self->{'db'});

    $self->{'dispatcher'} = OESS::RabbitMQ::Dispatcher->new( topic    => 'OF.NDDI.RPC');
    
    my $method = GRNOC::RabbitMQ::Method->new( name => 'init_circuit_trace',
					       async => 1,
					       callback => sub { $self->init_circuit_trace(@_) },
					       description => "Initializes a circuit trace");
    $method->add_input_parameter( name => 'circuit_id',
				  description => "the circuit ID to add",
				  required => 1,
				  pattern => $GRNOC::WebService::Regex::INTEGER);
    $method->add_input_parameter( name => 'interface_id', 
				  description => "the interface id of the interface to start at",
				  required => 1,
				  pattern => $GRNOC::WebService::Regex::INTEGER);
    $self->{'dispatcher'}->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => 'get_traceroute_transactions',
					    callback => sub { $self->get_traceroute_transactions( @_ ) },
					    description => "Get current traceroute transactions");
    $method->add_input_parameter( name => 'circuit_id',
                                  description => "the circuit ID to add",
                                  required => 0,
				  pattern => $GRNOC::WebService::Regex::INTEGER);
    $method->add_input_parameter( name => 'status',
                                  description => "the interface id of the interface to start at",
                                  required => 0,
                                  pattern => $GRNOC::WebService::Regex::TEXT);
    $self->{'dispatcher'}->register_method($method);
    

    $method = GRNOC::RabbitMQ::Method->new( name => "link_event",
					    topic => "OF.NOX.event",
					    callback => sub { $self->link_event_callback(@_) },
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
    $self->{'dispatcher'}->register_method($method);


    $method = GRNOC::RabbitMQ::Method->new( name => "traceroute_packet_in",
					    topic => "OF.NOX.event",
					    async => 1,
					    callback => sub { $self->process_trace_packet(@_) },
					    description => "Traceroute packet was received");
    $method->add_input_parameter( name => "dpid",
				  description => "The DPID of the switch which received the packet",
				  required => 1,
				  pattern => $GRNOC::WebService::Regex::NAME_ID);
    $method->add_input_parameter( name => "in_port",
				  description => "The port of the switch which received the packet",
				  required => 1,
				  pattern => $GRNOC::WebService::Regex::INTEGER);
    $method->add_input_parameter( name => "circuit_id",
				  description => "ID of the circuit that was traced",
				  required => 1,
				  pattern => $GRNOC::WebService::Regex::INTEGER);
    $self->{'dispatcher'}->register_method($method);
    
    $self->{'rabbitmq'} = OESS::RabbitMQ::Client->new( topic => 'OF.Traceroute.event');
    
    $self->{'collector_interval'} = AnyEvent->timer( after    => 5,
						     interval => 10,
						     cb => sub {
							 $self->_timeout_traceroutes();
						     });

    $self->{'config_reload_interval'} = AnyEvent->timer( after    => 5,
							 interval => 1,
							 cb => sub{
							     $self->_send_pending_traceroute_packets();
							 });
    return $self;
}

=head2 start

Start listening for messages on RabbitMQ

=cut
sub start {
    my $self = shift;

    $self->{'rabbitmq'}->{'topic'} = "OF.NOX.RPC";
    $self->{'rabbitmq'}->register_for_traceroute_in();
    $self->{'rabbitmq'}->{'topic'} = 'OF.Traceroute.event';

    $self->{'logger'}->info("Traceroute.pm consuming on OF.NDDI.RPC");
    $self->{'dispatcher'}->start_consuming();
}

=head2 init_circuit_trace

handles bootstrapping of setting up a traceroute request record,
documenting origin edge interface, signalling the first outbound
packet(s).

=cut
sub init_circuit_trace {
    my $self = shift;
    my $method_ref = shift;
    my $p_ref = shift;

    my $success_cb = $method_ref->{'success_callback'};
    my $error_cb = $method_ref->{'error_callback'};

    my $circuit_id = $p_ref->{'circuit_id'}{'value'};
    my $endpoint_interface = $p_ref->{'interface_id'}{'value'};
    
    $self->{'logger'}->info("Calling init_circuit_trace");

    my $db = $self->{'db'};

    my $circuit = OESS::Circuit->new(db => $db,
                                     topo => $self->{'topo'},
                                     circuit_id => $circuit_id
        );

    my $active_path = $circuit->get_active_path;
    my $endpoint_dpid;
    my $endpoint_port_no;
    #get dpid,port_no from endpoint_interface_id;
    
    my $interface = $db->get_interface(interface_id => $endpoint_interface);
    if (!$interface){
        $self->{'logger'}->error("could not find interface with interace_id $endpoint_interface");
	\&$error_cb({error => "could not find interface with interace_id $endpoint_interface"});
	return;
    }
    
    my $node = $db->get_node_by_name(name => $interface->{'node_name'});
    
    $endpoint_dpid= $node->{'dpid'};
    $endpoint_port_no = $interface->{'port_number'};
    my $exit_ports = [];

    foreach my $exit_port (@{$circuit->{'path'}{$active_path}->{ $interface->{'node_name'} } } ){
        push (@$exit_ports, {vlan => $exit_port->{'remote_port_vlan'}, port => $exit_port->{'port'}});
    }

    # Verify there isn't already a traceroute running for this vlan.
    my $active_transaction = $self->get_traceroute_transactions(undef, {
	circuit_id => { value => $circuit_id },
	status     => { value => 'active' }
    });
    
    if ($active_transaction && defined $active_transaction->{'status'}) {
        $self->{'logger'}->error("Traceroute transaction for this circuit is already active.");
	\&$error_cb({error => "Traceroute transaction for this circuit is already active."});
	return;
    }

    my $remaining_endpoints = 0;
    my @endpoint_nodes;

    foreach my $endpoint (@{$circuit->{'endpoints'}}) {
        push (@endpoint_nodes, $endpoint->{'node'});
    }
    my @unique_nodes = unique(@endpoint_nodes);

    #create a new tracelog entry in the database
    my $success = $self->add_traceroute_transaction(
	circuit_id          => $circuit_id,
	remaining_endpoints => (@unique_nodes -1),
	source_endpoint     => { dpid => $endpoint_dpid, exit_ports => $exit_ports },
	ttl                 => 30
    );
    if (!$success) {
        $self->{'logger'}->error("Failed to create traceroute transaction.");
	\&$error_cb({error => "Failed to create traceroute transaction."});
        return;
    }
   #will have transaction_id,ttl,source_port left of current traceroute
   
    my $transaction = $self->get_traceroute_transactions(undef, {
	circuit_id => { value => $circuit_id },
	status     => { value => undef }
    });

    #add all rules
    my $rules = $self->build_trace_rules($circuit_id);

    $self->{'rabbitmq'}->{'topic'} = "OF.NOX.RPC";
    my @dpids = ();

    my $cv = AnyEvent->condvar;
    $cv->begin( sub{ 
	\&$success_cb({success => 1});
		} );
    foreach my $rule (@{$rules}) {
	$cv->begin();
        $self->{'rabbitmq'}->send_datapath_flow(
	    flow           => $rule->to_dict(command => OFPFC_ADD),
	    async_callback => sub {
		$self->{'logger'}->debug("Installed rule to " . $rule->get_dpid());
		$cv->end();
	    }
	);

	push(@dpids, $rule->get_dpid());
    }

    foreach my $dpid (@dpids) {
	$cv->begin();
        $self->{'rabbitmq'}->send_barrier(
	    dpid           => int($dpid),
	    async_callback => sub {
		$self->{'logger'}->debug("Node $dpid has installed all rules.");
		$cv->end();
	    }
	);
    }

    $self->{pending_packets}->{$circuit_id} = { dpid => \@dpids, timeout => time() + 15 };

    $cv->end();
}

# handles packet that is returned to controller by the traceroute rules. 


=head2 build_trace_rules

uses current circuit flow rules to build a set of openflow rules that is higher priority, matches based on vlan,mac address, and ethertype, and as an action outputs to controller

=cut

sub build_trace_rules {
    my $self = shift;
    my $circuit_id = shift;
    my @rules = ();
    my $circuit = OESS::Circuit->new(db => $self->{'db'},
                                     #topo => $self->{'topo'},
                                     circuit_id => $circuit_id
        );

    my $current_flows = $circuit->get_flows();#path => $circuit->get_active_path );

    foreach my $flow( @$current_flows){
        
        #first upgrade priority on flow higher
        $flow->{'priority'} +=1;
        my $matches= $flow->get_match();
        #overwrite dl_dst with new mac_addr
        $matches->{'dl_dst'} = $self->{'mac_address'};
        $matches->{'dl_type'} = 34997; #0x88B5 experimental type, to not conflict with fv/lldp.
        $flow->set_match($matches);
        
        #only action: output to controller
        my $actions = []; #$flow->get_actions;
        push(@$actions, {output => OESS::FlowRule::OFPP_CONTROLLER});
        $flow->set_actions($actions);
        push(@rules,$flow);
    }

    return \@rules;
}

# adds next hop(s) rule, removes rule for match, signals injection of packet again at initial edge port.

=head2 process_trace_packet

processes a trace packet that has been returned from the switch, determines what rules to remove and how to update the log

=cut

sub process_trace_packet {
    my $self  = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    my $success_cb = $m_ref->{'success_callback'};
    \&$success_cb({success => 1});
    
    my $src_dpid   = $p_ref->{'dpid'}->{'value'};
    my $src_port   = $p_ref->{'in_port'}->{'value'};
    my $circuit_id = $p_ref->{'circuit_id'}->{'value'};
    $self->{'logger'}->info("Calling process_trace_packet.");

    my $db = $self->{'db'};
    my $node = $db->get_node_by_dpid(dpid =>$src_dpid);

    # get_link based on dst port, dst dpid:
    my $link = $db->get_link_by_dpid_and_port(dpid=>$src_dpid,port=>$src_port);
    my $interface = $db->get_interface_by_dpid_and_port(dpid=>$src_dpid,port_number=>$src_port);
    

    # get circuits based on link

    my $circuit_details  = OESS::Circuit->new(db => $db,
                                              topo => $self->{'topo'},
                                              circuit_id => $circuit_id
                );
    my $transaction = $self->get_traceroute_transactions(undef, {
	circuit_id => { value => $circuit_id },
	status     => { value => 'active' }
    });

    #we've got an active transaction for this circuit, now verify this
    #is actually the right traceroute, we may have multiple circuits
    #over the same link get circuit_details, and validate this was
    #tagged with the vlan we would have expected inbound
    
    if ($transaction){  
	
	my $cv = AnyEvent->condvar;
	$cv->begin( sub {
	    my @tmp_nodes_traversed = split (',',$transaction->{nodes_traversed});
	    my @tmp_intfs_traversed = split (',',$transaction->{interfaces_traversed});
	    push (@tmp_nodes_traversed , $src_dpid);
	    push (@tmp_intfs_traversed , $interface->{'name'});
	    $transaction->{nodes_traversed} = join(",",@tmp_nodes_traversed);
	    $transaction->{interfaces_traversed} = join(",",@tmp_intfs_traversed);
	    $transaction->{ttl} -= 1;
	    #get transaction from db again:	    
	    if ($transaction->{'remaining_endpoints'} < 1){
		#we're done!
		$transaction->{'status'} = 'Complete';
		#remove all flows from the switches
		$transaction->{'end_epoch'} = time();
		$self->remove_traceroute_rules(circuit_id => $circuit_id);
	    }
	    elsif ($transaction->{'ttl'} < 1){
		$transaction->{'status'} = 'timeout';
		$transaction->{'end_epoch'} = time();
		#remove all flows from the switches
		$self->remove_traceroute_rules(circuit_id => $circuit_id);
	    }
	    else {
		
		$self->{pending_packets}->{$circuit_id} = { dpid => [$src_dpid],
							    timeout => time() + 15,
		};
		
		#$self->send_trace_packet($circuit_id,$transaction);
		
	    }});
	my $t;
	#remove flow rule from dst_dpid,dst_port
	foreach my $flow_rule (@{$self->build_trace_rules($circuit_id)} ) {

	    if (  $flow_rule->get_dpid() == $src_dpid && $flow_rule->{'match'}->{'in_port'} == $src_port ) {
		$self->{'logger'}->info("Received traceroute flow from node: $node->{'name'} interface: $interface->{'name'} ".$flow_rule->get_dpid() );
		$self->{'rabbitmq'}->{'topic'} = "OF.NOX.RPC";
		$cv->begin();
		$self->{'logger'}->debug("Removing Flow: " . $flow_rule->to_human());
		my $xid = $self->{'rabbitmq'}->send_datapath_flow(flow => $flow_rule->to_dict(command => OFPFC_DELETE_STRICT),
								  async_callback => sub {
								      $self->{'rabbitmq'}->send_barrier(dpid => int($flow_rule->get_dpid()),
													async_callback => sub {
													    #wait for barrier...
													    #is this a rule that is on the same node as edge ports other than the originating edge port? if so, decrement edge_ports
													    foreach my $endpoint (@{$circuit_details->{'details'}->{'endpoints'} }) {
														
														my $e_node = $endpoint->{'node'};
														my $e_dpid = $circuit_details->{'dpid_lookup'}->{$e_node};
														
														if ( $e_dpid == $transaction->{'source_endpoint'}->{'dpid'} ) {
														    next;
														}
														
														if ($e_dpid == $src_dpid ){
														    #decrement 
														    $transaction->{remaining_endpoints} -= 1;
														}   		    
													    }

														$cv->end();
													
													})});
	    }
	}
	$cv->end();
    }
}

=head2 send_trace_packet

handles sending traceroute packet to nox dbus for each output port. Takes circuit_id, and current transaction;

=cut

sub send_trace_packet {
    my $self = shift;
    my $circuit_id = shift;
    my $transaction = shift;
    #build packets

    my $source_port = $transaction->{'source_endpoint'};
    
    my $packet_out;
    #each packet will always be set to send out the links of the edge_interface
    $self->{'rabbitmq'}->{'topic'} = "OF.NOX.RPC";
    foreach my $exit_port (@{$source_port->{exit_ports}}) {
	$self->{'logger'}->info("calling send_traceroute_packet");

        $self->{'rabbitmq'}->send_traceroute_packet(
	    data           => int($circuit_id),
	    dpid           => int($source_port->{'dpid'}),
	    out_port       => int($exit_port->{'port'}),
	    my_vlan        => int($exit_port->{'vlan'}),
	    async_callback => sub {
		my $result = shift;

		if (defined $result->{'results'} && defined $result->{'results'}->[0] && defined $result->{'results'}->[0]->{'error'}) {
		    $self->{'logger'}->error($result->{'results'}->[0]->{'error'});
		}
	    }
	);
    }
}

=head2 get_traceroute_transactions

gets traceroute transactions from memory, optionally filtering by circuit_id and/or status

=cut

sub get_traceroute_transactions {
    my $self = shift;
    my $method_ref = shift;
    my $p_ref = shift;

    my $results = {};
    my $transactions = $self->{'transactions'};

    my $circuit_id = $p_ref->{'circuit_id'}{'value'};
    my $status     = $p_ref->{'status'}{'value'};
    
    if (defined $circuit_id) {
        if (defined $status) {
            if ($self->{'transactions'}->{$circuit_id} && $self->{'transactions'}->{$circuit_id}->{'status'} eq $status) {
                $results = $transactions->{$circuit_id} || {};
            }
        } else {
            $results = $transactions->{$circuit_id} || {};
        }

	return $results;
    } elsif (defined $status) {
        foreach my $transaction_circuit_id (keys %{$transactions}) {
            if ($transactions->{$transaction_circuit_id} && $transactions->{$transaction_circuit_id}->{'status'} eq $status){
                $results->{$transaction_circuit_id} = $transactions->{$transaction_circuit_id};
            }
        }

        return $results;
    } else {
        $results = $transactions || {};

        return $results;
    }
}

=head2 add_traceroute_transaction

add_traceroute_transaction adds an entry into the in-memory hash for
new traceroute. It returns 1 if successful or undef on failure.

=cut


sub add_traceroute_transaction {
    my $self = shift;
    
    my %args = ( circuit_id => undef,
                 ttl =>0,
                 remaining_endpoints => 0,
                 source_endpoint => undef,
                 #nodes_traversed => [],
                 @_
        );
    
    if(!defined($args{circuit_id}) ){
        $self->{'logger'}->warn("no circuit_id");
        return;
    }
    if(!defined($args{ttl}) ){
        $self->{'logger'}->warn("no ttl");
        return;
    }
    if(!defined($args{remaining_endpoints}) ){
        $self->{'logger'}->warn("no remaining_endpoints");
        return;
    }
    if(!defined( $args{source_endpoint}) ){
        $self->{'logger'}->warn("no source_endpoint");
        return;
    }
    $self->{'logger'}->info("adding record of start of traceroute for circuit ".$args{circuit_id}); 
    $self->{'transactions'}->{ $args{circuit_id} } =
    {
        ttl => $args{ttl},
        remaining_endpoints => $args{remaining_endpoints},
        nodes_traversed => "",
        interfaces_traversed =>"",
        source_endpoint => $args{source_endpoint},
        status => 'active',
        start_epoch => time(),
        end_epoch => undef
    };

    return 1;
}

=head2 remove_traceroute_rules

Sends removal requests for all traceroute rules for a circuit

=cut

sub remove_traceroute_rules {
    my $self = shift;
    my %args = (
        circuit_id => undef,
        
        @_);
    #get rules
    my $rules = $self->build_trace_rules($args{circuit_id});
    my @dpids = ();
    #optimization: rules for nodes we've already traced through should have been deleted already, we could skip them.
    $self->{'rabbitmq'}->{'topic'} = "OF.NOX.RPC";
    my %dpids;

    my $cv = AnyEvent->condvar;
    $cv->begin( sub { 
	foreach my $dpid (keys %dpids){
	    $self->{'rabbitmq'}->send_barrier( dpid => int($dpid),
					       no_reply => 1);
	}});
    foreach my $rule (@$rules){
        $self->{'logger'}->debug("removing traceroute rule for circuit_id $args{'circuit_id'} on switch ". sprintf("%x",$rule->get_dpid()));
	$cv->begin();
        $self->{'rabbitmq'}->send_datapath_flow(flow => $rule->to_dict(command => OFPFC_DELETE_STRICT),
						async_callback => sub { $cv->end() } );
	$dpids{$rule->get_dpid()} = 1;
    }

}

=head2 clear_traceroute_transaction

deletes a transaction from the in-memory transaction object.

=cut


sub clear_traceroute_transaction {
    my $self = shift;
    my %args = ( circuit_id => undef,
               @_
        );
    if(!$args{circuit_id}){
        return;
    }
    delete $self->{'transactions'}->{ $args{circuit_id} };
    return;
}




sub _timeout_traceroutes {
    my $self = shift;
    #look for transactions that started more than 30 seconds ago.
    my $threshold = time() - 45;
    my $reap_threshold = time() - (60*3);

    my $transactions = $self->get_traceroute_transactions(undef, {
	circuit_id => { value => undef },
	status     => { value => undef }
    });

    foreach my $circuit_id (keys %$transactions){

        my $transaction = $transactions->{$circuit_id};

        if ($transaction && $transaction->{'status'} eq 'active' && $transaction->{'start_epoch'} <= $threshold) {
            $self->{'logger'}->warn("Timed out transaction for circuit: $circuit_id");

            $self->{'transactions'}->{$circuit_id}->{'status'} = 'timed out';
            $self->{'transactions'}->{$circuit_id}->{'end_epoch'} = time();
            $self->remove_traceroute_rules(circuit_id => $circuit_id);
        }

        # if the end epoch is more than 5 minutes old, lets remove it from memory, to try and limit memory balooning?
        if ($transaction && $transaction->{'end_epoch'} && $transaction->{'end_epoch'} <= $reap_threshold){
            delete $self->{'transactions'}->{$circuit_id};
        }
    }
}

#checks the status of the dpid from the last traceroute send, and if complete or timed out, sends the packet anyways.

sub _send_pending_traceroute_packets {
    my $self = shift;

    my $now = time();
    
    foreach my $circuit_id  (keys %{$self->{pending_packets}}){
        my $transaction = $self->{transactions}->{$circuit_id};
        my $pending_packet = $self->{pending_packets}->{$circuit_id};
        if ($transaction && $transaction->{'status'} ne "active"){
            delete $self->{pending_packets}->{$circuit_id};
            next;
        }
        
        my $dpids = $pending_packet->{'dpid'};
        my $timeout = $pending_packet->{'timeout'};
        if ($timeout < $now ){
            #give up waiting, send packet anyways
            $self->{'logger'}->info("sending trace packet for circuit $circuit_id, even though last check of barriers came back FWDCTL_WAITING");
            delete $self->{pending_packets}->{$circuit_id};
            $self->send_trace_packet($circuit_id,$transaction);
        }
        else{
            my $all_dpids_ok=1;
            foreach my $dpid (@$dpids){
                $self->{'rabbitmq'}->{'topic'} = "OF.NOX.RPC";
                $self->{'rabbitmq'}->get_node_status(
		    dpid           => int($dpid),
		    async_callback => sub {
			my $result = shift;
			my $status = $result->{'results'}->[0];

			if ($status->{'status'} == FWDCTL_WAITING) {
			    $self->{'logger'}->debug("switch ".sprintf("%x",$dpid)." is still in FWDCTL_WAITING, skipping sending for circuit $circuit_id");
			    $all_dpids_ok=0;
			    # last;
			}
		    });
            }
            if ($all_dpids_ok){
                $self->{'logger'}->info("all switches returned from FWDCTL_WAITING sending trace packet for circuit $circuit_id");
                delete $self->{pending_packets}->{$circuit_id};
                $self->send_trace_packet($circuit_id,$transaction);
            }
        }
        
    }
    return;
}

=head2 link_event_callback

on link events, invalidate any traceroutes that were currently running over the impacted link.

=cut


sub link_event_callback {
    my $self  = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    my $a_dpid = $p_ref->{'dpsrc'}->{'value'};
    my $a_port = $p_ref->{'sport'}->{'value'};
    my $z_dpid = $p_ref->{'dpdst'}->{'value'};
    my $z_port = $p_ref->{'dport'}->{'value'};
    my $status = $p_ref->{'action'}->{'value'};
    my $db     = $self->{'db'};

    if ($status ne 'add' ){
        #we don't do anything with link up, but down or unknown, we want to know what circuits were on this link.
        
        my $interface = $db->get_interface_by_dpid_and_port(dpid => $a_dpid, port_number => $a_port);
        if (!defined $interface) {
            $self->{'logger'}->error("Could not get interface for Switch: $a_dpid Port: $a_port");
            return;
        }

        my $link = $db->get_link_by_interface_id(interface_id => $interface->{'interface_id'});

        
        if ($link){
        
            $link= $link->[0];

            
            my $transactions = $self->get_traceroute_transactions(undef, {
		circuit_id => { value => undef },
		status     => { value => 'active' }
	    });
            
            if (!$transactions){
                #shortcut if we don't have any active transactions

                return;
            }
            my $circuits = $db->get_affected_circuits_by_link_id( link_id => $link->{'link_id'} );
            
            foreach my $circuit (@$circuits){
               
                #we have an active traceroute on an impacted transaction
                
                if ($transactions && $transactions->{ $circuit->{'id'} }) {
                   
                    $transactions->{ $circuit->{'id'} }->{'status'}  = 'invalidated';
                    $transactions->{ $circuit->{'id'} }->{'end_epoch'}  = time();
                    $self->remove_traceroute_rules(circuit_id => $circuit->{'id'});
                }
            }
        }
    }
    return;
}


1;
