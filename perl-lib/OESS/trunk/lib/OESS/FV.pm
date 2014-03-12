#!/usr/bin/perl

use strict;
use warnings;

package OESS::FV;

use Log::Log4perl;
use Graph::Directed;
use OESS::Database;
use OESS::DBus;

use NetPacket::Ethernet;

#link statuses
use constant OESS_LINK_UP       => 1;
use constant OESS_LINK_DOWN     => 0;
use constant OESS_LINK_UNKNOWN  => 2;
#node status
use constant OESS_NODE_UP       => 1;
use constant OESS_NODE_DOWN     => 0;

=head1 NAME

OESS::FV - Forwarding Verification

=head1 SYNOPSIS

this is a module used by oess-bfd to provide the bfd link capabilities in OESS and fail over circuits when a
bi-directional or uni-directional link failure is detected
    
=cut


=head2 new

    Creates a new OESS::FV object

=cut

sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS::FV");

    my %args = (
        interval => 500,
	@_
        );

    my $self = \%args;

    bless $self, $class;

    $self->{'logger'} = $logger;

    my $db = OESS::Database->new();
    if(!defined($db)){
	$self->{'logger'}->error("error creating database object");
	return;
    }
    $self->{'db'} = $db;
    $self->{'vlan_id'} = 100;
    $self->_load_state();
    $self->_connect_to_dbus();

    return $self;
}

sub _load_state(){
    my $self = shift;
    my $links = $self->{'db'}->get_current_links();

    my %nodes;
    my $nodes = $self->{'db'}->get_current_nodes();
    foreach my $node (@$nodes) {
        $nodes{$node->{'dpid'}} = $node;
        if($node->{'status'} eq 'up'){
            $node->{'status'} = OESS_NODE_UP;
        }else{
	    $node->{'status'} = OESS_NODE_DOWN;
	}

	$nodes{$node->{'name'}} = $node;
	$nodes{$node->{'dpid'}} = $node;
	$nodes{$node->{'node_id'}} = $node;
    }

    my %links;
    foreach my $link (@$links) {
	if ($link->{'status'} eq 'up') {
            $link->{'status'} = OESS_LINK_UP;
	} elsif ($link->{'status'} eq 'down') {
            $link->{'status'} = OESS_LINK_DOWN;
	} else {
            $link->{'status'} = OESS_LINK_UNKNOWN;
        }


        my $int_a = $self->{'db'}->get_interface( interface_id => $link->{'interface_a_id'} );
        my $int_z = $self->{'db'}->get_interface( interface_id => $link->{'interface_z_id'} );

	$link->{'a_node'} = $nodes{$int_a->{'node_id'}};
	$link->{'a_port'} = $int_a;
	$link->{'z_node'} = $nodes{$int_z->{'node_id'}};
	$link->{'z_port'} = $int_z;
        $links{$link->{'name'}} = $link;
    }

    
    $self->{'nodes'} = \%nodes;
    $self->{'links'} = \%links;
    
    return;

}

sub _connect_to_dbus{
    my $self = shift;

    $self->{'logger'}->debug("Connecting to DBus");
    my $dbus = OESS::DBus->new( service => "org.nddi.openflow",
                                instance => "/controller1", sleep_interval => .1, timeout => -1);
    if(!defined($dbus)){
        $self->{'logger'}->crit("Error unable to connect to DBus");
        die;
    }

    $dbus->connect_to_signal("datapath_leave",$self->datapath_leave_callback);
    $dbus->connect_to_signal("datapath_join",$self->datapath_join_callback);
    $dbus->connect_to_signal("link_event", $self->link_event_callback);
    $dbus->connect_to_signal("fv_packet_in", $self->fv_packet_in_callback);
    
    my $bus = Net::DBus->system;

    my $client;
    my $service;
    eval {
        $service = $bus->get_service("org.nddi.openflow");
        $client  = $service->get_object("/controller1");
    };

    $self->{'dbus'} = $client;

    $dbus->start_reactor( timeouts => [{interval => 300000, callback => Net::DBus::Callback->new(
                                            method => sub { $self->_load_state(); })},
                                       {interval => $self->{'interval'}, callback => Net::DBus::Callback->new(
                                            method => sub { $self->do_work(); })}]);
    
}

sub datapath_leave_callback{
    my $self = shift;
    my $dpid = shift;
    
    $self->{'logger'}->debug("Node: " .$dpid ." has left");
    $self->{'logger'}->warn("Node: " . $self->{'nodes'}->{$dpid}->{'name'} . " has left");
    $self->{'nodes'}->{$dpid}->{'status'} = OESS_NODE_DOWN;
}

sub datapath_join_callback{
    my $self = shift;
    my $dpid = shift;

    $self->{'logger'}->debug("Node: " . $dpid . " has joined");
    $self->{'logger'}->warn("Node: " . $self->{'nodes'}->{$dpid}->{'name'} . " has joined");
    $self->{'nodes'}->{$dpid}->{'status'} = OESS_NODE_UP;

}

sub link_event_callback{
    my $self = shift;
    my $a_dpid = shift;
    my $a_port = shift;
    my $z_dpid = shift;
    my $z_port = shift;
    my $status = shift;

    
    

}

