use strict;
use warnings;

package OESS::FV;

use bytes;
use Data::Dumper;
use Log::Log4perl;
use Graph::Directed;
use GRNOC::RabbitMQ::Client;
use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;
use GRNOC::WebService::Regex;
use OESS::Database;
use JSON::XS;
use Time::HiRes;

#link statuses
use constant OESS_LINK_UP      => 1;
use constant OESS_LINK_DOWN    => 0;
use constant OESS_LINK_UNKNOWN => 2;

#node status
use constant OESS_NODE_UP   => 1;
use constant OESS_NODE_DOWN => 0;

=head1 NAME

OESS::FV - Forwarding Verification

=head1 SYNOPSIS

this is a module used by oess-bfd to provide the bfd link capabilities in OESS and fail over circuits when a
bi-directional or uni-directional link failure is detected
    
=cut

=head2 new

    Creates a new OESS::FV object

=cut

sub new {
    my $that = shift;
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS.FV");

    my %args = (
        interval => 1000,
        timeout  => 15000,
        @_
    );

    my $self = \%args;

    bless $self, $class;
    $self->{'first_run'} = 1;
    $self->{'logger'}    = $logger;

    my $db = OESS::Database->new();
    if ( !defined($db) ) {
        $self->{'logger'}->error("error creating database object");
        return;
    }
    $self->{'db'} = $db;

    if ( defined( $db->{'forwarding_verification'} ) ) {
        $self->{'interval'} = $db->{'forwarding_verification'}->{'interval'};
        $self->{'timeout'}  = $db->{'forwarding_verification'}->{'timeout'};
    }


    $self->{'nox'} = GRNOC::RabbitMQ::Client->new( host => $self->{'db'}->{'rabbitMQ'}->{'host'},
                                                   port => $self->{'db'}->{'rabbitMQ'}->{'port'},
                                                   user => $self->{'db'}->{'rabbitMQ'}->{'user'},
                                                   pass => $self->{'db'}->{'rabbitMQ'}->{'pass'},
                                                   exchange => 'OESS',
                                                   topic => 'OF.NOX.RPC' );

    $self->{'dispatch'} = GRNOC::RabbitMQ::Dispatcher->new( host => $self->{'db'}->{'rabbitMQ'}->{'host'},
                                                            port => $self->{'db'}->{'rabbitMQ'}->{'port'},
                                                            user => $self->{'db'}->{'rabbitMQ'}->{'user'},
                                                            pass => $self->{'db'}->{'rabbitMQ'}->{'pass'},
                                                            exchange => 'OESS',
                                                            topic => 'OF.NOX' );
    $self->_register_callbacks();
    $self->{'dispatch'}->start_consuming();
    
    return $self;
}

