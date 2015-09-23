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

use Log::Log4perl;
use RRDs;
use XML::Simple;
use OESS::Database;
use Data::Dumper;
use Exporter qw(import);
use OESS::Circuit;


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
    
    if (!defined $db){
        $db = OESS::Database->new();
    }
    
    if(!defined($db)){
        return undef;
    }

    my %args = (
        config => $db->get_snapp_config_location(),
        @_
    );
    my $self = \%args;
    bless $self,$class;

    $self->{'db'} = $db;
    my $config_filename = $args{'config'};
    my $config = XML::Simple::XMLin($config_filename);
    my $username = $config->{'db'}->{'username'};
    my $password = $config->{'db'}->{'password'};
    my $database = $config->{'db'}->{'name'};
    my $dbh = DBI->connect("DBI:mysql:$database", $username, $password);
    $self->{'dbh'} = $dbh;
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

=head2 get_circuit_data

=cut

sub get_circuit_data {
    my $self = shift;
    my %params = @_;

    my $circuit_id = $params{'circuit_id'};
    my $start      = $params{'start_time'};
    my $end        = $params{'end_time'};
    my $node       = $params{'node'};
    my $interface  = $params{'interface'};
    my $db         = $params{'db'};
    
    if (!defined($db)){
        $db = OESS::Database->new();
    }
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
    #find the base RRD dir
    my $rrd_dir;
    my $query = "select value from global where name = 'rrddir'";
    my $sth = $self->{'dbh'}->prepare($query);
    $sth->execute();
    if(my $row = $sth->fetchrow_hashref()){
        $rrd_dir = $row->{'value'};
    }
    my $circuit_details = $self->{'db'}->get_circuit_details(circuit_id => $circuit_id);
    my @interfaces;
    
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
    

    my $flows = $ckt->get_flows(path => $active_path);
    my %endpoint;
    foreach my $flow (@{$flows}){
	my $match = $flow->get_match();
	push(@interfaces,{
            node =>$repaired_node_dpid_hash{$flow->get_dpid()},
            int =>$int_names{$repaired_node_dpid_hash{$flow->get_dpid()}}{$match->{'in_port'}},
            port_no => $match->{'in_port'},
            tag => $match->{'dl_vlan'}});
    }


    #ok we pushed all interfaces into a big array
    #now pull out all the ones on our selected node... and if its the selected selected it
    my $selected;
    my @interfaces_on_node;

    if(!defined($node)){
        $node = $interfaces[0]->{'node'};
    }

    foreach my $int (@interfaces){
        if($int->{'node'} eq $node){
            if( ( !defined($interface) && !defined($selected) ) || $int->{'int'} eq $interface){
                $selected = $int;
            }else{
                push(@interfaces_on_node,$int);
            }
        }
    }

    #warn "Selected: " . Data::Dumper::Dumper($selected);
    
    #warn "Interfaces: " . Data::Dumper::Dumper(@interfaces_on_node);
    #now we have selected an interface and have a list of all the other interfaces on that node
    #generate our data
    return $self->get_data( interface => $selected, other_ints => \@interfaces_on_node, start_time => $start, end_time => $end);

}


=head2 get_data
  Params: circuit_id => circuit id of the circuit to find data for
          start_time => the start_time to get data for
          end_time => the end time to get data for (optional, if not defined is set to NOW)

  return RRD Data

=cut

sub get_data {
    my $self = shift;
    my %params = @_;
    my $selected = $params{'interface'};
    my $other_ints = $params{'other_ints'};
    my $start      = $params{'start_time'};
    my $end        = $params{'end_time'};
    if(!defined $start){
        $self->_set_error("start_time is required and should be in epoch time");
	return undef;
    }

    # assume we mean "start to now"
    if(!defined $end){
        $end = time;
    }
    #find the base RRD dir
    my $rrd_dir;
    my $query = "select value from global where name = 'rrddir'";
    my $sth = $self->{'dbh'}->prepare($query);
    $sth->execute();
    if(my $row = $sth->fetchrow_hashref()){
        $rrd_dir = $row->{'value'};
    }
    my $node = $self->{'db'}->get_node_by_name( name => $selected->{'node'});
    #get all the host details for the interfaces host
    my $host = $self->get_host_by_external_id($node->{'node_id'});
    
    #find the collections RRD file in SNAPP
    #warn "Looking for collection\n";
    
    my $collection = $self->_find_rrd_file_by_host_int_and_vlan($host->{'host_id'},$selected->{'port_no'},$selected->{'tag'});
    if(defined($collection)){
        #warn "Collection Found!!\n";
	my $rrd_file = $rrd_dir . $collection->{'rrdfile'};
        my $data= [];
        my $input  = $self->get_rrd_file_data( file => $rrd_file, start_time => $start, end_time => $end) || [];
        push(@{$data},{name => 'Input (Bps)',
                       data => $input});
        my $output_agg;
        foreach my $other_int (@$other_ints){
            my $other_collection = $self->_find_rrd_file_by_host_int_and_vlan($host->{'host_id'},$other_int->{'port_no'},$other_int->{'tag'});
            if(defined($other_collection)){
                my $other_rrd_file = $rrd_dir . $other_collection->{'rrdfile'};
                my $output = $self->get_rrd_file_data( file => $other_rrd_file, start_time => $start, end_time => $end);
                $output_agg = aggregate_data($output_agg,$output) || [];
            }
        }
        
        push(@{$data},{name => 'Output (Bps)',
                       data => $output_agg});



        my @all_interfaces;
	foreach my $int (@$other_ints){
	    push(@all_interfaces, $int->{'int'});
	}
        
        push(@all_interfaces, $selected->{'int'});
	
	return {"node"       => $selected->{'node'},
		"interface"  => $selected->{'int'},
		"data"       => $data,
		"interfaces" => \@all_interfaces
	};
    }else{
	#unable to find RRD file
	$self->_set_error("Unable to find RRD/Collection");
	return BUILDING_FILE;#[{name => 'Creating RRD', data => [[time(), undef]]}];
    }
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
        if($agg->[$i]->[0] == $new_data->[$i]->[0]){
            $agg->[$i]->[1] += $new_data->[$i]->[1];
        }
    }
    return $agg;
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

