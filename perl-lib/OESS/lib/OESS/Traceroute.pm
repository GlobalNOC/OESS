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
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS.Traceroute");

    my %args = (
        interval => 1000,
        timeout  => 15000,
        db => undef,
        @_
    );

    my $self = \%args;

    bless $self, $class;
    $self->{'first_run'} = 1;
    $self->{'logger'}    = $logger;
    $self->{'mac_address'} = OESS::Database::mac_hex2num('06:a2:90:26:50:09');
    $self->{transactions} = {};
    warn "db".Dumper ($args{'db'});
    
    if (defined $args{'db'}){
        $self->{'db'} = $args{'db'};
    }
    else {
        $self->{'db'} = OESS::Database->new();
    }
    if ( !defined($self->{'db'}) ) {
        $self->{'logger'}->error("error creating database object");
        return;
    }
    #$self->{'db'} = $db;
    $self->{'topo'} = OESS::Topology->new( db => $self->{'db'});
    $self->_connect_to_dbus();    
    
    #$self->{'oess_dbus'}->start_reactor(
    #    timeouts => [
    #        {
    #            interval => 300000,
    #            callback => Net::DBus::Callback->new( method => sub { $self->_load_state(); } )
    #        },
    #        {
    #            interval => $self->{'interval'},
    #            callback => Net::DBus::Callback->new( method => sub { $self->do_work(); } )
    #        }
    #    ]
    #    );

    return $self;
}

# sub _load_state {
#     my $self  = shift;
#     $self->{'logger'}->debug("Loading the state");

#     my $links = $self->{'db'}->get_current_links();

#     my %nodes;
#     my $nodes = $self->{'db'}->get_current_nodes();
#     foreach my $node (@$nodes) {
#         $nodes{ $node->{'dpid'} } = $node;

#         if ( defined( $self->{'nodes'}->{ $node->{'dpid'} } ) ) {
#             $node->{'status'} = $self->{'nodes'}->{ $node->{'dpid'} }->{'status'};
#         }
#         else {
#             if ( $node->{'operational_state'} eq 'up' ) {
#                 $node->{'status'} = OESS_NODE_UP;
#             }
#             else {
#                 $node->{'status'} = OESS_NODE_DOWN;
#             }
#         }

#         $nodes{ $node->{'node_id'} } = $node;
#         $nodes{ $node->{'dpid'} }    = $node;

#     }

#     my %links;
#     foreach my $link (@$links) {
#         next if (defined($link->{'remote_urn'}));

#         if ( $link->{'status'} eq 'up' ) {
#             $link->{'status'} = OESS_LINK_UP;
#         }
#         elsif ( $link->{'status'} eq 'down' ) {
#             $link->{'status'} = OESS_LINK_DOWN;
#         }
#         else {
#             $link->{'status'} = OESS_LINK_UNKNOWN;
#         }

#         my $int_a = $self->{'db'}->get_interface( interface_id => $link->{'interface_a_id'} );
#         my $int_z = $self->{'db'}->get_interface( interface_id => $link->{'interface_z_id'} );

#         $link->{'a_node'} = $nodes{ $nodes{ $int_a->{'node_id'} }->{'dpid'} };
#         $link->{'a_port'} = $int_a;
#         $link->{'z_node'} = $nodes{ $nodes{ $int_z->{'node_id'} }->{'dpid'} };
#         $link->{'z_port'} = $int_z;

#         if ( defined( $self->{'links'}->{ $link->{'name'} } ) ) {
#             $link->{'fv_status'}     = $self->{'links'}->{ $link->{'name'} }->{'fv_status'};
#             $link->{'last_verified'} = $self->{'links'}->{ $link->{'name'} }->{'last_verified'};
#         }
#         else {
#             $link->{'last_verified'} = Time::HiRes::time() * 1000;
#             $link->{'fv_status'}     = OESS_LINK_UNKNOWN;
#         }

#         $links{ $link->{'name'} } = $link;
#     }

#     $self->{'logger'}->debug( "Node State: " . Data::Dumper::Dumper( \%nodes ) );
#     $self->{'logger'}->debug( "Link State: " . Data::Dumper::Dumper( \%links ) );

#     $self->{'nodes'} = \%nodes;
#     $self->{'links'} = \%links;
    
#     my @packet_array;
#     #ok now send out our packets
    
#     foreach my $link_name ( keys( %{ $self->{'links'} } ) ) {
        
#         my $link = $self->{'links'}->{$link_name};
#         $self->{'logger'}->debug( "Sending packets for link: " . $link_name );
        
