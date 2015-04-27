#!/usr/bin/perl

use strict;
use warnings;

package OESS::Circuit;

use Log::Log4perl;
use OESS::FlowRule;
use Graph::Directed;
use Data::Dumper;
use OESS::Topology;
#link statuses
use constant OESS_LINK_UP       => 1;
use constant OESS_LINK_DOWN     => 0;
use constant OESS_LINK_UNKNOWN  => 2;

=head1 NAME

OESS::Circuit - Circuit Interaction Module

=head1 SYNOPSIS

This is a module to provide a simplified object oriented way to connect to
and interact with the OESS Circuits.

Some examples:

    use OESS::Circuit;

    my $ckt = OESS::Circuit->new( circuit_id => 100, db => new OESS::Database());

    my $circuit_id = $ckt->get_id();

    if (! defined $circuit_id){
        warn "Uh oh, something bad happened: " . $circuit->get_error();
        exit(1);
    }

    my $success = $circuit->change_path();
    
=cut


=head2 new

    Creates a new OESS::Circuit object
    requires an OESS::Database handle
    and either the details from get_circuit_details or a circuit_id

=cut

sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS.Circuit");

    my %args = (
	details => undef,
	circuit_id => undef,
	db => undef,
	just_display => 0,
        link_status => undef,
        @_
        );

    my $self = \%args;

    bless $self, $class;

    $self->{'logger'} = $logger;

    if(!defined($self->{'db'})){
	$self->{'logger'}->error("No Database Object specified");
	return;
    }

    if(!defined($self->{'circuit_id'}) && !defined($self->{'details'})){
	$self->{'logger'}->error("No circuit id or details specified");
	return;
    }

    if(!defined($self->{'topo'})){
        $self->{'topo'} = OESS::Topology->new( db => $self->{'db'});
    }

    if(defined($self->{'details'})){
	$self->_process_circuit_details();
    }else{
	$self->_load_circuit_details();
    }

    return $self;
}

=head2 get_id

    returns the id of the circuit

=cut

sub get_id{
    my $self = shift;
    return $self->{'circuit_id'};
}

=head2 get_name

=cut

sub get_name{
    my $self = shift;
    return $self->{'details'}->{'name'};
}

=head2 get_restore_to_primary

=cut

sub get_restore_to_primary{
    my $self = shift;
    return $self->{'details'}->{'restore_to_primary'};
}

=head2 update_circuit_details

    reload the circuit details from the database to make sure everything 
    is in sync with what should be there

=cut

sub update_circuit_details{
    my $self = shift;
    $self->{'graph'} = {};
    $self->{'endpoints'} = {};
    $self->{'flows'} = {};
    $self->_load_circuit_details();
}

sub _load_circuit_details{
    my $self = shift;
    $self->{'logger'}->debug("Loading Circuit data for circuit: " . $self->{'circuit_id'});
    my $data = $self->{'db'}->get_circuit_details( circuit_id => $self->{'circuit_id'}, link_status => $self->{'link_status'});
    $self->{'details'} = $data;
    $self->_process_circuit_details();
}

sub _process_circuit_details{
    my $self = shift;
    $self->{'circuit_id'} = $self->{'details'}->{'circuit_id'};
    $self->{'logger'}->debug("Processing circuit " . $self->{'circuit_id'});
    $self->{'active_path'} = $self->{'details'}->{'active_path'};
    $self->{'logger'}->debug("Active path: " . $self->get_active_path());
    $self->{'static_mac'} = $self->{'details'}->{'static_mac'};
    $self->{'has_backup_path'} = 0;
    $self->{'interdomain'} = 0;
    if(scalar(@{$self->{'details'}->{'backup_links'}}) > 0){
        $self->{'logger'}->debug("Circuit has backup path");
	$self->{'has_backup_path'} = 1;
    }

    $self->{'endpoints'} = $self->{'details'}->{'endpoints'};

    foreach my $endpoint (@{$self->{'endpoints'}}){
        if($endpoint->{'local'} == 0){
            $self->{'interdomain'} = 1;
        }
    }

    if(!$self->{'just_display'}){       
        $self->_create_graph();
        $self->_create_flows();
    }
}



