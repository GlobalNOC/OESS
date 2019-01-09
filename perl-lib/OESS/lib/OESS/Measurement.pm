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

    my $db = $params{'db'};

    if(!defined($db)){
        $db = OESS::Database->new();
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
    my $ckt = OESS::Circuit->new(circuit_id => $circuit_id, db => $db);

    if(!defined($ckt)){
        warn "Unable to find circuit\n";
        $self->_set_error("unable to find circuit: " . $circuit_id . " in th OESS DB");
        return undef;
    }


    if(!defined $start){
        $self->_set_error("start_time is required and should be in epoch time");
        return undef;
    }

    # assume we mean "start to now"
    if(!defined $end){
        $end = time;
    }    

    #issue 7410 graphs not able to determine backup vs primary path data. 

    my %node_to_dpid = %{$db->get_node_dpid_hash()}; # map of node name to node DPID
    my %int_names; # map of (DPID, port #) to interface name

    foreach my $nodeName (keys %node_to_dpid){

        my $int_name =  $db->get_node_interfaces(node => $nodeName, show_down => 1, show_trunk =>1, type => 'openflow');
        
        foreach my $int (@{$int_name}){
            $int_names{$node_to_dpid{$nodeName}}->{$int->{'port_number'}} = $int->{'name'};
        }
    }

    $self->{'logger'}->debug("Gathered all interface names");
  
    my @interfaces;

    my $active_path = $ckt->get_active_path();
    my $flows = $ckt->get_flows(path => $active_path);

    foreach my $flow (@{$flows}){
	my $match = $flow->get_match();

	push(@interfaces, {
            dpid    => $flow->get_dpid(),
            int     => $int_names{$flow->get_dpid()}{$match->{'in_port'}},
            port_no => $match->{'in_port'},
            tag     => $match->{'dl_vlan'}
	});
    }

    #$self->{'logger'}->debug("Gathered all flows: " . Dumper(@interfaces));

    #ok we pushed all interfaces into a big array
    #now pull out all the ones on our selected node... and if its the selected selected it
    my $selected;
    my @other_interfaces_on_node;

    # if we weren't given a specific node, or it isn't involved in the current path, use one of the endpoint interfaces
    if (!defined($node) || !defined($node_to_dpid{$node})
                        || (scalar(grep { $_->{'dpid'} eq $node_to_dpid{$node} } @interfaces) == 0)){
        my $ep = $ckt->get_endpoints()->[0];
        $node = $ep->{'node'};
        $interface = $ep->{'interface'};
    }

    my $dpid = $node_to_dpid{$node};

    foreach my $int (@interfaces){
        if ($int->{'dpid'} eq $dpid) {
            if(!defined($selected) && defined($interface) && ($int->{'int'} eq $interface)){
                $selected = $int;
            }else{
                push(@other_interfaces_on_node, $int);
            }
        }
    }

    # If the asked-for interface does not exist on the node in question
    # (or no specific interface was asked for), just select one!
    $selected = shift @other_interfaces_on_node if !defined($selected);

    #$self->{'logger'}->info("Interfaces: " . Dumper(@other_interfaces_on_node));
    #$self->{'logger'}->info("Selected: "   . Dumper($selected));

    #now we have selected an interface and have a list of all the other interfaces on that node
    #generate our data
    my $in = $self->_tsds_of_query( port_no => $selected->{'port_no'},
                                    dpid    => $selected->{'dpid'},
                                    tag     => $selected->{'tag'},
                                    start   => $start,
                                    end     => $end);

    my $out_agg;
    foreach my $int (@other_interfaces_on_node){
        my $out = $self->_tsds_of_query( port_no => $int->{'port_no'},
                                         dpid    => $int->{'dpid'},
                                         tag     => $int->{'tag'},
                                         start   => $start,
                                         end     => $end);
        if(!defined($out_agg)){
            $out_agg = $out->{'results'};
        } else {
	    aggregate_data($out_agg->[0]->{'aggregate(values.bps, 30, average)'}, $out->{'results'}->[0]->{'aggregate(values.bps, 30, average)'});
        }
    }

#    $self->{'logger'}->debug(Dumper($in));
#    $self->{'logger'}->debug(Dumper($out_agg));

    my @interface_names = ();
    foreach my $int (@other_interfaces_on_node) {
	push(@interface_names, $int->{'int'});
    }

    push(@interface_names, $selected->{'int'});
    @interface_names = sort @interface_names;

    my $result = { 'interfaces' => \@interface_names,
                   'interface'  => $selected->{'int'},
                   'node'       => $node,
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

=head2 _is_tsds_config_ok

Sees if all the TSDS-related config is present

=cut

sub _is_tsds_config_ok{
    my $self  = shift;
    my $tconf = $self->{'config'}->{'tsds'};
    return defined($tconf) && defined($tconf->{'url'}) && defined($tconf->{'username'}) && defined($tconf->{'password'});
}

=head2 tsds_of_query

=cut

sub _tsds_of_query{
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

    $self->{'logger'}->error('TSDS config not fully set up!') if !$self->_is_tsds_config_ok();
    my $req = GRNOC::WebService::Client->new(
	url    => $self->{'config'}->{'tsds'}->{'url'} . "/query.cgi",
	uid    => $self->{'config'}->{'tsds'}->{'username'},
	passwd => $self->{'config'}->{'tsds'}->{'password'},
	realm  => $self->{'config'}->{'tsds'}->{'realm'},
	debug => 0,
    );
    my $res = $req->query(query => $query);
    if (!defined $res) {
	$self->{'logger'}->error($req->get_error());
    }

    #$self->{'logger'}->debug("tsds_of_query: " . Dumper($res));

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
        #warn Dumper($agg->[$i]);
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



    

    my $results = $self->_tsds_interface_query( node => $node,
                                               interface => $interface . "." . $tag,
                                               start => $start_time,
                                               end => $end_time );

    #warn Dumper($results);

    my $result = { 'interfaces' => \@interfaces,
		   'interface'  => $interface,
		   'node'       => $node,
		   'results'    => [ {name => "Input (Bps)", data => $results->{'results'}->[0]->{'aggregate(values.input, 30, average)'}}, {name => "Output (Bps)", data => $results->{'results'}->[0]->{'aggregate(values.output, 30, average)'}} ]
    };

    return $result;
}


sub _tsds_interface_query{
    my $self = shift;
    my %args = @_;
    
    my $node = $args{'node'};
    my $interface = $args{'interface'};
    my $start = $args{'start'};
    my $end = $args{'end'};

    my $query = "get intf, node, aggregate(values.input, 30, average), aggregate(values.output, 30, average) between ($start, $end) by intf, node from interface  where (intf=\"$interface\" and node=\"$node\")";

    $self->{'logger'}->error('TSDS config not fully set up!') if !$self->_is_tsds_config_ok();
    my $req = GRNOC::WebService::Client->new(
        url    => $self->{'config'}->{'tsds'}->{'url'} . "/query.cgi",
        uid    => $self->{'config'}->{'tsds'}->{'username'},
        passwd => $self->{'config'}->{'tsds'}->{'password'},
	realm  => $self->{'config'}->{'tsds'}->{'realm'},
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
