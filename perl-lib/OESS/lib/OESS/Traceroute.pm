use strict;
use warnings;

package OESS::Traceroute;

use bytes;
use Log::Log4perl;
use Graph::Directed;
use OESS::Database;
use OESS::DBus;

use OESS::Circuit;
use OESS::Topology;
use Net::DBus::Annotation qw(:call);
use Net::DBus::Exporter qw (org.nddi.traceroute);
use Net::DBus qw(:typing);
use base qw(Net::DBus::Object);

use JSON::XS;
use Time::HiRes;
use Data::Dumper;


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
    my $service = shift;
    my $class = ref($that) || $that;
    
    my $logger = Log::Log4perl->get_logger("OESS.Traceroute");
    
    my %args = (
        interval => 1000,
        timeout  => 15000,
        db => undef,
        @_
    );

    my $self = $class->SUPER::new($service,"/controller1");
    
    foreach my $key (keys %args){
        $self->{$key} = $args{$key};
    }

    bless $self, $class;
    $self->{'first_run'} = 1;
    $self->{'logger'}    = $logger;
    $self->{'mac_address'} = OESS::Database::mac_hex2num('06:a2:90:26:50:09');
    $self->{transactions} = {};
    #warn "db".Dumper ($args{'db'});
    
    if ($args{'db'}){
        $self->{'db'} = $args{'db'};
        warn "Set DB via arg";
    }
    else {
        $self->{'db'} = OESS::Database->new();
        warn "Set DB via new object";
    }
    if ( !defined($self->{'db'}) ) {
        $self->{'logger'}->error("error creating database object");
        return 0;
    }
    #$self->{'db'} = $db;
    $self->{'topo'} = OESS::Topology->new( db => $self->{'db'});
    $self->_connect_to_dbus();    
    
    dbus_method("init_circuit_trace",["uint32","uint32"],["int32"]);
    dbus_method("get_traceroute_transactions",[ [ "dict", "string", ["variant"] ] ]
,[ [ "dict", "string", ["variant"] ] ]);

    $self->{'nox'}->start_reactor(
        timeouts => [
            {
                interval => 10000,
                callback => Net::DBus::Callback->new( method => sub { $self->_timeout_traceroutes() } )
            },

        ]
        );

    return $self;
}



sub _connect_to_dbus {
    my $self = shift;

    $self->{'logger'}->debug("Connecting to DBus");
   
    my $dbus = OESS::DBus->new(
        service        => "org.nddi.openflow",
        instance       => "/controller1",
        sleep_interval => .1,
        timeout        => -1
    );

    if ( !defined($dbus) ) {
        $self->{'logger'}->crit("Error unable to connect to DBus");
        die;
    }

   

#    $dbus->connect_to_signal( "datapath_leave", sub { $self->datapath_leave_callback(@_) } );
#    $dbus->connect_to_signal( "datapath_join",  sub { $self->datapath_join_callback(@_) } );
     $dbus->connect_to_signal( "link_event",     sub { $self->link_event_callback(@_) } );
#    $dbus->connect_to_signal( "port_status",    sub { $self->port_status_callback(@_) } );
#    $dbus->connect_to_signal( "fv_packet_in",   sub { $self->fv_packet_in_callback(@_) } );

    $self->{'nox'} = $dbus;

    my $bus = Net::DBus->system;

    my $client;
    my $service;
    eval {
        $service = $bus->get_service("org.nddi.openflow");
        $client  = $service->get_object("/controller1");
    };
    if ($@) {
        warn "Error in _conect_to_dbus: $@";
        return;
    }

    $client->register_for_traceroute_in();
    #$client->register_for_fv_in( $self->{'db'}->{'discovery_vlan'} );

    $self->{'dbus'} = $client;

}

=head2 init_circuit_trace
handles bootstrapping of setting up a traceroute request record, documenting origin edge interface, signalling the first outbound packet(s).

=cut