sub _create_graph{
    my $self = shift;

    $self->{'logger'}->debug("Creating graphs for circuit " . $self->{'circuit_id'});
    my @links = @{$self->{'details'}->{'links'}};

    $self->{'logger'}->debug("Creating a Graph for the primary path for the circuit " . $self->{'circuit_id'});

    my $p = Graph::Undirected->new;
    foreach my $link (@links){
        $p->add_vertex($link->{'node_z'});
        $p->add_vertex($link->{'node_a'});
        $p->add_edge($link->{'node_a'},$link->{'node_z'});
    }

    $self->{'graph'}->{'primary'} = $p;

    if($self->has_backup_path()){
	
	$self->{'logger'}->debug("Creating a Graph for the backup path for the circuit " . $self->{'circuit_id'});

	@links = @{$self->{'details'}->{'backup_links'}};
	my $b = Graph::Undirected->new;
	
	foreach my $link (@links){
	    $b->add_vertex($link->{'node_z'});
	    $b->add_vertex($link->{'node_a'});
	    $b->add_edge($link->{'node_a'},$link->{'node_z'});
	}
	
	$self->{'graph'}->{'backup'} = $b;
    }

}

sub _create_flows{
    my $self = shift;

    #create the flows    
    my $circuit_details = $self->{'details'};
    my $internal_ids= $self->{'details'}->{'internal_ids'};

    if (!defined $circuit_details) {
        $self->{'logger'}->error("No Such Circuit circuit_id: " . $self->{'circuit_id'});
        return undef;
    }
    
    my $dpid_lookup  = $self->{'db'}->get_node_dpid_hash();
    $self->{'dpid_lookup'} = $dpid_lookup;
    
    sub _process_links {
        my $links        = shift;
        my $internal_ids = shift;

        my $path_dict = {};
        foreach my $link (@$links){
            my $node_a = $link->{'node_a'};
            my $node_z = $link->{'node_z'};
            my $port_a = $link->{'port_no_a'}; 
            my $port_z = $link->{'port_no_z'}; 
            my $vlan_a = $internal_ids->{$node_a}{$link->{'interface_a_id'}};
            my $vlan_z = $internal_ids->{$node_z}{$link->{'interface_z_id'}};

            push(@{$path_dict->{$node_a}},{
                port             => $port_a,
                port_vlan        => $vlan_a,
                remote_port_vlan => $vlan_z
            });
            push(@{$path_dict->{$node_z}},{
                port             => $port_z,
                port_vlan        => $vlan_z,
                remote_port_vlan => $vlan_a
            });
        }
        return $path_dict;
    }

    # process primary links
    $self->{'path'}{'primary'} = _process_links( 
        $self->{'details'}->{'links'},
        $internal_ids->{'primary'}
    );        
    # process backup links
    $self->{'path'}{'backup'}  = _process_links( 
        $self->{'details'}->{'backup_links'},
        $internal_ids->{'backup'}
    ) if($self->has_backup_path());
    
    #do static mac addrs
    if($self->is_static_mac()){
        #generate normal flows that go on the path
        $self->_generate_static_mac_path_flows( path => 'primary');
        if($self->has_backup_path()){
            $self->{'logger'}->debug("generating static mac backup flows");
            $self->_generate_static_mac_path_flows( path => 'backup');
        }
    }
    
    #we always do this part static mac addresses or not
    #primary path rules
    $self->_generate_path_flows(path => 'primary');
    #backup path rules
    if($self->has_backup_path()){
        $self->{'logger'}->debug("generating backup path flows");
	$self->_generate_path_flows(path => 'backup');
    }
    #endpoint/flood rules
    $self->_generate_endpoint_flows( path => 'primary');
    
    if($self->has_backup_path()){
        $self->{'logger'}->debug("Generating backup path endpoint flows");
	$self->_generate_endpoint_flows( path => 'backup');
    }    

    $self->{'flows'}->{'path'}->{'primary'} = $self->_dedup_flows($self->{'flows'}->{'path'}->{'primary'});
    $self->{'flows'}->{'path'}->{'backup'} = $self->_dedup_flows($self->{'flows'}->{'path'}->{'backup'});
    $self->{'flows'}->{'endpoint'}->{'primary'} = $self->_dedup_flows($self->{'flows'}->{'endpoint'}->{'primary'});
    $self->{'flows'}->{'endpoint'}->{'backup'} = $self->_dedup_flows($self->{'flows'}->{'endpoint'}->{'backup'});

}


sub _dedup_flows{
    my $self = shift;
    
    my $flows = shift;
    
    my @deduped = ();

    foreach my $flow (@$flows){
	my $matched = 0;
	foreach my $de_duped_flow (@deduped){
            if(!defined($flow) || !defined($de_duped_flow)){
                next;
            }
            if($de_duped_flow->get_dpid() != $flow->get_dpid()){
                next;
            }
	    if($de_duped_flow->compare_match( flow_rule => $flow)){
		$de_duped_flow->merge_actions( flow_rule => $flow);
		$matched = 1;
	    }
	}
	if($matched == 0){
	    push(@deduped,$flow);
	}
    }

    return \@deduped;
}


