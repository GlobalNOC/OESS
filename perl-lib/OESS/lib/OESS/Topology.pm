#!/usr/bin/perl
##----- NDDI OESS Topology module
##-----
##----- $HeadURL: svn+ssh://svn.grnoc.iu.edu/grnoc/oe-ss/perl-lib/OESS-Topology/trunk/lib/OESS/Topology.pm $
##----- $Id$
##----- $Date$
##----- $LastChangedBy$
##-----
##----- Does shortest path calculations for the UI
##----------------------------------------------------------------------
##
## Copyright 2011 Trustees of Indiana University
##
##   Licensed under the Apache License, Version 2.0 (the "License");
##   you may not use this file except in compliance with the License.
##   You may obtain a copy of the License at
##
##       http://www.apache.org/licenses/LICENSE-2.0
##   Unless required by applicable law or agreed to in writing, software
##   distributed under the License is distributed on an "AS IS" BASIS,
##   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
##   See the License for the specific language governing permissions and
##   limitations under the License.
#

use strict;
use warnings;

package OESS::Topology;

use OESS::Database;
use Set::Scalar;
use Graph::Directed;
use List::MoreUtils qw{uniq};
use Data::Dumper;
use Log::Log4perl;

#link statuses
use constant OESS_LINK_UP       => 1;
use constant OESS_LINK_DOWN     => 0;
use constant OESS_LINK_UNKNOWN  => 2;

#circuit statuses
use constant OESS_CIRCUIT_UP    => 1;
use constant OESS_CIRCUIT_DOWN  => 0;
use constant OESS_CIRCUIT_UNKNOWN => 2;

=head1 NAME

OESS-Topology -Perl module for topology operations/computations on the OESS database.

=cut


=head1 SYNOPSIS

A module to get topology operations on the OE-SS Database

example:

	use OESS::Topology
	my $topology=OESS::Topology->new();

	my $link_list=find_path(
			nodes=>\@node_list;
			used_links=>\@used_link_list;
			reserved_bw=> 100; #in mbps
			);

=cut



=head1 Protected Methods

=head2 _set_error

Protected method used to document the point and reason an error occured

=cut

sub _set_error{
        my $self 	= shift;

        $self->{'error'}{'timestamp'}   = gmtime;
        $self->{'error'}{'message'}     = shift;

        if(defined $self->{'dbh'}){
           $self->{'error'}{'dbi_err'}  = $self->{'dbh'}->errstr;
        }else{
           $self->{'error'}{'dbi_err'}  = undef;
        }
        #$self->{'error'}{'stacktrace'}  = longmess;
        #$self->{'logger'}-error( "an error occured: " .  $self->{'error'}{'message'} );
}

=head2 get_error

returns the last reported error

=cut

sub get_error{
	my $self	= shift;
	return $self->{'error'};
}





=head2 new

Creates a new OESS-topology Object

=cut

sub new {
    my $class = shift;

    my $logger = Log::Log4perl->get_logger("OESS.Topology");

    my %args = (
	config              => "/etc/oess/database.xml",
	dbname              => undef,
	db                  => undef,
	remote_user         => undef,
	net		    => undef,
	wg		    => undef,
	@_,
        );

    my $self = \%args;
    bless($self,$class);

    $self->{'logger'} = $logger;

    if (! defined $self->{'db'}){
	my $db = OESS::Database->new(config => $args{'config'},
	                             topo   => $self
	                            );

	if (! defined $db){
	    return undef;
	}

	$self->{'db'}  = $db;
    }

    return $self;
}

=head2 get_database

=cut

sub get_database{
    my $self = shift;
    return $self->{'db'};
}


=head2 path_is_loop_free

  Checks a given path for a cycle / loop

=cut

sub path_is_loop_free{
    my $self = shift;
    my $path = shift;


    my $g = Graph::Undirected->new;

    foreach my $link (@$path){
        $g->add_vertex($link->{'node_z'});
        $g->add_vertex($link->{'node_a'});
        $g->add_edge($link->{'node_a'},$link->{'node_z'});
    }

    if($g->has_a_cycle()){
	$self->_set_error("Path has a loop!");
	return 0;
    }
    return 1;
}

=head2 all_endpoints_connected_in_path

    checks to see if all the endpoints are connected
    by the given path