sub do_work{
    my $self = shift;

    $self->{'logger'}->debug("checking forwarding on links");

    foreach my $link_name (keys(%{$self->{'links'}})){
	
        my $link = $self->{'links'}->{$link_name};

        $self->{'logger'}->debug("Checking Forwarding on link: " . $link->{'name'});
        my $a_end = {node => $link->{'a_node'}, int => $link->{'a_port'}};
        my $z_end = {node => $link->{'z_node'}, int => $link->{'z_port'}};
        
        if(!defined($self->{'last_heard'}->{$a_end->{'node'}}->{$a_end->{'int'}}) ||
           !defined($self->{'last_heard'}->{$z_end->{'node'}}->{$z_end->{'int'}})){
            #we have never received it at least not since we were started...
            if($self->{'links'}->{$link->{'name'}}->{'status'} == OESS_LINK_UP){
                $self->{'logger'}->error("An error has occurred Forwarding Verification, considering link " . $link->{'name'} . " down");
                #fire link down
            }else{
                $self->{'logger'}->error("Forwarding verification for link: " . $link->{'name'} . " is experiencing an error");
            }
            #no need to do more work... go to next one
	    next;
        }

        if($self->{'node'}->{$a_end->{'node'}}->{'status'} == OESS_NODE_DOWN ||
           $self->{'node'}->{$z_end->{'node'}}->{'status'} == OESS_NODE_DOWN){
            $self->{'logger'}->debug("node is down for one side... not checking");
            next;            
        }
        
        #verify both ends came and went from the right nodes/interfaces
        if($self->{'last_heard'}->{$a_end->{'node'}}->{$a_end->{'int'}}->{'originator'}->{'node'} eq $z_end->{'node'} &&
           $self->{'last_heard'}->{$a_end->{'node'}}->{$a_end->{'int'}}->{'originator'}->{'int'} eq $z_end->{'int'} &&
           $self->{'last_heard'}->{$a_end->{'node'}}->{$a_end->{'int'}}->{'originator'}->{'node'} eq $a_end->{'node'} &&
           $self->{'last_heard'}->{$z_end->{'node'}}->{$z_end->{'int'}}->{'originator'}->{'int'} eq $a_end->{'int'}){
            
            $self->{'logger'}->debug("Packet origins/outputs line up with what we expected");
            
            #verify the last heard time is good
            if($self->{'last_heard'}->{$z_end->{'node'}}->{$z_end->{'int'}}->{'ts'} + $self->{'timeout'} < time() && 
               $self->{'last_heard'}->{$a_end->{'node'}}->{$a_end->{'int'}}->{'ts'} + $self->{'timeout'} < time() ){
                $self->{'logger'}->debug("link " . $link->{'name'} . " is operating as expected");
                #link is good
                if($self->{'links'}->{$link->{'name'}}->{'status'} == OESS_LINK_DOWN){
                    $self->{'logger'}->warn("Link: " . $link->{'name'} . " forwarding restored!");
                    #fire link up
                }else{
                    $self->{'logger'}->debug("link " . $link->{'name'} . " is still up");
                }
            }else{
                $self->{'logger'}->debug("Link: " . $link->{'name'} . " is not function properly");
                #link is bad!
                if($self->{'link'}->{$link->{'name'}}->{'status'} == OESS_LINK_UP){
                    $self->{'logger'}->warn("LINK " . $link->{'name'} . " forwarding disrupted!!!! Considered DOWN!");
                    #fire link down
                }else{
                    $self->{'logger'}->debug("Link " . $link->{'name'} . " is still down");
                }
            }
        }else{
            #uh oh the endpoints don't line up... update our db records (maybe a migration/node insertion happened) other wise we are busted
            
        }
    }

    #ok now send out our packets
    foreach my $link_name (keys(%{$self->{'links'}})){

	my $link = $self->{'links'}->{$link_name};

        $self->{'logger'}->debug("Checking Forwarding on link: " . $link->{'name'});
        my $a_end = {node => $link->{'a_node'}, int => $link->{'a_port'}};
	my $z_end = {node => $link->{'z_node'}, int => $link->{'z_port'}};

	my $res = $self->{'dbus'}->send_fv_packet($self->{'nodes'}->{$a_end->{'node'}}->{'dpid'},
						  $a_end->{'int'}->{'port_no'},
						  $self->{'nodes'}->{$z_end->{'node'}}->{'dpid'},
						  $z_end->{'int'}->{'port_no'},$self->{'vlan_id'});

	$res    = $self->{'dbus'}->send_fv_packet($self->{'nodes'}->{$z_end->{'node'}}->{'dpid'},
						  $z_end->{'int'}->{'port_no'},
						  $self->{'nodes'}->{$a_end->{'node'}}->{'dpid'},
						  $a_end->{'int'}->{'port_no'},$self->{'vlan_id'});
    }

}

    
sub fv_packet_in_callback{
    my $self = shift;
    my $dpid = shift;
    my $port = shift;
    my $packet = shift;

    $self->{'logger'}->debug("received a FV packet in!!!");
    
    
}


1;
