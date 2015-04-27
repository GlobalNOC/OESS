#!/usr/bin/perl
#
##----- NDDI OESS traceroute.cgi
##-----
##----- Provides a WebAPI to allow for initiating and getting the results of a circuit traceroutes
##
##-------------------------------------------------------------------------
##
##
## Copyright 2015 Trustees of Indiana University
##
##   Licensed under the Apache License, Version 2.0 (the "License");
##   you may not use this file except in compliance with the License.
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

use strict;
use warnings;

use CGI;
use JSON;
use Switch;
#use Net::DBus::Exporter qw(org.nddi.fwdctl);
use Data::Dumper;

use OESS::Database;
use OESS::Topology;
use OESS::Circuit;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;

my $db = new OESS::Database();

my $cgi = new CGI;

$| = 1;

sub main {

    if ( !$db ) {
        send_json( { "error" => "Unable to connect to database." } );
        exit(1);
    }

    my $action = $cgi->param('action');
    print STDERR "action " . $action;
    my $output;

    switch ($action) {

        case "init_circuit_traceroute" {
                                  $output = &init_circuit_traceroute();
                                 }
        case "get_circuit_traceroute" {
            $output = &get_circuit_traceroute();
        }


    }

    send_json($output);

}

sub init_circuit_traceroute {

    my $results;

    $results->{'results'} = [];


    my $output;
    
    #workgroup_id, circuit_id, source_interface, are all required;
    my $workgroup_id = $cgi->param('workgroup_id');
    my $circuit_id  = $cgi->param('circuit_id');
    my $source_node = $cgi->param('node');
    my $source_intf = $cgi->param('interface');
   
    my $interface_id = $db->get_interface_id_by_names (node => $source_node,
                                                       interface => $source_intf
        );


    my $source_interface = $interface_id;

    if (!defined ($workgroup_id)) {
        return {error => "workgroup_id is required" }
    }
    if (!defined ($circuit_id)) {
        return {error => "circuit_id is required" }
    }
    
   if (!defined ($source_interface)) {
        return {error => "Could not find source interface" }
    }

    my $ckt = OESS::Circuit->new( circuit_id => $circuit_id, db => $db);
    warn Data::Dumper::Dumper($ckt);
    if (!$ckt || $ckt->{'details'}->{'state'} ne 'active'){
        return { error => "User and workgroup do not have permission to traceroute this circuit" }
    }

    my $endpoints = $db->get_circuit_endpoints(circuit_id => $circuit_id);
    warn Dumper ($endpoints);
    if (!$endpoints){

    }
    my $source_interface_is_endpoint=0;
    
    foreach my $endpoint (@$endpoints){
        if ($endpoint->{'interface'} eq $source_intf &&$endpoint->{'node'} eq $source_node ){
            $source_interface_is_endpoint =1;
            last;
        }
    }
    
    if ( !$source_interface_is_endpoint ){
        return {error => "interface $source_interface is not an endpoint of circuit $circuit_id"}
    }
    
    my $bus = Net::DBus->system;
    my $traceroute_svc;
    my $traceroute_client;
    eval {
        $traceroute_svc    = $bus->get_service("org.nddi.traceroute");
        $traceroute_client = $traceroute_svc->get_object("/controller1");
    };
    warn $@ if $@;
    if (!$traceroute_svc|| !$traceroute_client ){
        return {error => 'unable to talk to traceroute service'};
    }
    my $workgroup = $db->get_workgroup_by_id( workgroup_id => $workgroup_id );

    if(!defined($workgroup)){
    return {error => 'unable to find workgroup $workgroup_id'};
    }
    elsif($workgroup->{'status'} eq 'decom'){
    return {error => 'The selected workgroup is decomissioned and unable to provision'};
    }

    my $user = $db->get_user_by_id(user_id => $db->get_user_id_by_auth_name( auth_name => $ENV{'REMOTE_USER'}))->[0];
         
    my $can_edit = $db->can_modify_circuit(
                                             circuit_id   => $circuit_id,
                                             username     => $ENV{'REMOTE_USER'},
                                             workgroup_id => $workgroup_id
                                            );


    if ( $can_edit < 1 ) {
        $results->{'error'} =
            "User and workgroup do not have permission to traceroute this circuit";
        return $results;
    }

        
    my $result = $traceroute_client->init_circuit_trace($circuit_id,$source_interface);
    
    if ($result){
        $results->{'results'} = [{success => '1'}];
        
    }


    return $results;
}

sub get_circuit_traceroute {
    
    my $results;

    $results->{'results'} = [];


    my $output;

    my $workgroup_id = $cgi->param('workgroup_id');
    my $circuit_id  = $cgi->param('circuit_id');
    
    my $bus = Net::DBus->system;
    my $traceroute_svc;
    my $traceroute_client;
    eval {
        $traceroute_svc    = $bus->get_service("org.nddi.traceroute");
        $traceroute_client = $traceroute_svc->get_object("/controller1");
    };
    if ($@){
        if(!defined($traceroute_client)){
            return {error => "unable to fetch traceroute data" }
        }
    }
    my $workgroup = $db->get_workgroup_by_id( workgroup_id => $workgroup_id );

    if(!defined($workgroup)){
    return {error => "unable to find workgroup $workgroup_id"};
    }
    elsif($workgroup->{'status'} eq 'decom'){
    return {error => 'The selected workgroup is decomissioned and unable to provision'};
    }

    my $user = $db->get_user_by_id(user_id => $db->get_user_id_by_auth_name( auth_name => $ENV{'REMOTE_USER'}))->[0];
         
    my $can_edit = $db->can_modify_circuit(
                                             circuit_id   => $circuit_id,
                                             username     => $ENV{'REMOTE_USER'},
                                             workgroup_id => $workgroup_id
                                            );


    if ( $can_edit < 1 ) {
        $results->{'error'} =
            "No traceroute data found for this circuit";
        return $results;
    }

    #dbus is fighting me, this is suboptimal, but dbus does not like the signature changing.    
    my $result = $traceroute_client->get_traceroute_transactions({});
    
    if ($result && $result->{$circuit_id}){
        my $node_dpid_hash = $db->get_node_dpid_hash;
        my $dpid_node_hash = {};
        #invert the hash, because we can
        foreach my $node_name (keys %$node_dpid_hash){
            $dpid_node_hash->{ $node_dpid_hash->{$node_name} } = $node_name;
        }
        $result = $result->{$circuit_id};
        delete $result->{source_endpoint};
        my @tmp_nodes = split(",",$result->{nodes_traversed});
        my @tmp_interfaces = split(",",$result->{'interfaces_traversed'});
        # replace dpid with node name
        foreach my $dpid (@tmp_nodes){
            $dpid = $dpid_node_hash->{$dpid};
        }
        
        $result->{nodes_traversed} = \@tmp_nodes;
        $result->{interfaces_traversed} = \@tmp_interfaces;
        push (@{$results->{results}}, $result);
    }
    if (!defined($result)){
        $results->{'error'} = "No traceroute data found for this circuit";
    }


    return $results;
}


sub send_json {
    my $output = shift;

    print "Content-type: text/plain\n\n" . encode_json($output);
}

main();