=cut
sub all_endpoints_connected_in_path {
    my $self      = shift;
    my $path      = shift;
    my $endpoints = shift;

    my $g = Graph::Undirected->new;

    foreach my $link (@$path){
	$g->add_vertex($link->{'node_z'});
	$g->add_vertex($link->{'node_a'});
	$g->add_edge($link->{'node_a'}, $link->{'node_z'});
    }

    # make sure each endpoint has a path to each other endpoint
    foreach my $endpoint (@$endpoints){

	# we can't test connectivity to foreign places, skip that.
	next if ($endpoint->{'local'} eq 0);

	my $node = $endpoint->{'node'};

	foreach my $other_endpoint (@$endpoints){
	    my $other_node = $other_endpoint->{'node'};

	    next if ($node eq $other_node || $other_endpoint->{'local'} eq 0);

	    my @result = $g->SP_Dijkstra($node, $other_node);

	    if (! @result){
		$self->_set_error("Not all endpioints connected in path");
		return 0;
	    }
	}
    }

    return 1;
}


=head2 validate_paths

    for now this assumes the path we want to validate
    is part of a circuit record

=cut
#--- might want to have anothe varient that
#--- takes an arbtrary path so that we can do this in the ui

sub validate_paths {
    my ( $self, %args ) = @_;

    #-- get the circuit info
    my $links;
    my $backup_links;
    my $endpoints;
    if($args{'circuit_id'}){
        my $res = $self->{'db'}->get_circuit_details( circuit_id=> $args{'circuit_id'} );
        $links = $res->{'links'};
        $backup_links = $res->{'backup_links'};
        $endpoints = $res->{'endpoints'}
    }elsif( ($args{'links'} || $args{'backup_links'}) && $args{'endpoints'}){
        $links        = $self->{'db'}->get_links_details_by_name( names => $args{'links'} );
        if(!$links){
            $self->_set_error($self->{'db'}->get_error());
        }
        $backup_links = $self->{'db'}->get_links_details_by_name( names => $args{'backup_links'} );
        if(!$backup_links){
            $self->_set_error($self->{'db'}->get_error());
        }
        $endpoints = $args{'endpoints'};
    }else {
        $self->_set_error("Must pass in a circuit_id, a list or links, or a list of backup_links");
        return;
    }

    if(defined $links){
        if ( (!$self->path_is_loop_free($links)) && (!$self->is_loopback($endpoints)) ){
            $self->_set_error("Primary path contains a loop");
            return (0,"Primary path contains a loop.");
        }

        if (! $self->all_endpoints_connected_in_path($links, $endpoints)){
            $self->_set_error("Primary path does not connect all endpoints.");
            return (0,"Primary path does not connect all endpoints.");
        }
    }

    if(defined $backup_links){

        if ( (!$self->path_is_loop_free($backup_links)) && (!$self->is_loopback($endpoints)) ){
            $self->_set_error("Backup path contains a loop.");
            return (0,"Backup path contains a loop.");
        }

        if (@{$backup_links} > 0 && ! $self->all_endpoints_connected_in_path($backup_links, $endpoints)){
            $self->_set_error("Backup path does not connect all endpoints.");
            return (0,"Backup path does not connect all endpoints.");
        }
    }

    return 1;
}

=head2 is_loopback
    Checks to see if the endpoints are the same but on different vlans.
    If this returns true we should allow a path with a loop in it.    
=cut
sub is_loopback {
    my ($self, $endpoints)     = @_;

    # first ensure there are only two endpoints
    return 0 if(@$endpoints != 2);

    my $node;
    my $intf; # keeps the name of our interface
    my $known_vlans = {}; # hash of vlans we've used in our endpoints
    foreach my $endpoint (@$endpoints){
        if(!%$known_vlans && !defined($intf)){
            $intf = $endpoint->{'interface'};
            $known_vlans->{$endpoint->{'tag'}} = 1;
            $node = $endpoint->{'node'};
        }else {
            # if our endpoints are not all on the same interface this is not a valid loopback path
            return 0 if($intf ne $endpoint->{'interface'});
            # if we have used the same vlan tag twice this is not a valid loopback path
            return 0 if(defined($known_vlans->{$endpoint->{'tag'}}));
            return 0 if($node ne $endpoint->{'node'});
        }
    }

    return 1; 
}

=head2 find_path

    Attempts to find a path to the given nodes
    Here are the steps to complete

    step 0 -> sanity (at least two nodes).
    step 1 get nodes
    step 2 get links with available bandwidth
    step 3 build the graph
    step 4 make sure they can be connected
    step 5 select the root (and reoder the nodes?)
    step 6 (iterate for shortest path from the root for the rest).