sub _generate_static_mac_path_flows{
    my $self = shift;
    my %args = @_;
    
    my $path = $args{'path'};
    
    my %node_ends;
    my %in_ports;
    
    #push our endpoints into the list of in_ports for each node
    foreach my $endpoint (@{$self->{'details'}->{'endpoints'}}){

        if(!defined($node_ends{$endpoint->{'node'}})){
            $node_ends{$endpoint->{'node'}} = 0;
        }

        $node_ends{$endpoint->{'node'}}++;
        if(!defined($in_ports{$endpoint->{'node'}})){
            $in_ports{$endpoint->{'node'}} = ();
        }
        push(@{$in_ports{$endpoint->{'node'}}},$endpoint);
    }
    
    my $graph = $self->{'graph'}->{$path};
    my $internal_ids = $self->{'details'}->{'internal_ids'};
    
    #finds the links when we just have a node and node
    #
    my %finder;
    
    my $links;

    if($path eq 'primary'){
	$links = $self->{'details'}->{'links'};
    }else{
	$links = $self->{'details'}->{'backup_links'};
    }    

    #need to setup some data structures to get the data we want
    foreach my $link (@{$links}) {
        my $node_a = $link->{'node_a'};
        my $node_z = $link->{'node_z'};
        my $interface_a =$link->{'interface_a_id'};
        my $interface_z = $link->{'interface_z_id'};

        if(!defined($in_ports{$node_a})){
            $in_ports{$node_a} = ();
        }
        
        if(!defined($in_ports{$node_z})){
            $in_ports{$node_z} = ();
        }

        push(@{$in_ports{$node_a}},{link_id => $link->{'link_id'}, port_no => $link->{'port_no_a'}, tag => $internal_ids->{$path}{$node_z}{$interface_z}});
        push(@{$in_ports{$node_z}},{link_id => $link->{'link_id'}, port_no => $link->{'port_no_z'}, tag => $internal_ids->{$path}{$node_a}{$interface_a}});
        
        $finder{$node_a}{$node_z} = $link;
        $finder{$node_z}{$node_a} = $link;
    }

    
    my @verts = $graph->vertices;
    
    
    foreach my $vert (@verts){
        if(!defined($node_ends{$vert})){
            $node_ends{$vert} =0;
        }
	$self->{'logger'}->debug("Vert: " . $vert . " has degree: " . $graph->degree($vert) . " and " . $node_ends{$vert} .
				 " endpoints for total degree " . ($graph->degree($vert) + $node_ends{$vert}));

	#check to see what degree our node is
	next if(($graph->degree($vert) + $node_ends{$vert})  <= 2);
	
	$self->{'logger'}->debug("Processing a complex node with more than 2 edges");
	#complex node!!! take the endpoints and find the paths to each of them!
	my @edges = $graph->edges_to($vert);

	foreach my $edge ($graph->edges_to($vert)){
	    $self->{'logger'}->debug("Finding link between " . $edge->[0] . " and " . $edge->[1]);
	    #my $link = $finder{$edge->[0]}{$edge->[1]};
            #this will process
	    foreach my $endpoint (@{$self->{'details'}->{'endpoints'}}){
		$self->{'logger'}->debug("Finding shortest path between " . $vert . " and " . $endpoint->{'node'});
		
		my @next_hop = $graph->SP_Dijkstra($vert, $endpoint->{'node'});
				
		if(defined($next_hop[1])){
		    my $link = $finder{$next_hop[0]}{$next_hop[1]};
		    #if we could find a link do it
		
		    if(!defined($link)){
			$self->{'logger'}->error("Couldn't find the link... but there should be one!");
                        next;
		    }

		    my $port;
                    my $interface_id;
		    if($link->{'node_a'} eq $vert){
			$port = $link->{'port_no_a'};
                        $interface_id = $link->{'interface_z_id'}
		    }else{
			$port = $link->{'port_no_z'};
                        $interface_id = $link->{'interface_a_id'}
		    }
		    
		    foreach my $in_port (@{$in_ports{$vert}}){
			#if the in port matches the out port go on to next
			next if($in_port->{'port_no'} == $port);

			#for each mac addr
			foreach my $mac_addr (@{$endpoint->{'mac_addrs'}}){
			    
			    $self->{'logger'}->debug("Creating flow for mac_addr " . $mac_addr->{'mac_address'} . " on node " . $vert);
			    $self->{'logger'}->debug("Next hop: " . $next_hop[1] . " and path: " . $path . " and vlan " . $internal_ids->{$path}{$next_hop[1]}{$interface_id});
			    my $flow = OESS::FlowRule->new( match => {'dl_vlan' => $in_port->{'tag'},
								      'in_port' => $in_port->{'port_no'},
								      'dl_dst' => OESS::Database::mac_hex2num($mac_addr->{'mac_address'})},
							    priority => 35000,
							    dpid => $self->{'dpid_lookup'}->{$vert},
							    actions => [{'set_vlan_vid' => $internal_ids->{$path}{$next_hop[1]}{$interface_id}},
									{'output' => $port}]);
			    
			    push(@{$self->{'flows'}->{'static_mac_addr'}->{$path}},$flow);
			    
			}
		    }
		    
		}else{
		    
		    $self->{'logger'}->debug("not a link");
		    #endpoint must be on this node
		    foreach my $in_port (@{$in_ports{$vert}}){

			#if the in port matches the out port go on to next
			next if($in_port->{'port_no'} == $endpoint->{'port_no'});
			#for each mac addr
			foreach my $mac_addr (@{$endpoint->{'mac_addrs'}}){
			    
			    $self->{'logger'}->debug("Creating flow for mac_addr " . $mac_addr->{'mac_address'} . " on node " . $vert);
			    my $flow = OESS::FlowRule->new( match => {'dl_vlan' => $in_port->{'tag'},
								      'in_port' => $in_port->{'port_no'},
								      'dl_dst' => OESS::Database::mac_hex2num($mac_addr->{'mac_address'})},
							    priority =>35000,
							    dpid => $self->{'dpid_lookup'}->{$vert},
							    actions => [{'set_vlan_vid' => $endpoint->{'tag'}},
									{'output' => $endpoint->{'port_no'}}]);
			    push(@{$self->{'flows'}->{'static_mac_addr'}->{$path}},$flow);
			}
		    }
		}
	    }
	}
    }
}

