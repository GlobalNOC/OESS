#!/usr/bin/perl
#------ NDDI OESS Measurement Module
##-----
##----- $HeadURL: svn+ssh://svn.grnoc.iu.edu/grnoc/oe-ss/perl-lib/OESS-Measurement/trunk/lib/OESS/Measurement.pm $
##----- $Id$
##----- $Date$
##----- $LastChangedBy$
##-----
##----- Provides object oriented methods to interact with the DBus test
##----------------------------------------------------------------------
##
## Copyright 2011 Trustees of Indiana University
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


package OESS::Measurement;

use strict;
use warnings;

use GRNOC::Log;
use RRDs;
use XML::Simple;
use OESS::Database;
use Data::Dumper;
use Exporter qw(import);
use OESS::Circuit;
use POSIX qw(strftime);


use constant BUILDING_FILE => -1;

our @EXPORT_OK = qw(BUILDING_FILE);

our $ENABLE_DEVEL=0;

=head2 new

=cut
sub new {
    my $that = shift;
    my $class = ref($that) || $that;
    my %params = @_;

    my $db = OESS::Database->new();
        
    if(!defined($db)){
        return undef;
    }

    my %args = (
        @_
    );
    my $self = \%args;
    bless $self,$class;

    Log::Log4perl::init('/etc/oess/logging.conf');
    $self->{'logger'} = Log::Log4perl->get_logger("OESS.Measurement");
    $self->{'db'} = $db;
    $self->{'config'} = $db->{'configuration'};
    warn Dumper($self);
    return $self;

}

sub _set_error {
    my $self = shift;
    my $error = shift;

    $self->{'error'} = $error;
}

=head2 get_error

=cut

sub get_error {
    my $self = shift;

    my $err = $self->{'error'};
    $self->{'error'} = undef;
    return $err;
}

=head2 get_of_circuit_data

=cut

