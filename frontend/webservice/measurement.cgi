#!/usr/bin/perl -T
#
##----- NDDI OESS Measurement.cgi
##-----
##----- $HeadURL: svn+ssh://svn.grnoc.iu.edu/grnoc/oe-ss/frontend/trunk/webservice/measurement.cgi $
##----- $Id$
##----- $Date$
##----- $LastChangedBy$
##-----
##----- Provides Measurement data to the UI
##
##-------------------------------------------------------------------------
##
##
## Copyright 2011 Trustees of Indiana University
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
use Data::Dumper;

use OESS::Database;
use OESS::Topology;
use OESS::Measurement qw(BUILDING_FILE);

my $db          = new OESS::Database();
my $topo        = new OESS::Topology();
my $measurement = new OESS::Measurement();

my $cgi  = new CGI;

$| = 1;

sub main {

    if (! $db){
        send_json({"error" => "Unable to connect to database."});
        exit(1);
    }

    my $action = $cgi->param('action');

    my $output;
    my $user = $db->get_user_by_id( user_id => $db->get_user_id_by_auth_name( auth_name => $ENV{'REMOTE_USER'}))->[0];
    if ($user->{'status'} eq 'decom') {
        $action = "error";
    }

    switch ($action){

    case "get_circuit_data" {
                             $output = &get_circuit_data();
    }
    case "error" {
        $output = {error => "Decom users cannot use webservices."};
    }
    else{
        $output = {error => "Unknown action - $action"};
    }

    }

    send_json($output);

}

sub get_circuit_data {
    my $results;

    my $start      = $cgi->param("start");
    my $end        = $cgi->param("end");
    my $circuit_id = $cgi->param("circuit_id");

    # optional parameters, if not given we will pick the first alphabetical node / intf to show traffic for
    my $node       = $cgi->param('node');
    my $interface  = $cgi->param('interface');

    my $link       = $cgi->param('link');

    # if we were sent a link, pick one of the endpoints to use for gathering data
    if (defined $link){

    my $link_id = $db->get_link_id_by_name(link => $link);

    if (! defined $link_id){
        $results->{'results'} = [];
        $results->{'error'} = $db->get_error();
        return $results;
    }

    my $endpoints = $db->get_link_endpoints(link_id => $link_id);

    $node      = $endpoints->[0]->{'node_name'};
    $interface = $endpoints->[0]->{'interface_name'};
    }

    if ($start !~ /^\d+$/ || $end !~ /^\d+$/ || $circuit_id !~ /^\d+$/){
    return undef;
    }

    my $data = $measurement->get_circuit_data(circuit_id => $circuit_id,
                          start_time => $start,
                          end_time   => $end,
                          node       => $node,
                          interface  => $interface
    );


    if (! defined $data){
        $results->{'results'} = [];
        $results->{'error'} = $measurement->get_error();
    }
    elsif ($data eq BUILDING_FILE){
        $results->{'results'}     = [];
        $results->{'in_progress'} = 1;
    }
    else{
        $results->{'results'}    = $data->{'data'};
        $results->{'node'}       = $data->{'node'};
        $results->{'interface'}  = $data->{'interface'};
        $results->{'interfaces'} = $data->{'interfaces'};
    }

    return $results;
}


sub send_json{
    my $output = shift;

    print "Content-type: text/plain\n\n" . encode_json($output);
}

main();