sub init_circuit_trace {

    my $self = shift;
    my ($circuit_id, $endpoint_interface) = @_;
    my $db = $self->{'db'};
    warn Dumper ($db);
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
        warn "could not find interface with interace_id $endpoint_interface";
        return 0;
    }
    
    my $node = $db->get_node_by_name(node_name => $interface->{'node_name'});
    $endpoint_dpid= $node->{'dpid'};
    $endpoint_port_no = $interface->{'port_number'};
    my $exit_ports = [];
    foreach my $exit_port (@$circuit->{'path'}{$active_path}->{ $interface->{'node_name'} } ){
        push (@$exit_ports, {vlan => $exit_port->{'remote_port_vlan'}, port => $exit_port->{'port'}});
    } 
    #verify there isn't already a traceroute running for this vlan
    my $active_transaction = $self->get_traceroute_transactions({circuit_id => $circuit_id,
                                                                 status => 'active'});
    if ($active_transaction&& defined($active_transaction->{'status'}) ){
        #set_error..
        warn "traceroute transaction for this circuit already active";
        warn Dumper ($active_transaction);
      return 0;
    }
    
    #create a new tracelog entry in the database
    my $success =$self->add_traceroute_transaction( circuit_id=> $circuit_id,
                                     source_endpoint => {dpid => $endpoint_dpid,exit_ports =>$exit_ports},
                                     remaining_endpoints => ( @{$circuit->{'endpoints'}} -1),
                                     ttl => 30 #todo make based on config
        );
    if (!$success){
        warn "did not add traceroute transaction";
        return 0;
    }
   #will have transaction_id,ttl,source_port left of current traceroute
   
    my $transaction = $self->get_traceroute_transactions({circuit_id => $circuit_id});
    #add all rules
    my $rules=    $self->build_trace_rules($circuit_id);
    
    #should this send to fwdctl or straight to NOX?
    foreach my $rule (@$rules){
        $self->{'nox'}->install_datapath_flow($rule->to_dbus());
    }
    
    $self->send_trace_packet($transaction);

    return 1;

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
    #warn Dumper $circuit;
    my $current_flows = $circuit->get_flows();#path => $circuit->get_active_path );
    #warn Dumper ($current_flows);
    foreach my $flow( @$current_flows){
    
        #TODO if flow match isn't on a trunk port, skip it;

        #first upgrade priority on flow higher
        $flow->{'priority'} +=1;
        my $matches= $flow->get_match();
        #overwrite dl_dst with new mac_addr
        $matches->{'dl_dst'} = $self->{'mac_address'};
        $matches->{'dl_type'} = 34997; #0x88B5 experimental type, to not conflict with fv/lldp.
        $flow->set_match($matches);
        
        #only action: output to controller
        $flow->set_actions([{output => OESS::FlowRule::OFPP_CONTROLLER}]);
        #warn Dumper ($flow);
        push(@rules,$flow);
    }

    return \@rules;
}

# adds next hop(s) rule, removes rule for match, signals injection of packet again at initial edge port.

=head2 process_trace_packet

processes a trace packet that has been returned from the switch, determines what rules to remove and how to update the log

=cut