sub _register_callbacks {
    my $self = shift;

    my $method = GRNOC::RabbitMQ::Method->new( name        => "datapath_join",
                                               topic       => "OF.NOX.event",
                                               callback    => sub { $self->datapath_join_callback(@_) },
                                               description => "Signals a node has joined the controller" );
    $method->add_input_parameter( name => "dpid",
                                  description => "Datapath ID of node that has joined",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::NUMBER_ID );
    $method->add_input_parameter( name => "ip",
                                  description => "IP Address of node that has joined",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::NUMBER_ID );
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
    $self->{'dispatch'}->register_method($method);
    
    $method = GRNOC::RabbitMQ::Method->new( name        => "datapath_leave",
                                            topic       => "OF.NOX.event",
                                            callback    => sub { $self->datapath_leave_callback(@_) },
                                            description => "Removes datapath to FV's internal nodes" );
    $method->add_input_parameter( name => "dpid",
                                  description => "Datapath ID of node that has joined",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::NUMBER_ID );
    $self->{'dispatch'}->register_method($method);
    
    $method = GRNOC::RabbitMQ::Method->new( name        => "link_event",
                                            topic       => "OF.NOX.event",
                                            callback    => sub { $self->link_event_callback(@_) },
                                            description => "Notifies FV of any link event." );
    $method->add_input_parameter( name => "dpdst",
                                  description => "DPID of one node on the link",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::NAME_ID );
    $method->add_input_parameter( name => "dport",
                                  description => "Port of node a on the link",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::INTEGER );
    $method->add_input_parameter( name => "dpsrc",
                                  description => "DPID of one node on the link",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::NAME_ID );
    $method->add_input_parameter( name => "sport",
                                  description => "Port of node z on the link",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::INTEGER );
    $method->add_input_parameter( name => "action",
                                  description => "Status of the link",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::TEXT );
    $self->{'dispatch'}->register_method($method);
    
    $method = GRNOC::RabbitMQ::Method->new( name        => "port_status",
                                            topic       => "OF.NOX.event",
                                            callback    => sub { $self->port_status_callback(@_) },
                                            description => "Notifies FV of any port status change." );
    $method->add_input_parameter( name => "dpid",
                                  description => "The DPID of the switch which fired the port status event",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::NAME_ID);

    $method->add_input_parameter( name => "reason",
                                  description => "The reason for the port status must be one of OFPPR_ADD OFPPR_DELETE OFPPR_MODIFY",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::INTEGER);

    $method->add_input_parameter( name => "port",
                                  description => "Details about the port that had the port status message generated on it",
                                  required => 1,
                                  schema => { 'type' => 'object',
                                              'properties' => {'port_no'     => {'type' => 'number'},
                                                               'link'        => {'type' => 'number'},
                                                               'name'        => {'type' => 'string'},
                                                               'admin_state' => {'type' => 'string'},
                                                               'status'      => {'type' => 'string'}} } );
    $self->{'dispatch'}->register_method($method);
    
    $method = GRNOC::RabbitMQ::Method->new( name        => "fv_packet_in",
                                            topic       => "OF.NOX.event",
                                            callback    => sub { $self->fv_packet_in_callback(@_) },
                                            description => "Notifies FV of any received FV packet." );
    $method->add_input_parameter( name => "src_dpid",
                                  description => "DPID of one node on the link",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::NAME_ID );
    $method->add_input_parameter( name => "src_port",
                                  description => "Port of node a on the link",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::INTEGER );
    $method->add_input_parameter( name => "dst_dpid",
                                  description => "DPID of one node on the link",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::NAME_ID );
    $method->add_input_parameter( name => "dst_port",
                                  description => "Port of node z on the link",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::INTEGER );
    $method->add_input_parameter( name => "timestamp",
                                  description => "When the packet_in was received.",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::INTEGER );
    $self->{'dispatch'}->register_method($method);
}

=head2 register_for_fv_in

Publishes a message to OF.NOX.register_for_fv_in to enable the
generation of fv_packet_in messages on OF.NOX.fv_packet_in.

=over 1

=item $discovery_vlan VLAN on which discovery packets will be sent.

=back

=cut
sub register_for_fv_in {
    my $self = shift;
    my $discovery_vlan = shift;

    $self->{'nox'}->register_for_fv_in(vlan => int($discovery_vlan));
}

=head2 send_fv_link_event

Generates a link event to the OF.FV.fv_link_event topic.

=over 1

=item $link_name  Name of link that triggered an event

=item $link_state State of the link identified by link_name

=back

=cut
sub send_fv_link_event {
    my $self       = shift;
    my $link_name  = shift;
    my $link_state = shift;
 
    $self->{'nox'}->fv_link_event( link_name => $link_name,
                                   state     => $link_state,
                                   no_reply  => 1 );
}

=head2 send_fv_packets

Sends an array of packets to $discovery_valn every $interval.

=over 1

=item $interval       Interval by which $packets will be sent

=item $discovery_vlan VLAN to which discovery packets must be sent.

=item $packets        Array reference of packets to send

=back

=cut
sub send_fv_packets {
    my $self           = shift;
    my $interval       = shift;
    my $discovery_vlan = shift;
    my $packets        = shift;

    $self->{'nox'}->send_fv_packets( interval => int($interval),
                                     vlan     => int($discovery_vlan),
                                     packets  => $packets );
}