sub _find_rrd_file_by_host_and_int{
    my $self = shift;
    my $host_id = shift;
    my $int_name = shift;
    my $query = "select * from collection where host_id = ? and premap_oid_suffix = ?";
    my $sth = $self->{'dbh'}->prepare($query);
    $sth->execute($host_id,"Ethernet" . $int_name);
    if(my $row = $sth->fetchrow_hashref()){
    return $row;
    }else{
	$self->_set_error("No Collection found with host_id $host_id and interface name $int_name\n");
	return undef;
    }
}

sub _find_rrd_file_by_host_int_and_vlan{
    my $self = shift;
    my $host_id = shift;
    my $port = shift;
    my $vlan = shift;
    # openflow treats untagged as 0xFFFF so that's
    # what we'll need to look for
    if ($vlan eq -1){
        $vlan = 65535;
    }

    my $query = "select * from collection where host_id = ? and premap_oid_suffix = ?";
    my $sth = $self->{'dbh'}->prepare($query);
    $sth->execute($host_id,$port . "-" . $vlan);
    if(my $row = $sth->fetchrow_hashref()){
	return $row;
    }else{
    $self->_set_error("No Collection found for host host_id with interface and vlan $port - $vlan");
	return undef;
    }
}

=head2 get_host_by_external_id

    find a host based on the external_id (ie... node_id)

=cut



sub get_host_by_external_id{
    my $self = shift;
    my $id = shift;
    my $query = "select * from host where host.external_id = ?";
    my $sth = $self->{'dbh'}->prepare($query);
    $sth->execute($id);
    if(my $row = $sth->fetchrow_hashref()){
        return $row;
    }else{
	$self->_set_error("No host found with external_id $id");
	return undef;
    }
}



=head2 get_rrd_file_data

    Params: file => the rrd file to pull data from
            start_time => the start time (epoch or RRD style (-5min))
            end_time => (optional) the end time to query data for (epoch or RRD style NOW) defaults to NOW if not specified

    process the data into a format for the FLOT graphs to use, also buckets data so that javascript doesn't freak out with too much data

=cut

sub get_rrd_file_data {
    my $self = shift;
    my %params = @_;

    if(!defined($params{'file'})){
	$self->_set_error("No file specified");
	return undef;
    }

    if(!defined($params{'start_time'})){
	$self->_set_error("No Start time specified");
	return undef;
    }

    if(!defined($params{'end_time'})){
	$params{'end_time'} = "NOW";
    }

    if(!defined($params{'h_size'})){
	$params{'h_size'} = 300;
    }
    my ($start,$step,$names,$data) = RRDs::fetch($params{'file'},"AVERAGE","-s " . $params{'start_time'},"-e " . $params{'end_time'});
   
    if (! defined $data){
	 
        warn RRDs::error;
        return undef;
    }

    my @results;
    my $output;
    my $input;
    my @names = @$names;
    my @data = @$data;

    for(my $i=0;$i<$#names;$i++){

	if($names[$i] eq 'output'){
            next;
	}elsif($names[$i] eq 'input'){
	    $input = $i;
	}
    }
    my $time = $start;
    my @outputs;
    my @inputs;

    my $spacing = int(@$data / $params{'h_size'});
    $spacing = 1 if($spacing == 0);

    for(my $i=0;$i<$#data;$i+=$spacing){
	my ($bucket,$j);

	for($j = 0;$j<$spacing && $j+$i < @$data; $j++){
	    my $row = @$data[$i+$j];
	    my $divisor = ($j + $i == @$data - 1? $j+1 : $spacing);

	    if(defined(@$row[$input])){
		$bucket->{'input'} += @$row[$input] / $divisor;
	    }

	}

	if($spacing > 1){
	    my $timeStart = $start;
	    my $timeEnd = ($start + ($step*$spacing));
	    $bucket->{'time'} = ($timeStart + $timeEnd) / 2;
	}else{
	    $bucket->{'time'} = $start;
	}

	$start += ($step * $spacing);
	if(defined($bucket->{'input'})){
	    $bucket->{'input'} *= 8;
	}
	push(@inputs,[$bucket->{'time'}, $bucket->{'input'}]);
    }
    return \@inputs;
#    push(@results,{"name" => "Input (bps)",
#		   "data" => \@inputs});
#
#    return \@results;
}


1;