sub process_trace_packet {
    my $self=shift;
    my $src_dpid = shift;
    my $src_port = shift;
    my $circuit_id = shift;

    my $db = $self->{'db'};
    my $node = $db->get_node_by_dpid($src_dpid);

    # get_link based on dst port, dst dpid:
    my $link = $db->get_link_by_dpid_and_port(dpid=>$src_dpid,port=>$src_port);
    

    # get circuits based on link
#    my $circuits = $db->get_circuits_by_link(link_id =>$link->{'link_id'});
#    my $circuit_id;
    my $circuit_details  = OESS::Circuit->new(db => $db,
                                              topo => $self->{'topo'},
                                              circuit_id => $circuit_id
                );
    my $transaction = $self->get_traceroute_transactions({circuit_id => $circuit_id, status=>'active'});
#        if ($candidate_transaction){
            #we've got an active transaction for this circuit, now verify this is actually the right traceroute, we may have multiple circuits over the same link 
            #get circuit_details, and validate this was tagged with the vlan we would have expected inbound
    
    if ($transaction){  
        
    #remove flow rule from dst_dpid,dst_port
    foreach my $flow_rule ($self->build_trace_rules($circuit_id) ) {

        if ($flow_rule->{'matches'}->{'in_port'} == $src_port ) {
            $self->{'nox'}->delete_datapath_flow($flow_rule->to_dbus() );
        }
        # is this a rule that is on the same node as edge ports other than the originating edge port? if so, decrement edge_ports
        foreach my $endpoint (@{$circuit_details->{'details'}->{'endpoints'} }) {
           
            my $e_node = $endpoint->{'node'};
            my $e_dpid = $circuit_details->{'dpid_lookup'}->{$e_node};
            
            if ( $e_dpid == $transaction->{'source_port'}->{'dpid'} ) {
                next;
            }

            if ($e_dpid == $src_dpid ){
                #decrement 
                $transaction->{remaining_endpoints} -= 1;
            }
                     
            
        }
    }
                        
    push (@{$transaction->{nodes_traversed}}, $src_dpid);
    $transaction->{ttl} -= 1;
   #get transaction from db again:

        
    if ($transaction->{'remaining_endpoints'} < 1){
        #we're done!
        $transaction->{'status'} = 'Complete';
        #remove all flows from the switches
        $self->remove_traceroute_rules(circuit_id => $circuit_id);
    }
    elsif ($transaction->{'ttl'} < 1){
            $transaction->{'status'} = 'timeout';
            #remove all flows from the switches
            $self->remove_traceroute_rules(circuit_id => $circuit_id);
    }
    else {
        $self->send_trace_packet($transaction);
        
        
    }
 
    }
   return;
}




sub send_trace_packet {
    my $self = shift;
    my $transaction = shift;
    #build packets
    my $circuit_id = $transaction->{'circuit_id'};
    my $source_port = $transaction->{'source_port'};
    
    my $packet_out;

    #each packet will always be set to send out the links of the edge_interface
    foreach my $exit_port (@{$source_port->{exit_ports} }){
        $self->{'nox'}->send_traceroute_packet(Net::DBus::dbus_uint64($source_port->{'dpid'}),Net::DBus::dbus_uint16($exit_port->{'vlan'}),Net::DBus::dbus_uint64($exit_port->{'port'}),Net::DBus::dbus_uint64($circuit_id));
    }
}

sub get_traceroute_transactions {

    # $status object:
    # $self->{'transactions'} =  { $circuit_id => { status => 'active|timeout|invalidated|complete'
    #                                             ttl => 30,
    #                                             remaining_endpoints => 3,
    #                                             nodes_traversed = []
    #                             }               }
    
    my $results = {};
    my $self = shift;
    #because dbus we can't pass as a hash, this has to be a hashref.
    my $hash_ref = shift;

    my %args = ( circuit_id => undef,
                 status => undef,
               );
    
    while ((my $k, my $v) = each %$hash_ref){
        $args{$k} = $v;
    }
    #warn Dmper \%args;
    my $transactions = $self->{'transactions'};

    my $circuit_id = $args{'circuit_id'};
    if ( defined( $circuit_id ) ){     

        if (defined($args {'status'})){
            if ($self->{'transactions'}->{$circuit_id} &&
                $self->{'transactions'}->{$circuit_id}->{'status'} eq $args{'status'}){
                $results = $self->{'transactions'}->{$circuit_id} || {};
                return $results;
            }
            $results = {};
            return $results;
        }
        else {
            $results = $self->{'transactions'}->{$circuit_id} || {};
            return $results;
#return $self->{'transactions'}->{$circuit_id};
        }
    }
    elsif (defined($args{'status'})){
        my $transactions = $self->{'transactions'};
        foreach my $circuit_id (keys %$transactions){
            if ($transactions->{$circuit_id} && $transactions->{$circuit_id}->{'status'} eq $args{'status'}){
                $results->{$circuit_id}= $transactions->{$circuit_id};
            }
        }
        return $results;
      #return (grep { $self->{'transactions'}->{$_}->{'status'} eq $args{'status'} } keys %$transactions );
    }
    else {
        return $transactions;
    }

}



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
        warn("no circuit_id");
        return;
    }
    if(!defined($args{ttl}) ){
        warn("no ttl");
        return;
    }
    if(!defined($args{remaining_endpoints}) ){
        warn("no remaining_endpoints");
        return;
    }
    if(!defined( $args{source_endpoint}) ){
        warn("no source_endpoint");
        return;
    }

    $self->{'transactions'}->{ $args{circuit_id} } =
    {
        ttl => $args{ttl},
        remaining_endpoints => $args{remaining_endpoints},
        nodes_traversed => [],
        source_endpoint => $args{source_endpoint},
        status => 'active',
        start_epoch => time(),
        end_epoch => undef
    };
    #warn Dumper $self->{'transactions'};
    return 1;
}