sub _load_state {
    my $self  = shift;
    $self->{'logger'}->debug("Loading the state");

    my $links = $self->{'db'}->get_current_links();

    my %nodes;
    my $nodes = $self->{'db'}->get_current_nodes();
    foreach my $node (@$nodes) {
        $nodes{ $node->{'dpid'} } = $node;

        if ( defined( $self->{'nodes'}->{ $node->{'dpid'} } ) ) {
            $node->{'status'} = $self->{'nodes'}->{ $node->{'dpid'} }->{'status'};
        }
        else {
            if ( $node->{'operational_state'} eq 'up' ) {
                $node->{'status'} = OESS_NODE_UP;
            }
            else {
                $node->{'status'} = OESS_NODE_DOWN;
            }
        }

        $nodes{ $node->{'node_id'} } = $node;
        $nodes{ $node->{'dpid'} }    = $node;

    }

    my %links;
    foreach my $link (@$links) {
        next if (defined($link->{'remote_urn'}));

        if ( $link->{'status'} eq 'up' ) {
            $link->{'status'} = OESS_LINK_UP;
        }
        elsif ( $link->{'status'} eq 'down' ) {
            $link->{'status'} = OESS_LINK_DOWN;
        }
        else {
            $link->{'status'} = OESS_LINK_UNKNOWN;
        }

        my $int_a = $self->{'db'}->get_interface( interface_id => $link->{'interface_a_id'} );
        my $int_z = $self->{'db'}->get_interface( interface_id => $link->{'interface_z_id'} );

        $link->{'a_node'} = $nodes{ $nodes{ $int_a->{'node_id'} }->{'dpid'} };
        $link->{'a_port'} = $int_a;
        $link->{'z_node'} = $nodes{ $nodes{ $int_z->{'node_id'} }->{'dpid'} };
        $link->{'z_port'} = $int_z;

        if ( defined( $self->{'links'}->{ $link->{'name'} } ) ) {
            $link->{'fv_status'}     = $self->{'links'}->{ $link->{'name'} }->{'fv_status'};
            $link->{'last_verified'} = $self->{'links'}->{ $link->{'name'} }->{'last_verified'};
        }
        else {
            $link->{'last_verified'} = Time::HiRes::time() * 1000;
            $link->{'fv_status'}     = OESS_LINK_UNKNOWN;
        }

        $links{ $link->{'name'} } = $link;
    }

    $self->{'logger'}->debug( "Node State: " . Data::Dumper::Dumper( \%nodes ) );
    $self->{'logger'}->debug( "Link State: " . Data::Dumper::Dumper( \%links ) );

    $self->{'nodes'} = \%nodes;
    $self->{'links'} = \%links;
    

    # Now send out our packets
    my $packet_array = [];
    foreach my $link_name ( keys( %{ $self->{'links'} } ) ) {
        
        my $link = $self->{'links'}->{$link_name};
        $self->{'logger'}->debug( "Sending packets for link: " . $link_name );
        
        my $a_end = { node => $link->{'a_node'}, int => $link->{'a_port'} };
        my $z_end = { node => $link->{'z_node'}, int => $link->{'z_port'} };
        
        my $arr = [ $a_end->{'node'}->{'dpid'}, $a_end->{'int'}->{'port_number'}, $z_end->{'node'}->{'dpid'}, $z_end->{'int'}->{'port_number'} ];
        $self->{'links'}->{$link_name}->{'a_z_details'} = $arr;
        push(@{$packet_array}, $self->{'links'}->{$link_name}->{'a_z_details'});
        
        my $arr2 = [ $z_end->{'node'}->{'dpid'}, $z_end->{'int'}->{'port_number'}, $a_end->{'node'}->{'dpid'}, $a_end->{'int'}->{'port_number'} ];
        $self->{'links'}->{$link_name}->{'z_a_details'} = $arr2;
        push(@{$packet_array}, $self->{'links'}->{$link_name}->{'z_a_details'} );
    }

    $self->{'all_packets'} = $packet_array;
    $self->{'logger'}->debug(Data::Dumper::Dumper($self->{'all_packets'}));
    $self->{'logger'}->debug("Send FV Packets");

    $self->send_fv_packets($self->{'interval'}, $self->{'db'}->{'discovery_vlan'}, $self->{'all_packets'});
}