#         my $a_end = { node => $link->{'a_node'}, int => $link->{'a_port'} };
#         my $z_end = { node => $link->{'z_node'}, int => $link->{'z_port'} };
        
#         my @arr = ( Net::DBus::dbus_uint64( $a_end->{'node'}->{'dpid'} ), Net::DBus::dbus_uint64( $a_end->{'int'}->{'port_number'} ), Net::DBus::dbus_uint64( $z_end->{'node'}->{'dpid'} ), Net::DBus::dbus_uint64( $z_end->{'int'}->{'port_number'} ) );
#         $self->{'links'}->{$link_name}->{'a_z_details'} = Net::DBus::dbus_array(\@arr);
#         push( @packet_array, $self->{'links'}->{$link_name}->{'a_z_details'} );
        
#         my @arr2 = ( Net::DBus::dbus_uint64( $z_end->{'node'}->{'dpid'} ), Net::DBus::dbus_uint64( $z_end->{'int'}->{'port_number'} ), Net::DBus::dbus_uint64( $a_end->{'node'}->{'dpid'} ), Net::DBus::dbus_uint64( $a_end->{'int'}->{'port_number'} ) );
#         $self->{'links'}->{$link_name}->{'z_a_details'} = Net::DBus::dbus_array(\@arr2);
#         push( @packet_array, $self->{'links'}->{$link_name}->{'z_a_details'} );
#     }


#     $self->{'all_packets'} = Net::DBus::dbus_array( \@packet_array );
#     $self->{'logger'}->debug(Data::Dumper::Dumper($self->{'all_packets'}));
#     $self->{'logger'}->debug("Send FV Packets");

#     $self->{'dbus'}->send_fv_packets(Net::DBus::dbus_int32($self->{'interval'}),Net::DBus::dbus_uint16($self->{'db'}->{'discovery_vlan'}),$self->{'all_packets'});
    
# }



sub _connect_to_dbus {
    my $self = shift;

    $self->{'logger'}->debug("Connecting to DBus");
    my $dbus = OESS::DBus->new(
        service        => "org.nddi.openflow",
        instance       => "/controller1",
        #sleep_interval => .1,
        #timeout        => -1
    );

    if ( !defined($dbus) ) {
        $self->{'logger'}->crit("Error unable to connect to DBus");
        die;
    }

#    $dbus->connect_to_signal( "datapath_leave", sub { $self->datapath_leave_callback(@_) } );
#    $dbus->connect_to_signal( "datapath_join",  sub { $self->datapath_join_callback(@_) } );
#    $dbus->connect_to_signal( "link_event",     sub { $self->link_event_callback(@_) } );
#    $dbus->connect_to_signal( "port_status",    sub { $self->port_status_callback(@_) } );
#    $dbus->connect_to_signal( "fv_packet_in",   sub { $self->fv_packet_in_callback(@_) } );

    $self->{'nox'} = $dbus->{'dbus'};

#    my $bus = Net::DBus->system;

    #my $client;
    #Bmy $service;
 #   eval {
  #      $service = $bus->get_service("org.nddi.openflow");
  #      $client  = $service->get_object("/controller1");
  #  };

    if ($@) {
        warn "Error in _conect_to_dbus: $@";
        return;
    }

    #$client->register_for_fv_in( $self->{'db'}->{'discovery_vlan'} );

    #$self->{'dbus'} = $client;

}

=head2 init_circuit_trace
handles bootstrapping of setting up a traceroute request record, documenting origin edge interface, signalling the first outbound packet(s).

=cut