sub _generate_endpoint_flows {
    my $self = shift;
    my %args = @_;
    my $path = $args{'path'};

    # if this is a loopback circuit generate the endpoint flows differently
    if($self->{'topo'}->is_loopback($self->{'details'}{'endpoints'})){
        $self->_generate_loopback_endpoint_flows( path => $path );
        return;
    }

    # otherwise generate rules normally 
    # get a hash of all of the ways we know how to exit a node on our path
    my $path_dict  = $self->{'path'}{$path};
    foreach my $endpoint (@{$self->{'details'}->{'endpoints'}}) {
        my $e_node = $endpoint->{'node'};
        my $e_dpid = $self->{'dpid_lookup'}{$e_node};
        my $e_port = $endpoint->{'port_no'};
        my $e_vlan = $endpoint->{'tag'};

        # handle interswitch circuit
        foreach my $other_endpoint (@{$self->{'details'}->{'endpoints'}}){
            # only want endpoints on the same node
            next if( $endpoint->{'node'} ne $other_endpoint->{'node'} );
            # only want local endpoints
            next if( ($endpoint->{'local'} == 0) || ($other_endpoint->{'local'} == 0) );
            # only want endpoints on the same node on a different interface
            next if( $endpoint->{'port_no'} eq $other_endpoint->{'port_no'} );

            # if we've gotten here we have an interswitch circuit and le rules for it 
            my $other_e_port = $other_endpoint->{'port_no'};
            my $other_e_vlan = $other_endpoint->{'tag'};

            # coming in endpoint going out to other_endpoint
            push(@{$self->{'flows'}{'endpoint'}{$path}}, OESS::FlowRule->new(
                dpid  => $e_dpid,
                match => {
                    dl_vlan => $e_vlan,
                    in_port => $e_port
                },
                actions => [
                    {'set_vlan_vid' => $other_e_vlan},
                    {'output'       => $other_e_port}
                ]
            ));

            # coming in other_endpoint going out endpoint
            push(@{$self->{'flows'}{'endpoint'}{$path}}, OESS::FlowRule->new(
                dpid  => $e_dpid,
                match => {
                    dl_vlan => $other_e_vlan,
                    in_port => $other_e_port
                },
                actions => [
                    {'set_vlan_vid' => $e_vlan},
                    {'output'       => $e_port}
                ]
            ));

        }

        foreach my $node_exit (@{$path_dict->{$e_node}}){
            # rule for data coming from the endpoint out to the circuit path
            my $from_endpoint = OESS::FlowRule->new(
                dpid  => $e_dpid,
                match => {
                    dl_vlan => $e_vlan,
                    in_port => $e_port
                },
                actions => [
                    {'set_vlan_vid' => $node_exit->{'remote_port_vlan'}},
                    {'output'       => $node_exit->{'port'}}
                ]
            );
            # push our rule onto our endpoint rule hash
            push(@{$self->{'flows'}{'endpoint'}{$path}},$from_endpoint);
        }
    }
}