=head2 datapath_leave_callback

event that firest for when a node leaves

=cut

sub datapath_leave_callback {
    my $self = shift;
    my $method  = shift;
    my $message = shift;

    my $dpid = $message->{'dpid'}->{'value'};

    $self->{'logger'}->debug( "Node: " . $dpid . " has left" );
    $self->{'logger'}->warn( "Node: " . $self->{'nodes'}->{$dpid}->{'name'} . " has left" );
    $self->{'nodes'}->{$dpid}->{'status'} = OESS_NODE_DOWN;
}

=head2 datapath_join_callback

event that fires when a node joins

=cut

sub datapath_join_callback {
    my $self    = shift;
    my $method  = shift;
    my $message = shift;

    my $dpid = $message->{'dpid'}->{'value'};

    $self->{'logger'}->debug( "Node: " . $dpid . " has joined" );
    $self->{'logger'}->warn( "Node: " . $self->{'nodes'}->{$dpid}->{'name'} . " has joined" );
    $self->{'nodes'}->{$dpid}->{'status'} = OESS_NODE_UP;
}

=head2 link_event_callback

event that fires when a link is added or removed

=cut

sub link_event_callback {
    my $self    = shift;
    my $method  = shift;
    my $message = shift;

    my $a_dpid = $message->{'dpdst'}->{'value'};
    my $a_port = $message->{'dport'}->{'value'};
    my $z_dpid = $message->{'dpsrc'}->{'value'};
    my $z_port = $message->{'sport'}->{'value'};
    my $status = $message->{'action'}->{'value'};

    $self->_load_state();
}

=head2 port_status_callback

event that is fired when a port status changes

=cut

sub port_status_callback {
    my $self   = shift;
    my $method  = shift;
    my $message = shift;

    my $dpid   = $message->{'dpid'}->{'value'};
    my $reason = $message->{'reason'}->{'value'};
    my $info   = $message->{'info'}->{'value'};

    my $port_number = $info->{'port_no'};
    my $link_status = $info->{'link'};
    my $port_name   = $info->{'name'};
    my $admin_state = $info->{'admin_state'};
    my $port_status = $info->{'status'};


    #if the link didn't go up ignore it!
    if ( $link_status != 1 ) {
        return;
    }

    #ok link came up... is it a part of a link
    foreach my $link_name ( keys( %{ $self->{'links'} } ) ) {
        if (   $self->{'links'}->{$link_name}->{'a_node'}->{'dpid'} == $dpid
            && $self->{'links'}->{$link_name}->{'a_port'}->{'port_number'} == $port_number )
        {
            $self->{'links'}->{$link_name}->{'fv_status'}     = OESS_LINK_UNKNOWN;
            $self->{'links'}->{$link_name}->{'last_verified'} = Time::HiRes::time() * 1000;
            delete $self->{'last_heard'}->{ $self->{'links'}->{$link_name}->{'a_node'}->{'dpid'} }->{ $self->{'links'}->{$link_name}->{'a_port'}->{'port_number'} };
            delete $self->{'last_heard'}->{ $self->{'links'}->{$link_name}->{'z_node'}->{'dpid'} }->{ $self->{'links'}->{$link_name}->{'z_port'}->{'port_number'} };
        }

        if (   $self->{'links'}->{$link_name}->{'z_node'}->{'dpid'} == $dpid
            && $self->{'links'}->{$link_name}->{'z_port'}->{'port_number'} == $port_number )
        {
            $self->{'links'}->{$link_name}->{'fv_status'}     = OESS_LINK_UNKNOWN;
            $self->{'links'}->{$link_name}->{'last_verified'} = Time::HiRes::time() * 1000;
            delete $self->{'last_heard'}->{ $self->{'links'}->{$link_name}->{'a_node'}->{'dpid'} }->{ $self->{'links'}->{$link_name}->{'a_port'}->{'port_number'} };
            delete $self->{'last_heard'}->{ $self->{'links'}->{$link_name}->{'z_node'}->{'dpid'} }->{ $self->{'links'}->{$link_name}->{'z_port'}->{'port_number'} };
        }
    }
}