sub init_circuit_trace {

    my $self = shift;
    my ($circuit_id, $endpoint_interface) = shift;
    my $db = $self->{'db'};
    my $circuit = OESS::Circuit->new(db => $db,
                                     topo => $self->{'topo'},
                                     circuit_id => $circuit_id
        );
    
    #verify there isn't already a traceroute running for this vlan
    if ($self->get_traceroute_transactions(circuit_id => $circuit_id,
                                           status => 'active'
        ) ){
        #set_error..
      return;
    }
    
    #create a new tracelog entry in the database
    $db->add_traceroute_transaction( circuit_id=> $circuit_id,
                                     source_endpoint => $endpoint_interface,
                                     remaining_endpoints => ( @{$circuit->{'endpoints'}} -1),
                                     ttl => 30 #todo make based on config
        );
   #will have transaction_id,ttl,source_port left of current traceroute
   
    my $transaction = $self->get_traceroute_transactions(circuit_id => $circuit_id);
    #add all rules
    my $rules=    $self->build_trace_rules($circuit_id);
    
    #should this send to fwdctl or straight to NOX?
    foreach my $rule (@$rules){
        $self->{'nox'}->install_datapath_flow($rule->to_dbus());
    }
    
    $self->send_trace_packet($transaction);

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
    warn Dumper ($current_flows);
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
    my $dst_dpid = shift;
    my $src_port = shift;
    my $dst_port = shift;
    my $port_vlan = shift;
    my $packet = shift;

    my $db = $self->{'db'};
    my $node = $db->get_node_by_dpid($dst_dpid);

    # get_link based on dst port, dst dpid:
    my $link = $db->get_link_by_dpid_and_port(dpid=>$dst_dpid,port=>$dst_port);
    
    

    # get circuits based on link
    my $circuits = $db->get_circuits_by_link(link_id =>$link->{'link_id'});
    my $circuit_id;
    my $circuit_details;
    my $transaction;
    # get transaction based on circuit_id
    foreach my $circuit (@$circuits){
        my $candidate_transaction = $self->get_traceroute_transactions(circuit_id => $circuit->{'circuit_id'}, status=>'active');
        if ($candidate_transaction){
            #we've got an active transaction for this circuit, now verify this is actually the right traceroute, we may have multiple circuits over the same link 
            $circuit_details = OESS::Circuit->new(db => $db,
                                                     topo => $self->{'topo'},
                                                     circuit_id => $circuit->{'circuit_id'}
                );
            #get circuit_details, and validate this was tagged with the vlan we would have expected inbound
            my $internal_ids = $circuit_details->{'details'}->{'internal_ids'};
            $internal_ids = $internal_ids->{$circuit_details->get_active_path };
            #TODO fix
            if($internal_ids->{$node->{node_name} }{$dst_port} eq $port_vlan ){
                #this is the correct transaction / circuit combination.
                $transaction = $candidate_transaction;
                $circuit_id = $circuit_details->{'circuit_id'};
                last;
            }
          
        }
    }
    
    if ($transaction){  
        
    #remove flow rule from dst_dpid,dst_port
    foreach my $flow_rule ($self->build_trace_rules($circuit_id) ) {

        if ($flow_rule->{'matches'}->{'in_port'} = $src_port ) {
            $self->{'nox'}->delete_datapath_flow($flow_rule->to_dbus() );
        }
        # is this a rule that is on the same node as edge ports other than the originating edge port? if so, decrement edge_ports
        foreach my $endpoint (@{$circuit_details->{'details'}->{'endpoints'} }){
            my $e_node = $endpoint->{'node'};
            my $e_dpid = $self->{'dpid_lookup'}{$e_node};
            my $e_port = $endpoint->{'port_no'};
            my $e_interface_id = $endpoint->{'interface_id'};
            if ($e_interface_id == $transaction->{'orig_endpoint'}){
                next;
            }
            if ($e_interface_id == $src_port ){
                #decrement 
                $transaction->{remaining_endpoints} -= 1;
                
            }
                     
            
        }
    }
                           

   $transaction->{ttl} -= 1;
   #get transaction from db again:
#   $transaction = $self->get_traceroute_transaction(circuit_id => $circuit_id);
        
    if ($transaction->{'remaining_endpoints'} < 1){
                               #we're done!
        $transaction->{'status'} = 'Complete';
        }
    elsif ($transaction->{'ttl'} < 1){
            $transaction->{'status'} = 'timeout';
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
    
}

sub get_traceroute_transactions {

    # $status object:
    # $self->{'transactions'} =  { $circuit_id => { status => 'active|timeout|invalidated|complete'
    #                                             ttl => 30,
    #                                             remaining_endpoints => 3,
    #                                             nodes_traversed = []
    #                             }               }
    

    my $self = shift;
    my %args = ( circuit_id => undef,
                 status => undef,
                 @_
        );
    my $transactions = $self->{'transactions'};
    if ($args{'circuit_id'}){     
        if ($args{status}){
            if ($self->{'transactions'}->{'circuit_id'}->{'status'} eq $args{'status'}){
                return $self->{'transactions'}->{$args{'circuit_id'}};
            }
            return;
        }
        else {
            return $self->{'transactions'}->{$args{'circuit_id'}};
        }
    }
    elsif ($args{status}){
        return (grep { $self->{'transactions'}->{$_}->{'status'} eq $args{status} } keys %${$self->{'transactions'}} );
    }
    else {
        return $self->{'transactions'};
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

    $self->{'transactions'}->{ $args{circuit_id} } = {
        ttl => $args{ttl},
        remaining_endpoints => $args{remaining_endpoints},
        nodes_traversed => [],
        status => 'active',
        start_epoch => time(),
        end_epoch => undef
    };
    #warn Dumper $self->{'transactions'};
    return 1;
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

1;