=head2
    Method that generates the endpoint rules for a loopback circuit
=cut
sub _generate_loopback_endpoint_flows {
    my ($self, %args) = @_;

    my $path = $args{'path'};


    my $path_dict = $self->{'path'}{$path};

    my $link_type = ($path eq 'primary') ? 'links' : 'backup_links';
    my @endpoints = sort({ $a->{'tag'} cmp $b->{'tag'} } @{$self->{'details'}{'endpoints'}});


    my $get_port_dict = sub {
        my $node = shift;
        my $port = shift;

        foreach my $dict (@{$path_dict->{$node}}){
            return $dict if($dict->{'port'} eq $port);
        }
        return;
    };

    # get the info we need to get to/from the adjacent nodes from our loop endpoint
    my @rules    = ();
    my @links = sort({ $a->{'name'} cmp $b->{'name'} } @{$self->{'details'}{$link_type}});

    if(scalar(@links) == 0){
        #endpoint to endpoint rules
        for(my $i=0;$i<scalar(@endpoints);$i++){
            my $e  = $endpoints[$i];
            my @actions;
            for(my $j=0;$j<scalar(@endpoints);$j++){
                next if($i==$j);
                my $remote_port = $endpoints[$j];
                
                push(@actions,{'set_vlan_vid' => $remote_port->{'tag'}});
                push(@actions,{'output' => $remote_port->{'port_no'}});
            }
            
            push(@{$self->{'flows'}->{'endpoint'}->{$path}}, OESS::FlowRule->new(
                 match => {
                     'dl_vlan' => $e->{'tag'},
                     'in_port' => $e->{'port_no'}
                 },
                 dpid => $self->{'dpid_lookup'}->{$e->{'node'}},
                 actions => \@actions
             ));    
        }
    } else {
        foreach my $l (@links){
            my $id;
            # pick either endpoints node (should be the same since its a loopback circuit)
            my $interface_id;
            if( $l->{'node_a'} eq $endpoints[0]{'node'} ){
                $id='a';
                $interface_id = $l->{'interface_a_id'};
            }
            
            if( $l->{'node_z'} eq $endpoints[0]{'node'} ){
                $id = 'z';
                $interface_id = $l->{'interface_z_id'};
            }
            if(defined($id)){
                my $port_dict = &$get_port_dict( $l->{"node_$id"}, $l->{"port_no_$id"} );
                push(@rules, { 
                    remote_port_vlan => $port_dict->{'remote_port_vlan'}, 
                    port => $l->{"port_no_$id"},
                    port_vlan => $port_dict->{'port_vlan'}
                });
            }
        }

        foreach my $e (@endpoints){
            my $rule             = pop(@rules);
            my $port_to_adj_node = $rule->{'port'};
            my $remote_port_vlan = $rule->{'remote_port_vlan'};
            my $port_vlan        = $rule->{'port_vlan'};
            
            # create the rule coming from the edge interface out to an adjacent node
            push(@{$self->{'flows'}->{'endpoint'}->{$path}}, OESS::FlowRule->new(
                     match => {
                         'dl_vlan' => $e->{'tag'},
                         'in_port' => $e->{'port_no'}
                     },
                     dpid => $self->{'dpid_lookup'}->{$e->{'node'}},
                     actions => [
                         {'set_vlan_vid' => $remote_port_vlan },
                         {'output' => $port_to_adj_node }
                     ]
                 ));
            
            # create the rule coming from an adjacent node into the edge interface
            # push these onto both paths
            my $to_endpoint = OESS::FlowRule->new( 
                 match => {
                     'dl_vlan' => $port_vlan,
                     'in_port' => $port_to_adj_node
                 },
                 dpid => $self->{'dpid_lookup'}->{$e->{'node'}},
                 actions => [
                     {'set_vlan_vid' => $e->{'tag'}},
                     {'output' => $e->{'port_no'}}
                 ]
            );
            push(@{$self->{'flows'}->{'endpoint'}->{'primary'}}, $to_endpoint);
            push(@{$self->{'flows'}->{'endpoint'}->{'backup'}},  $to_endpoint);
        }
    }
}
sub _generate_path_flows {
    my $self   = shift;
    my %params = @_;

    my $path      = $params{'path'};
    my $path_dict = $self->{'path'}{$path};

    foreach my $node (keys %$path_dict) {
        #--- skip if node is on an endpoint and circuit is a loopback circuit
        #--- all necessary rules generated in _generate_loopback_endpoint_flows
        if($self->{'topo'}->is_loopback($self->{'details'}{'endpoints'})){
            my $is_endpoint_node = 0;
            foreach my $endpoint (@{$self->{'details'}{'endpoints'}}){
                if($endpoint->{'node'} eq $node){
                    $is_endpoint_node = 1;
                    last;
                }
            }
            next if($is_endpoint_node);
        }

        my $dpid   = $self->{'dpid_lookup'}->{$node};
        # loop through each path bit of path info and use the info for a match
        foreach my $enter (@{$path_dict->{$node}}){
            # loop through each bit of path info and use the info for an output action
            foreach my $exit (@{$path_dict->{$node}}){
                # dont' add a rule coming in and leaving on the same port
                next if($enter->{'port'} eq $exit->{'port'});

                push(@{$self->{'flows'}{'path'}{$path}}, OESS::FlowRule->new(
                    match => {
                        dl_vlan => $enter->{'port_vlan'},
                        in_port => $enter->{'port'}
                    },
                    dpid =>  $dpid,
                    actions => [
                        {'set_vlan_vid' => $exit->{'remote_port_vlan'}},
                        {'output'       => $exit->{'port'}}
                    ]
                ));
            }
        }
    }

    # now handle rules on the path going to the endpoint
    foreach my $endpoint (@{$self->{'details'}->{'endpoints'}}) {
        my $e_node = $endpoint->{'node'};
        my $e_dpid = $self->{'dpid_lookup'}{$e_node};
        my $e_port = $endpoint->{'port_no'};
        my $e_vlan = $endpoint->{'tag'};

        foreach my $node_exit (@{$path_dict->{$e_node}}){
            # rule for data coming from inside to circuit path to the endpoint
            my $to_endpoint = OESS::FlowRule->new(
                dpid  => $e_dpid,
                match => {
                    dl_vlan => $node_exit->{'port_vlan'},
                    in_port => $node_exit->{'port'}
                },
                actions => [
                    {'set_vlan_vid' => $e_vlan},
                    {'output'       => $e_port}
                ]
            );
            # push flows to the endpoint onto both paths for resilency if
            # the network state gets confused about which is the primary path
            push(@{$self->{'flows'}{'path'}{$path}},$to_endpoint);
        }
    }

}