sub get_of_circuit_data {
    my $self = shift;
    my %params = @_;

    my $circuit_id = $params{'circuit_id'};
    my $start      = $params{'start_time'};
    my $end        = $params{'end_time'};
    my $node       = $params{'node'};
    my $interface  = $params{'interface'};
    
    my $db = OESS::Database->new();

    if(!defined $circuit_id){
        $self->_set_error("circuit_id is required");
        return undef;
    }

    #get the path that is currently active for issue 7410
    my $ckt        = OESS::Circuit->new(circuit_id => $circuit_id, db => $db);
    my $active_path = $ckt->get_active_path();

    if(!defined $start){
        $self->_set_error("start_time is required and should be in epoch time");
        return undef;
    }

    # assume we mean "start to now"
    if(!defined $end){
        $end = time;
    }    

    #issue 7410 graphs not able to determine backup vs primary path data. 

    my $inital_node_dpid_hash = $db->get_node_dpid_hash();
    
    my %repaired_node_dpid_hash = reverse %{$inital_node_dpid_hash};
    my %int_names;
    foreach my $nodeName (keys (%{$inital_node_dpid_hash})){

        my $int_name =  $db->get_node_interfaces('node'=> $nodeName, show_down => 1, show_trunk =>1);
        
        foreach my $int (@{$int_name}){
            $int_names{$nodeName}->{$int->{'port_number'}} = $int->{'name'};
        }
    }

    $self->{'logger'}->debug("Gathered all interface names");
  
    my @interfaces;

    my $flows = $ckt->get_flows(path => $active_path);
    my %endpoint;
    foreach my $flow (@{$flows}){
	my $match = $flow->get_match();

	push(@interfaces, {
            node    => $flow->get_dpid(),
            int     => $int_names{$repaired_node_dpid_hash{$flow->get_dpid()}}{$match->{'in_port'}},
            port_no => $match->{'in_port'},
            tag     => $match->{'dl_vlan'}
	});
    }

    #$self->{'logger'}->debug("Gathered all flows: " . Dumper(@interfaces));

    #ok we pushed all interfaces into a big array
    #now pull out all the ones on our selected node... and if its the selected selected it
    my $selected;
    my @interfaces_on_node;

    my $ep = $ckt->get_endpoints()->[0];

    warn Dumper($ep);

    if(!defined($node)){
        $node = $inital_node_dpid_hash->{$ep->{'node'}};
    }else{
        $node = $inital_node_dpid_hash->{$node};
    }

    if(!defined($interface)){
	$interface = $ep->{'interface'};
    }

    foreach my $int (@interfaces){
        if ($int->{'node'} eq $node) {
            if( ( !defined($interface) && !defined($selected) ) || $int->{'int'} eq $interface){
                $selected = $int;
            }else{
                push(@interfaces_on_node, $int);
            }
        }
    }

    $self->{'logger'}->warn("Interfaces: " . Dumper(@interfaces_on_node));
    $self->{'logger'}->warn("Selected: "   . Dumper($selected));

    #now we have selected an interface and have a list of all the other interfaces on that node
    #generate our data
    my $in = $self->tsds_of_query( port_no => $selected->{'port_no'},
                                   dpid => $selected->{'node'},
                                   tag => $selected->{'tag'},
                                   start => $start,
                                   end => $end);

    my $out_agg;
    foreach my $int (@interfaces_on_node){
        my $out = $self->tsds_of_query( port_no => $int->{'port_no'},
                                        dpid => $int->{'node'},
                                        tag => $int->{'tag'},
                                        start => $start,
                                        end => $end);
        if(!defined($out_agg)){
            $out_agg = $out->{'results'};
        } else {
	    aggregate_data($out_agg->[0]->{'aggregate(values.bps, 30, average)'}, $out->{'results'}->[0]->{'aggregate(values.bps, 30, average)'});
        }
    }

#    $self->{'logger'}->debug(Dumper($in));
#    $self->{'logger'}->debug(Dumper($out_agg));

    my $interface_names = [];
    foreach my $int (@interfaces_on_node) {
	push(@{$interface_names}, $int->{'int'});
    }

    push(@{$interface_names}, $selected->{'int'});

    my $result = { 'interfaces' => $interface_names,
                   'interface'  => $selected->{'int'},
                   'node'       => $repaired_node_dpid_hash{$node},
                   'results'    => [
		       {
			   name => "Input (Bps)",
			   data => $in->{'results'}->[0]->{'aggregate(values.bps, 30, average)'}
		       },
		       {
			   name => "Output (Bps)",
			   data => $out_agg->[0]->{'aggregate(values.bps, 30, average)'}
		       }
		   ]
	       };
    return $result;
}

=head2 tsds_of_query

=cut

sub tsds_of_query{
    my $self = shift;
    my %params = @_;

    my $start = $params{'start'};
    my $end = $params{'end'};
    my $port_no = $params{'port_no'};
    my $dpid = $params{'dpid'};
    my $tag = $params{'tag'};

    $self->{'logger'}->debug("Calling tsds_of_query");
    $self->{'logger'}->debug($dpid);
    $self->{'logger'}->debug($port_no);
    $self->{'logger'}->debug($tag);

    my $query = "get port, dpid, vlan, aggregate(values.bps, 30, average) between ($start, $end) by port, dpid, vlan from oess_of_stats where (port = \"$port_no\" and dpid = \"$dpid\" and vlan = \"$tag\")";

    my $req = GRNOC::WebService::Client->new(
	url    => $self->{'config'}->{'tsds'}->{'url'} . "/query.cgi",
	uid    => $self->{'config'}->{'tsds'}->{'username'},
	passwd => $self->{'config'}->{'tsds'}->{'password'},
	debug => 1,
    );
    my $res = $req->query(query => $query);
    if (!defined $res) {
	$self->{'logger'}->error($res->get_error());
    }

    $self->{'logger'}->debug("tsds_of_query: " . Dumper($res));

    return $res;

}

=head2 aggregate_data

=cut

sub aggregate_data{
    my $agg = shift;
    my $new_data = shift;

    if(!defined($agg)){
        $agg = $new_data;
	return $agg;
    }

    #theoretically they are the same step and same times so this should just work
    #if it doesn't we need much more complex logic

    for(my $i=0;$i<=$#{$agg};$i++){
        warn Dumper($agg->[$i]);
	if($agg->[$i]->[0] == $new_data->[$i]->[0]){
            $agg->[$i]->[1] += $new_data->[$i]->[1];
        }
    }
    return $agg;
}