=head2 do_work

process all of the links and verifies their current status, and then sends packets via openflow

=cut

sub do_work {
    my $self = shift;

    if ( -e '/var/run/oess/oess_is_overloaded.lock' ) {
        $self->{'logger'}->warn("OESS OVERLOADED file exists FVD is disabled");
        foreach my $link_name ( keys( %{ $self->{'links'} } ) ) {
            $self->{'links'}->{$link_name}->{'fv_status'}     = OESS_LINK_UNKNOWN;
            $self->{'links'}->{$link_name}->{'last_verified'} = Time::HiRes::time() * 1000;
        }
        return;
    }

    foreach my $link_name ( keys( %{ $self->{'links'} } ) ) {

        my $link = $self->{'links'}->{$link_name};

        $self->{'logger'}->debug( "Checking Forwarding on link: " . $link->{'name'} );
        my $a_end = { node => $link->{'a_node'}, int => $link->{'a_port'} };
        my $z_end = { node => $link->{'z_node'}, int => $link->{'z_port'} };

        if ( $self->{'nodes'}->{ $a_end->{'node'}->{'dpid'} }->{'status'} == OESS_NODE_DOWN ) {
            $self->{'logger'}->info( "node " . $a_end->{'node'}->{'name'} . " is down not checking link: " . $link->{'name'} );
            $self->{'links'}->{ $link->{'name'} }->{'fv_status'}     = OESS_LINK_UNKNOWN;
            $self->{'links'}->{ $link->{'name'} }->{'last_verified'} = Time::HiRes::time() * 1000;
            next;
        }

        if ( $self->{'nodes'}->{ $z_end->{'node'}->{'dpid'} }->{'status'} == OESS_NODE_DOWN ) {
            $self->{'logger'}->info( "node " . $z_end->{'node'}->{'name'} . " is down not checking link: " . $link->{'name'} );
            $self->{'links'}->{ $link->{'name'} }->{'fv_status'}     = OESS_LINK_UNKNOWN;
            $self->{'links'}->{ $link->{'name'} }->{'last_verified'} = Time::HiRes::time() * 1000;
            next;
        }

        if (   !defined( $self->{'last_heard'}->{ $a_end->{'node'}->{'dpid'} }->{ $a_end->{'int'}->{'port_number'} } )
            || !defined( $self->{'last_heard'}->{ $z_end->{'node'}->{'dpid'} }->{ $z_end->{'int'}->{'port_number'} } ) )
        {

            #we have never received it at least not since we were started...
            if ( $self->{'links'}->{ $link->{'name'} }->{'fv_status'} == OESS_LINK_UP ) {
                $self->{'logger'}->error( "An error has occurred Forwarding Verification, considering link " . $link->{'name'} . " down" );

                #fire link down
                $self->_send_fwdctl_link_event(
                    link_name => $link->{'name'},
                    state     => OESS_LINK_DOWN
                );
                $self->{'links'}->{ $link->{'name'} }->{'fv_status'}     = OESS_LINK_DOWN;
                $self->{'links'}->{ $link->{'name'} }->{'last_verified'} = Time::HiRes::time() * 1000;
            }
            elsif ( $self->{'links'}->{ $link->{'name'} }->{'fv_status'} == OESS_LINK_UNKNOWN ) {
                $self->{'logger'}->debug( "Last verified: " . ( ( Time::HiRes::time() * 1000 ) - $self->{'links'}->{ $link->{'name'} }->{'last_verified'} ) . " ms ago" );
                if ( ( ( Time::HiRes::time() * 1000 ) - $self->{'links'}->{ $link->{'name'} }->{'last_verified'} ) > $self->{'timeout'} ) {
                    $self->{'logger'}->warn( "Forwarding verification for link: " . $link->{'name'} . " has not been verified since load... timeout has passed considering down" );
                    $self->_send_fwdctl_link_event(
                        link_name => $link->{'name'},
                        state     => OESS_LINK_DOWN
                    );
                    $self->{'links'}->{ $link->{'name'} }->{'fv_status'}     = OESS_LINK_DOWN;
                    $self->{'links'}->{ $link->{'name'} }->{'last_verified'} = Time::HiRes::time() * 1000;
                }
                else {
                    $self->{'logger'}->warn( "Forwarding verification for link: " . $link->{'name'} . " has not been verified yet... still unknown" );
                }
            }

            #no need to do more work... go to next one
            next;
        }

        #verify both ends came and went from the right nodes/interfaces
        if (   $self->{'last_heard'}->{ $a_end->{'node'}->{'dpid'} }->{ $a_end->{'int'}->{'port_number'} }->{'originator'}->{'dpid'} eq $z_end->{'node'}->{'dpid'}
            && $self->{'last_heard'}->{ $a_end->{'node'}->{'dpid'} }->{ $a_end->{'int'}->{'port_number'} }->{'originator'}->{'port_number'} eq $z_end->{'int'}->{'port_number'}
            && $self->{'last_heard'}->{ $z_end->{'node'}->{'dpid'} }->{ $z_end->{'int'}->{'port_number'} }->{'originator'}->{'dpid'}        eq $a_end->{'node'}->{'dpid'}
            && $self->{'last_heard'}->{ $z_end->{'node'}->{'dpid'} }->{ $z_end->{'int'}->{'port_number'} }->{'originator'}->{'port_number'} eq $a_end->{'int'}->{'port_number'} )
        {

            $self->{'logger'}->debug("Packet origins/outputs line up with what we expected");

            my $last_verified_a_z = ( ( Time::HiRes::time() * 1000 ) - $self->{'last_heard'}->{ $a_end->{'node'}->{'dpid'} }->{ $a_end->{'int'}->{'port_number'} }->{'timestamp'} );
            my $last_verified_z_a = ( ( Time::HiRes::time() * 1000 ) - $self->{'last_heard'}->{ $z_end->{'node'}->{'dpid'} }->{ $z_end->{'int'}->{'port_number'} }->{'timestamp'} );

            $self->{'logger'}->debug( "Link: " . $link->{'name'} . " Z -> A last verified " . $last_verified_z_a . "ms ago" );
            $self->{'logger'}->debug( "Link: " . $link->{'name'} . " A -> Z last verified " . $last_verified_a_z . "ms ago" );

            #verify the last heard time is good
            if (   $last_verified_a_z < $self->{'timeout'}
                && $last_verified_z_a < $self->{'timeout'} )
            {
                $self->{'logger'}->debug( "link " . $link->{'name'} . " is operating as expected" );

                #link is good
                if ( $self->{'links'}->{ $link->{'name'} }->{'fv_status'} == OESS_LINK_DOWN ) {
                    $self->{'logger'}->warn( "Link: " . $link->{'name'} . " forwarding restored!" );

                    #fire link up
                    $self->_send_fwdctl_link_event(
                        link_name => $link->{'name'},
                        state     => OESS_LINK_UP
                    );
                    $self->{'links'}->{ $link->{'name'} }->{'fv_status'}     = OESS_LINK_UP;
                    $self->{'links'}->{ $link->{'name'} }->{'last_verified'} = Time::HiRes::time() * 1000;
                }
                else {
                    if ( $self->{'links'}->{ $link->{'name'} }->{'fv_status'} == OESS_LINK_UNKNOWN ) {
                        $self->{'logger'}->warn( "Link: " . $link->{'name'} . " forwarding up" );
                        $self->_send_fwdctl_link_event(
                            link_name => $link->{'name'},
                            state     => OESS_LINK_UP
                        );
                    }
                    $self->{'links'}->{ $link->{'name'} }->{'fv_status'} = OESS_LINK_UP;
                    $self->{'logger'}->debug( "link " . $link->{'name'} . " is still up" );
                    $self->{'links'}->{ $link->{'name'} }->{'last_verified'} = Time::HiRes::time() * 1000;
                }
            }
            else {
                $self->{'logger'}->debug( "Link: " . $link->{'name'} . " is not function properly" );

                #link is bad!
                if ( $self->{'links'}->{ $link->{'name'} }->{'fv_status'} == OESS_LINK_UP ) {
                    $self->{'logger'}->warn( "Link " . $link->{'name'} . " forwarding disrupted!!!! Considered DOWN!" );

                    #fire link down
                    $self->_send_fwdctl_link_event(
                        link_name => $link->{'name'},
                        state     => OESS_LINK_DOWN
                    );
                    $self->{'links'}->{ $link->{'name'} }->{'fv_status'} = OESS_LINK_DOWN;
                }
                elsif ( $self->{'links'}->{ $link->{'name'} }->{'fv_status'} == OESS_LINK_UNKNOWN ) {
                    if ( ( ( Time::HiRes::time() * 1000 ) - $self->{'links'}->{ $link->{'name'} }->{'last_verified'} ) > $self->{'timeout'} ) {
                        $self->{'logger'}->warn( "Forwarding verification for link: " . $link->{'name'} . " has not been verified since last unknown state... timeout has passed considering down" );
                        $self->_send_fwdctl_link_event(
                            link_name => $link->{'name'},
                            state     => OESS_LINK_DOWN
                        );
                        $self->{'links'}->{ $link->{'name'} }->{'fv_status'}     = OESS_LINK_DOWN;
                        $self->{'links'}->{ $link->{'name'} }->{'last_verified'} = Time::HiRes::time() * 1000;
                    }
                    else {

                        #still waiting for timeout
                    }
                }
                else {
                    $self->{'logger'}->debug( "Link " . $link->{'name'} . " is still down" );
                }
            }
        }
        else {

            #uh oh the endpoints don't line up... update our db records (maybe a migration/node insertion happened) other wise we are busted... things will timeout
            $self->{'logger'}->error("packet are screwed up!@!@! This can't happen");
            $self->_load_state();
        }
        $self->{'logger'}->debug("Done processing link");
    }
}