=head2 get_flows

=cut

sub get_flows{
    my $self = shift;
    my %params = @_;	
    my @flows;

    if (!defined($params{'path'})){


    	foreach my $flow (@{$self->{'flows'}->{'path'}->{'primary'}}){
		push(@flows,$flow);
    	}

    	foreach my $flow (@{$self->{'flows'}->{'path'}->{'backup'}}){
		push(@flows,$flow);
    	}

    	if($self->get_active_path() eq 'primary'){
        
        	foreach my $flow (@{$self->{'flows'}->{'endpoint'}->{'primary'}}){
            	push(@flows,$flow);
        	}

		foreach my $flow (@{$self->{'flows'}->{'static_mac_addr'}->{'primary'}}){
	    	push(@flows,$flow);
		}

    	}else{

        	foreach my $flow (@{$self->{'flows'}->{'endpoint'}->{'backup'}}){
            	push(@flows,$flow);
        	}

		foreach my $flow (@{$self->{'flows'}->{'static_mac_addr'}->{'backup'}}){
	   	 push(@flows,$flow);
		}

    	}

	}

else {
	my $path = $params{'path'};
	if($path ne 'primary' && $path ne 'backup'){
        $self->{'logger'}->error("Path '$path' is invalid");
        return;
    }

	foreach my $flow (@{$self->{'flows'}->{'path'}->{$path}}){
                push(@flows,$flow);
        }

	foreach my $flow (@{$self->{'flows'}->{'endpoint'}->{$path}}){
                push(@flows,$flow);
                }

	foreach my $flow (@{$self->{'flows'}->{'static_mac_addr'}->{$path}}){
                push(@flows,$flow);
                }


}
    #if the number of endpoints is more than 2 and it is not interdomain
    if(scalar(@{$self->get_endpoints()}) > 2 && $self->is_interdomain()){
        return $self->_dedup_flows(\@flows);
    }else{
        return \@flows;
    }
}

=head2 get_endpoint_flows

=cut