sub remove_traceroute_rules {
    my $self = shift;
    my %args = (
        circuit_id => undef,
        
        @_);
    #get rules
    my $rules = $self->build_trace_rules(circuit_id => $args{circuit_id});
    
    #optimization: rules for nodes we've already traced through should have been deleted already, we could skip them.
    foreach my $rule (@$rules){
        $self->{'nox'}->delete_datapath_flow($rule->to_dbus());
    }


                                        
}


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
    my $threshold = time() - 30;
    my $reap_threshold = time() - (60*2);

    my $transactions = $self->get_traceroute_transactions();

    foreach my $circuit_id (keys %$transactions){

        my $transaction = $transactions->{$circuit_id};
        warn "transaction: ".Dumper ($transaction);
        warn "threshold: $threshold";
        warn "transact : $transaction->{'start_epoch'}";
          
        if ($transaction && $transaction->{'status'} eq 'active' && $transaction->{'start_epoch'} <= $threshold) {
            #set transaction to timeout, remove rules
            $self->{'transactions'}->{$circuit_id}->{'status'} = 'timed out';
            $self->{'transactions'}->{$circuit_id}->{'end_epoch'} = time();
            #$self->remove_traceroute_rules(circuit_id => $circuit_id);
        }
        # if the end epoch is more than 5 minutes old, lets remove it from memory, to try and limit memory balooning?
        if ($transaction && $transaction->{'end_epoch'}&& $transaction->{'end_epoch'} <= $reap_threshold){
            delete $self->{'transactions'}->{$circuit_id};
        }

    }
    
}

sub link_event_callback {
    my $self   = shift;
    my $a_dpid = shift;
    my $a_port = shift;
    my $z_dpid = shift;
    my $z_port = shift;
    my $status = shift;
    my $db = $self->{'db'};
    
    if ($status != OESS_LINK_UP){
        #we don't do anything with link up, but down or unknown, we want to know what circuits were on this link.
        
        my $interface = $db->get_interface_by_dpid_and_port(dpid => $a_dpid, port_number => $a_port);
        my $link = $db->get_link_by_interface_id(interface_id => $interface->{'interface_id'});
        my $circuits = $db->get_affected_circuits_by_link_id( link_id => $link->{'link_id'});
        my $transactions = $self->get_traceroute_transactions({status => 'active'});

        foreach my $circuit (@$circuits){
            #we have an active traceroute on an impacted transaction
            if ($transactions->{$circuit->{'circuit_id'} }) {
                $transactions->{$circuit->{'circuit_id'} }->{'status'}  = 'invalidated';
                $self->remove_traceroute_rules(circuit_id => $circuit->{'circuit_id'});
            }
        }

    }
    return;
}


1;