=head2 get_mpls_circuit_data

=cut
sub get_mpls_circuit_data {
    my $self = shift;
    my %params = @_;

    my $circuit_id = $params{'circuit_id'};
    my $start_time = $params{'start_time'};
    my $end_time   = $params{'end_time'};
    my $node       = $params{'node'};
    my $interface  = $params{'interface'};
    my $db = OESS::Database->new();
    my $tag;

    my @interfaces;

    if(!defined $circuit_id){
        $self->_set_error("circuit_id is required");
        return undef;
    }
    if(!defined $start_time){
        $self->_set_error("start_time is required and should be in epoch time");
        return undef;
    }
    if(!defined $end_time){
        # assume we mean "start to now"
        $end_time = time;
    }

    my $ckt = OESS::Circuit->new(circuit_id => $circuit_id, db => $db);
    
    if(!defined($node)){
        $node = $ckt->get_endpoints()->[0]->{'node'};
    }

    my $a; # First endpoint on specified interface
    foreach my $e (@{$ckt->get_endpoints()}) {
        if($e->{'node'} eq $node){
            push(@interfaces, $e->{'interface'});
        }
    }

    foreach my $e (@{$ckt->get_endpoints()}) {
	if ($e->{'node'} eq $node && !defined $interface) {
	    $interface = $e->{'interface'};
	    $tag = $e->{'tag'};
	    $a = $e;
	    last;
	}
        if ($e->{'node'} eq $node && $e->{'interface'} eq $interface) {
	    $tag = $e->{'tag'};
            $a = $e;
            last;
        }
    }



    

    my $results = $self->tsds_interface_query( node => $node,
                                               interface => $interface . "." . $tag,
                                               start => $start_time,
                                               end => $end_time );

    warn Dumper($results);

    my $result = { 'interfaces' => \@interfaces,
		   'interface'  => $interface,
		   'node'       => $node,
		   'results'    => [ {name => "Input (Bps)", data => $results->{'results'}->[0]->{'aggregate(values.input, 30, average)'}}, {name => "Output (Bps)", data => $results->{'results'}->[0]->{'aggregate(values.output, 30, average)'}} ]
    };

    return $result;
}


sub tsds_interface_query{
    my $self = shift;
    my %args = @_;
    
    my $node = $args{'node'};
    my $interface = $args{'interface'};
    my $start = $args{'start'};
    my $end = $args{'end'};

    my $query = "get intf, node, aggregate(values.input, 30, average), aggregate(values.output, 30, average) between ($start, $end) by intf, node from interface  where (intf=\"$interface\" and node=\"$node\")";
    
    my $req = GRNOC::WebService::Client->new(
        url    => $self->{'config'}->{'tsds'}->{'url'} . "/query.cgi",
        uid    => $self->{'config'}->{'tsds'}->{'username'},
        passwd => $self->{'config'}->{'tsds'}->{'password'},
        debug => 1,
	);

    my $res = $req->query(query => $query);

    return $res;
}

=head2 find_int_on_path_using_node

=cut

sub find_int_on_path_using_node{
    my $self = shift;
    my %params = @_;

    if(!defined($params{'links'})){
	return;
    }

    if(!defined($params{'node'})){
	return;
    }


    my $interface;

    foreach my $link (@{$params{'links'}}){
	# this will tell us one of the ports which should be good enough
	if ($link->{'node_a'} eq $params{'node'}){
	    if (!defined $interface || $interface eq $link->{'interface_a'}){
		$interface = {port_no    => $link->{'port_no_a'},
			      node       => $params{'node'},
			      interface  => $link->{'interface_a'},
		};
		last;
	    }
	}
	if ($link->{'node_z'} eq $params{'node'}){
	    if (!defined $interface || $interface eq $link->{'interface_z'}){
		$interface = {port_no    => $link->{'port_no_z'},
			      node       => $params{'node'},
			      interface  => $link->{'interface_z'},
		};
		last;
	    }
	}
    }

    return $interface;

}


1;