sub get_endpoint_flows{
    my $self = shift;
    my %params = @_;

    my $path = $params{'path'};

    if(!defined($path)){
	$self->{'logger'}->error("Path was not defined");
	return;
    }
    
    if($path ne 'primary' && $path ne 'backup'){
	$self->{'logger'}->error("Path '$path' is invalid");
	return;
    }

    return $self->{'flows'}->{'endpoint'}->{$path};    
}



=head2 get_details

=cut

sub get_details{
    my $self = shift;
    return $self->{'details'};
}

=head2 generate_clr

=cut

sub generate_clr{
    my $self = shift;

    my $clr = "";
    $clr .= "Circuit: " . $self->{'details'}->{'name'} . "\n";
    $clr .= "Created by: " . $self->{'details'}->{'created_by'}->{'given_names'} . " " . $self->{'details'}->{'created_by'}->{'family_name'} . " at " . $self->{'details'}->{'created_on'} . " for workgroup " . $self->{'details'}->{'workgroup'}->{'name'} . "\n";
    $clr .= "Lasted Modified By: " . $self->{'details'}->{'last_modified_by'}->{'given_names'} . " " . $self->{'details'}->{'last_modified_by'}->{'family_name'} . " at " . $self->{'details'}->{'last_edited'} . "\n\n";
    $clr .= "Endpoints: \n";

    foreach my $endpoint (@{$self->get_endpoints()}){
        if ($endpoint->{'tag'} == OESS::FlowRule::UNTAGGED ){ $endpoint->{'tag'} = 'Untagged'; }
	$clr .= "  " . $endpoint->{'node'} . " - " . $endpoint->{'interface'} . " VLAN " . $endpoint->{'tag'} . "\n";
    }

    $clr .= "\nPrimary Path:\n";
    foreach my $path (@{$self->get_path( path => 'primary' )}){
	$clr .= "  " . $path->{'name'} . "\n";
    }

    if($self->has_backup_path()){
        
        $clr .= "\nBackup Path:\n";
        foreach my $path (@{$self->get_path( path => 'backup' )}){
            $clr .= "  " . $path->{'name'} . "\n";
        }
    }

    return $clr;
}

=head2 generate_clr_raw

=cut

sub generate_clr_raw{
    
    my $self = shift;

    my $flows = $self->get_flows();

    my $str = "";

    foreach my $flow (@$flows){
        $str .= $flow->to_human() . "\n";
    }

    return $str;
}

=head2 get_endpoints

=cut

sub get_endpoints{
    my $self = shift;
    return $self->{'endpoints'};
}

=head2 has_backup_path

=cut

sub has_backup_path{
    my $self = shift;
    return $self->{'has_backup_path'};
}

=head2 get_path

=cut

sub get_path{
    my $self = shift;

    my %params = @_;

    my $path = $params{'path'};
    
    if(!defined($path)){
        $self->{'logger'}->error("Path was not defined");
        return;
    }

    $self->{'logger'}->trace("Returning links for path '$path'");
    
    if($path eq 'backup'){
        return $self->{'details'}->{'backup_links'};
    }else{
        return $self->{'details'}->{'links'};
    }
    
}

=head2 get_active_path

=cut

sub get_active_path{
    my $self = shift;
    
    return $self->{'active_path'};
}

=head2 change_path

=cut