=head2 fv_packet_in_callback

event that fires when a packet in event occurs and matches the
forwarding verification deamon process

=cut

sub fv_packet_in_callback {
    my $self      = shift;
    my $method  = shift;
    my $message = shift;

    my $src_dpid  = $message->{'src_dpid'}->{'value'};
    my $src_port  = $message->{'src_port'}->{'value'};
    my $dst_dpid  = $message->{'dst_dpid'}->{'value'};
    my $dst_port  = $message->{'dst_port'}->{'value'};
    my $timestamp = $message->{'timestamp'}->{'value'};

    $self->{'logger'}->debug("FV Packet IN");

    $self->{'last_heard'}->{$dst_dpid}->{$dst_port} = {
        originator => { dpid => $src_dpid, port_number => $src_port },
        timestamp  => $timestamp
    };

    $self->{'logger'}->debug("dpid: " . $dst_dpid . " port: " . $dst_port . " " . Data::Dumper::Dumper($self->{'last_heard'}->{$dst_dpid}->{$dst_port}));
}

sub _send_fwdctl_link_event {
    my $self = shift;
    my %args = @_;

    my $link_name = $args{'link_name'};
    my $state     = $args{'state'};

    my $link = $self->{'db'}->get_link( link_name => $link_name );
    if ( defined($link) ) {
        my $state_str = '';
        if ( $state == OESS_LINK_UP ) {
            $state_str = 'up';
        }
        elsif ( $state == OESS_LINK_DOWN ) {
            $state_str = 'down';
        }
        else {
            $state_str = 'unknown';
        }

        $self->{'db'}->update_link_fv_state(link_id => $link->{'link_id'},
                                            state   => $state_str );
    }

    my $results = $self->send_fv_link_event( $link_name, $state );
    return $results;
}

1;