=cut

sub find_path {
    my $self = shift;
    my %args = @_;

    warn "Finding the shortest path\n";
    $self->{'logger'}->debug("Finding shortest path");

    my @selected_links = ();

    my $reserved_bw = $args{'reserved_bw'};
    if(!defined($reserved_bw)){
        $reserved_bw = 0;
    }

    my $nodes = $args{'nodes'};
    my $try_avoid = $args{'used_links'};

    my $db = $self->get_database();
    my $g = Graph::Undirected->new;

    #now the acutal implementation, step0 sanity
    if(scalar(@$nodes) < 2){
        $self->_set_error("Not enough nodes specified in find path: " . join(",",@$nodes));
        warn "Not enough nodes specified in the path\n";
        return undef;
    }

    #step1 (get nodes);
    my @tmp = @{$db->get_current_nodes()};
    

    my @db_nodes;
    foreach my $tmp_node (@tmp){
        push(@db_nodes, $tmp_node->{'name'});
    }

    $self->{'logger'}->debug("db_nodes=" . join(",",@db_nodes));

    #Sanity check2 make sure the nodes are a subset of the nodes on the db
    my $db_node_set    = Set::Scalar->new(@db_nodes);
    my $input_node_set = Set::Scalar->new(@$nodes);

    if(not $input_node_set <= $db_node_set){
        warn "Bad Inputs!\n";
        $self->_set_error("Bad inputs: " . join(",",@$nodes));
        return undef;
    }

    #now put the nodes into the graph
    foreach my $vertex (@db_nodes){
        $g->add_vertex($vertex);
    }

    #now put the edges in the graph
    #I am assuming there are NO repeated links between cities right now!
    my $links = $db->get_edge_links($reserved_bw);
    $self->{'logger'}->debug("edge links: " . Dumper($links));
    my %edge;
    my $used_link_set = Set::Scalar->new(@$try_avoid);

    #--- determine the max weight
    #used as a baseline to start the primary path weights at
    #when trying to determine the backup bath.
    my @weights;
    my $max_weight=0;
    foreach my $link (@$links){ 
        push(@weights, $link->{'metric'});
        $max_weight += $link->{'metric'};
    }
    
    foreach my $link (@$links){
        #add every link as an edge in our graph
        my $current_reserved_bandwidth = $link->{'reserved_bw_mbps'};

        #--- determine how much capacity will be left on this link after our requested circuit runs through it
        my $capacity_left = $link->{'link_capacity'} * 1.0 - $current_reserved_bandwidth - $reserved_bw;
        #--- if the remaining capacity is less than zero we can't use this link so don't add it to the graph
        $self->{'logger'}->debug("Capacity left on link " . $link->{'name'} . ": " . $capacity_left);
        next if($capacity_left < 0);

        my $edge_weight = $link->{'metric'};
        #if the link is in our used list add the maximum weight
        #to its weight to ensure it's chose only as a last resort
        if($used_link_set->has($link->{'name'})){
            #add one to the max weight in case the max weight is the same as this edges' weight
            $self->{'logger'}->debug("Link " . $link->{'name'} . " was already used.. adding weight");
            $edge_weight = $edge_weight + ($max_weight + 1);
        }

        $self->{'logger'}->debug("Link weight: " . $edge_weight);

        my $circuits = $db->get_circuits_on_link(link_id => $link->{'link_id'});

        #it could be the case we have multiple links between the same 2 nodes
        #in that case we want to put the lowest path metric and if this is choosen we will
        #calculate which of the links is to be used
        $self->{'logger'}->debug("A " . $link->{'node_a_name'} . " to " . $link->{'node_b_name'});

        if(defined($edge{$link->{'node_a_name'}}{$link->{'node_b_name'}}) ||
           defined($edge{$link->{'node_b_name'}}{$link->{'node_a_name'}})){

            $self->{'logger'}->debug("adding a link to: " . $link->{'node_a_name'} . " to " . $link->{'node_b_name'});

            push(@{$edge{$link->{'node_a_name'}}{$link->{'node_b_name'}}},{name => $link->{'name'},
                                                                           weight => $edge_weight,
                                                                           circuits => $circuits });
            push(@{$edge{$link->{'node_b_name'}}{$link->{'node_a_name'}}},{name => $link->{'name'},
                                                                           weight => $edge_weight,
                                                                           circuits => $circuits });

            my $weight = $g->get_edge_attributes($link->{'node_a_name'},$link->{'node_b_name'},"weight");

            if($edge_weight < $weight){
                $g->set_edge_attribute($link->{'node_a_name'},$link->{'node_b_name'},"weight",$edge_weight);
            }
        
            #don't try and add it to the graph
            next;
        }

        $g->add_edge($link->{'node_a_name'},$link->{'node_b_name'});

        if (not defined $reserved_bw){
            $reserved_bw=0;
        }

        $g->set_edge_attribute($link->{'node_a_name'},$link->{'node_b_name'},"weight",$edge_weight);
        $self->{'logger'}->debug("Edge: " . $link->{'node_a_name'} . "<->" . $link->{'node_b_name'} . " = " . $edge_weight);

        push(@{$edge{$link->{'node_a_name'}}{$link->{'node_b_name'}}},{
            name => $link->{'name'},
            weight => $edge_weight,
            circuits => $circuits 
        });
        push(@{$edge{$link->{'node_b_name'}}{$link->{'node_a_name'}}},{
            name => $link->{'name'},
            weight => $edge_weight,
            circuits => $circuits
        });
    }

    warn Data::Dumper::Dumper($g);

    #run Dijkstra on our graph
    my @link_list = ();
    foreach my $node_a_name (@$nodes){
    foreach my $node_b_name (@$nodes){
        next if $node_a_name eq $node_b_name;
        #do the Shortest Path Calcualtion
        my @path = $g->SP_Dijkstra($node_a_name, $node_b_name);
        $self->{'logger'}->debug("Shortest path calc: for $node_a_name to $node_b_name " . Dumper(@path));
        if (!@path){
            warn "Unable to find path!\n";
            $self->_set_error("No Path found");
            return undef;
        }

        my $links_added = 0;
        for(my $i=0;$i<scalar(@path);$i++){
            my $links = $edge{$path[$i]}{$path[$i+1]};
            
            my $choosen_link;
            foreach my $link (@$links){
                $self->{'logger'}->debug("Link: " . $link->{'name'});
                if(!defined($choosen_link)){
                    $choosen_link = $link;
                    next;
                }
                $self->{'logger'}->debug(Data::Dumper::Dumper($link));

                $self->{'logger'}->debug("Comparing " . ($link->{'weight'} + scalar($link->{'circuits'})) . " to " . ($choosen_link->{'weight'} + scalar($choosen_link->{'circuits'}))); 
                if(($link->{'weight'} + $#{$link->{'circuits'}}) < ($choosen_link->{'weight'} + $#{$choosen_link->{'circuits'}})){
                    $choosen_link = $link;
                }
                
            }
            if(!defined($choosen_link)){
                next;
            }
            push(@link_list,$choosen_link->{'name'});
            $self->{'logger'}->debug("Adding link name: " . $choosen_link->{'name'});
            $links_added = 1;
        }
        last if($links_added);
    }}
    
    $self->{'logger'}->debug("link_list=".join(",",@link_list));

    @selected_links=uniq(@link_list);

    $self->{'logger'}->debug("selected_links=".join(",",@selected_links));

    warn "SELECTED LINKS" . Data::Dumper::Dumper(@selected_links);
    return \@selected_links;

}

=head2 is_path_up

=cut

sub is_path_up{
    my $self = shift;
    my %args = @_;

    my $path = $args{'path_id'};

    if(!defined($path)){

	return ;
    }

    my %down_links;
    my %unknown_links;


    if(defined($args{'link_status'})){
	my $link_status = $args{'link_status'};
	foreach my $key (keys (%{$link_status})){
	    if($link_status->{$key} == OESS_LINK_DOWN){
		$down_links{$key} = 1;
	    }elsif($link_status->{$key} == OESS_LINK_UNKNOWN){
		$unknown_links{$key} = 1;
	    }
	}
    }else{

	my $links = $self->{'db'}->get_current_links();


	foreach my $link (@$links){


            if( $link->{'status'} eq 'down'){
                $down_links{$link->{'name'}} = $link;
            }elsif($link->{'status'} eq 'unknown'){
                $unknown_links{$link->{'name'}} = $link;
            }
            
	}
        
    }

    my $path_links = $args{'links'};
    if(!defined($path_links)){
        $path_links = $self->{'db'}->get_path_links( path_id => $path );
    }

    foreach my $link (@$path_links){

        if( $down_links{ $link->{'name'} } ){
            return 0;
        }elsif($unknown_links{$link->{'name'}}){
            return 2;
        }
    }

    return 1;
}


1;
