#!/usr/bin/perl
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

use GRNOC::WebService;

use JSON;
use Switch;
use Data::Dumper;
use Log::Log4perl;

use OESS::Database;
use OESS::Measurement qw(BUILDING_FILE);


Log::Log4perl::init('/etc/oess/logging.conf');

my $db          = new OESS::Database();
my $db2         = new OESS::DB();
my $measurement = new OESS::Measurement();

#register web service dispatcher
my $svc = GRNOC::WebService::Dispatcher->new(method_selector => ['method', 'action']);

$| = 1;

sub main {

    if (! $db){
        send_json({"error" => "Unable to connect to database."});
        exit(1);
    }

    if ( !$svc ){
	send_json( {"error" => "Unable to access GRNOC::WebService" });
	exit(1);
    }

    my $user = $db->get_user_by_id( user_id => $db->get_user_id_by_auth_name( auth_name => $ENV{'REMOTE_USER'}))->[0];
    if ($user->{'status'} eq 'decom') {
	send_json("error");
	exit(1);
    }

    #register the WebService Methods
    register_webservice_methods();

    #handle the WebService request.
    $svc->handle_request();
    
}

sub register_webservice_methods {
    
    my $method;

    #get_circuit_data()
    $method = GRNOC::WebService::Method->new(
	name            => "get_circuit_data",
	description     => "returns JSON formatted usage statistics for a circuit from start time to end time, and for a specific node or interface in the circuit.",
	callback        => sub { get_circuit_data( @_ ) }
	);

    #add the required input parameter circuit_id
    $method->add_input_parameter(
        name            => 'circuit_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The id of the circuit to fetch details for."
        );

    #add the required input parameter start
    $method->add_input_parameter(
	name            => 'start',
	pattern         => '^(\d+)$' ,
	required        => 1,
        description     => "Start time in epoch seconds."
	 );
    
    #add the required input parameter end
    $method->add_input_parameter(
        name            => 'end',
        pattern         => '^(\d+)$' ,
        required        => 1,
        description     => "End time in epoch seconds."
        );

    #add the optional input paramter node
    $method->add_input_parameter(
        name            => 'node',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 0,
        description     => "the node to look at for the circuit usage data."
        );

    #add the optional input parameter interface
    $method->add_input_parameter(
        name            => 'interface',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 0,
        description     => "The name of the interface on the node to look at for the usage statistics. Must be specified when the node parameter is defined."
	);
    
    #add the optional input parameter link
    $method->add_input_parameter(
        name            => 'link',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 0,
        description     => "Name of the link to view data for, if specified node/interface should not be specified."
	);
    
    #register the get_circuit_data() method
    $svc->register_method($method);
}

sub get_circuit_data {

    my ( $method, $args ) = @_ ;
    my $results;

    my $start      = $args->{'start'}{'value'};
    my $end        = $args->{'end'}{'value'};
    my $circuit_id = $args->{'circuit_id'}{'value'};

    # optional parameters, if not given we will pick the first alphabetical node / intf to show traffic for
    my $node       = $args->{'node'}{'value'};
    my $interface  = $args->{'interface'}{'value'};

    my $link       = $args->{'link'}{'value'};
    my ($ok, $err);
    my ($ok, $err) = OESS::DB::User::has_circuit_access(db => $db2, username => $ENV{'REMOTE_USER'}, circuit_id => $circuit_id, role => 'read-only');
    if(!$ok){
        $results->{'error'} = $err;
        return $results;
    }

    # if we were sent a link, pick one of the endpoints to use for gathering data
    if (defined $link){
        my $link_id = $db->get_link_id_by_name(link => $link);

        if (! defined $link_id){
            $method->set_error( $db->get_error() ) ;
            return;
        }

        my $endpoints = $db->get_link_endpoints(link_id => $link_id);
        $node      = $endpoints->[0]->{'node_name'};
        $interface = $endpoints->[0]->{'interface_name'};
    }

    my $circuit = OESS::Circuit->new(circuit_id=>$circuit_id,db=>$db);
    my $data;
    if ($circuit->{'type'} eq 'openflow') {
	$data = $measurement->get_of_circuit_data(circuit_id => $circuit_id,
					       start_time => $start,
					       end_time   => $end,
					       node       => $node,
					       interface  => $interface);
    } else {
	$data = $measurement->get_mpls_circuit_data(circuit_id => $circuit_id,
						    start_time => $start,
						    end_time   => $end,
						    node       => $node,
						    interface  => $interface);
    }

    return $data;

    if (!defined $data) {
        $method->set_error( $measurement->get_error() );
        return;
    }
    elsif ($data eq BUILDING_FILE) {
        $results->{'results'}     = [];
        $results->{'in_progress'} = 1;
    }
    else {
        $results->{'results'}    = $data->{'data'};
        $results->{'node'}       = $data->{'node'};
        $results->{'interface'}  = $data->{'interface'};
        $results->{'interfaces'} = $data->{'interfaces'};
    }

    return $results;
}

sub send_json{
    my $output = shift;
    
    if (!defined($output) || !$output) {
        $output =  { "error" => "Server error in accessing webservices." };
    }

    print "Content-type: text/plain\n\n" . encode_json($output);
}
main();