sub change_path {
    my $self = shift;
    my %params = @_;

    my $do_commit = 1;
    if(defined($params{'do_commit'})){
        $do_commit = $params{'do_commit'};
    }

    #change the path

    if(!$self->has_backup_path()){
        $self->error("Circuit " . $self->{'name'} . " has no alternate path, refusing to try to switch to alternate.");
        return;
    }

    my $current_path = $self->get_active_path();
    my $alternate_path = 'primary';
    if($current_path eq 'primary'){
	$alternate_path = 'backup';
    }
    $self->{'logger'}->debug("Circuit ". $self->get_name()  . " is failing over to " . $alternate_path);

     my $query  = "select path.path_id from path " .
                 " join path_instantiation on path.path_id = path_instantiation.path_id " .
                 "  and path_instantiation.path_state = 'available' and path_instantiation.end_epoch = -1 " .
                 " where circuit_id = ?";
    
    my $results = $self->{'db'}->_execute_query($query, [$self->{'circuit_id'}]);
    my $new_active_path_id = $results->[0]->{'path_id'};
    if($do_commit){
        $self->{'db'}->_start_transaction();
    }
    # grab the path_id of the one we're switching away from
    $query = "select path_instantiation.path_id, path_instantiation.path_instantiation_id from path " .
	" join path_instantiation on path.path_id = path_instantiation.path_id " .
	" where path_instantiation.path_state = 'active' and path_instantiation.end_epoch = -1 " .
	" and path.circuit_id = ?";
    
    $results = $self->{'db'}->_execute_query($query, [$self->{'circuit_id'}]);

    if (! defined $results || @$results < 1){
        $self->error("Unable to find path_id for current path.");
        $self->{'db'}->_rollback();
        return;
    }

    my $old_active_path_id   = @$results[0]->{'path_id'};
    my $old_instantiation    = @$results[0]->{'path_instantiation_id'};

    # decom the current path instantiation
    $query = "update path_instantiation set path_instantiation.end_epoch = unix_timestamp(NOW()) " .
             " where path_instantiation.path_id = ? and path_instantiation.end_epoch = -1";

    my $success = $self->{'db'}->_execute_query($query, [$old_active_path_id]);

    if (! $success ){
        $self->error("Unable to change path_instantiation of current path to inactive.");
        $self->_rollback();
        return;
    }

    # create a new path instantiation of the old path
    $query = "insert into path_instantiation (path_id, start_epoch, end_epoch, path_state) " .
             " values (?, unix_timestamp(NOW()), -1, 'available')";

    my $new_available = $self->{'db'}->_execute_query($query, [$old_active_path_id]);

    if (! defined $new_available){
        $self->error("Unable to create new available path based on old instantiation.");
        $self->_rollback();
        return;
    }    

        # point the internal vlan mappings from the old over to the new path instance
    #$query = "update path_instantiation_vlan_ids set path_instantiation_id = ? where path_instantiation_id = ?";
    
    #$success = $self->{'db'}->_execute_query($query, [$new_available, $old_instantiation]);

    #if (! defined $success){
    #    $self->{'logger'}->error("Unable to move internal vlan id mappings over to new path instance");
    #    $self->error("Unable to move internal vlan id mappings over to new path instance.");
    #    $self->_rollback();
    #    return;
    #}

    # at this point, the old path instantiation has been decom'd by virtue of its end_epoch
    # being set and another one has been created in 'available' state based on it.

    # now let's change the state of the old available one to active
    $query = "update path_instantiation set path_state = 'active' where path_id = ? and end_epoch = -1";    

    $success = $self->{'db'}->_execute_query($query, [$new_active_path_id]);

    if (! $success){
        $self->{'logger'}->error("Unable to change state to active in alternate path");
        $self->error("Unable to change state to active in alternate path.");
        $self->{'db'}->_rollback();
        return;
    }
    
    if($do_commit){
        $self->{'db'}->_commit();
    }

    $self->{'active_path'} = $alternate_path;
    $self->{'details'}->{'active_path'} = $alternate_path;
    $self->{'logger'}->debug("Circuit " . $self->get_id() . " is now on " . $alternate_path);
    return 1;

}

=head2 is_interdomain

=cut

sub is_interdomain{
    my $self = shift;
    return $self->{'interdomain'};
}

=head2 is_static_mac

=cut

sub is_static_mac{
    my $self = shift;
    return $self->{'static_mac'};
}

=head2 get_path_status

=cut

sub get_path_status{
    my $self = shift;
    my %params = @_;

    my $path = $params{'path'};
    my $link_status = $params{'link_status'};

    if(!defined($path)){
	return;
    }
    
    my %down_links;
    my %unknown_links;
    
    if(!defined($link_status)){
        my $links = $self->{'db'}->get_current_links();
        
        foreach my $link (@$links){


            if( $link->{'status'} eq 'down'){
                $down_links{$link->{'name'}} = $link;
            }elsif($link->{'status'} eq 'unknown'){
                $unknown_links{$link->{'name'}} = $link;
            }

        }

    }else{
        foreach my $key (keys (%{$link_status})){
            if($link_status->{$key} == OESS_LINK_DOWN){
                $down_links{$key} = 1;
            }elsif($link_status->{$key} == OESS_LINK_UNKNOWN){
                $unknown_links{$key} = 1;
            }
        }
    }

    my $path_links = $self->get_path( path => $path );

    foreach my $link (@$path_links){

        if( $down_links{ $link->{'name'} } ){
	    $self->{'logger'}->warn("Path is down because link: " . $link->{'name'} . " is down");
            return 0;
        }elsif($unknown_links{$link->{'name'}}){
	    $self->{'logger'}->warn("Path is unknown because link: " . $link->{'name'} . " is unknown");
            return 2;
        }

    }
    
    return 1;

}

=head2 error

=cut

sub error{
    my $self = shift;
    my $error = shift;
    if(defined($error)){
        $self->{'error'} = $error;
    }
    return $self->{'error'};
}

1;
