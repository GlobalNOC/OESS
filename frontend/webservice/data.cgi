#!/usr/bin/perl 
#
##----- NDDI OESS Data.cgi
##-----
##----- $HeadURL: svn+ssh://svn.grnoc.iu.edu/grnoc/oe-ss/frontend/trunk/webservice/data.cgi $
##----- $Id$
##----- $Date$
##----- $LastChangedBy$
##-----
##----- Retrieves data about the Network for the UI
##
##-------------------------------------------------------------------------
##
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
use strict;
use warnings;

use Data::Dumper;
use JSON::XS;
use Log::Log4perl;
use MIME::Lite;
use Switch;
use Time::HiRes qw(usleep);
use URI::Escape;

use GRNOC::WebService;

use OESS::Circuit;
use OESS::Database;
use OESS::Webservice;


#link statuses
use constant OESS_LINK_UP       => 1;
use constant OESS_LINK_DOWN     => 0;
use constant OESS_LINK_UNKNOWN  => 2;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;
use constant FWDCTL_BLOCKED     => 4;

Log::Log4perl::init_and_watch('/etc/oess/logging.conf',10);

my $db   = new OESS::Database();
my $db2  = new OESS::DB();

#register web service dispatcher
my $svc    = GRNOC::WebService::Dispatcher->new(method_selector => ['method', 'action']);

my $username = $ENV{'REMOTE_USER'};
my $is_admin = $db->get_user_admin_status( 'username' => $username );

$| = 1;

sub main {
        
    if ( !$db ) {
        send_json( { "error" => "Unable to connect to database." } );
        exit(1);
    }

    if ( !$svc ){
	send_json( {"error" => "Unable to access GRNOC::WebService" });
	exit(1);
    }
    
    my $user = $db->get_user_by_id( user_id => $db->get_user_id_by_auth_name( auth_name => $ENV{'REMOTE_USER'}))->[0];
    if ($user->{'status'} eq "decom") {
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

    # get_workgroups()
    $method = GRNOC::WebService::Method->new(
	name            => "get_workgroups",
	description     => "returns a list of workgroups the logged in user has access to",
	callback        => sub { get_workgroups( @_ ) },
    method_deprecated => "This method has been deprecated in favor of user.cgi?method=get_current."
	);

    #register get_workgroups() method
    $svc->register_method($method);

    # get_maps()
    $method = GRNOC::WebService::Method->new(
	name            => "get_maps",
	description     => "returns a JSON object representing the network layout",
	callback        => sub { get_maps( @_ ) } 
	);
    
    # add the required input parameter workgroup_id
    $method->add_input_parameter(
	name            => 'workgroup_id',
	pattern         => $GRNOC::WebService::Regex::INTEGER,
	required        => 0,
	description     => "The workgroup ID that the user is currently participating in."
    );
    $method->add_input_parameter(
	name            => 'link_type',
	pattern         => $OESS::Webservice::CIRCUIT_TYPE,
	required        => 0,
	description     => "The type of links that shall be included in the map."
    );
    
    #register get_maps method
    $svc->register_method($method);
    
    #get_nodes() 
    $method = GRNOC::WebService::Method->new(
	name            => "get_nodes",
	description     => "returns a list of nodes",
	callback        => sub { get_nodes( @_ ) },
    method_deprecated => "This method has been deprecated in favor of node.cgi?method=get_nodes."
    );
    $method->add_input_parameter(
	name            => 'type',
	pattern         => $OESS::Webservice::CIRCUIT_TYPE_WITH_ALL,
	required        => 0,
	description     => "The type of nodes that shall be included in the map."
    );
    
    #register get_nodes() method
    $svc->register_method($method);

    #get_node_interfaces
     $method = GRNOC::WebService::Method->new(
	 name            => "get_node_interfaces",
	 description     => "returns a list of interfaces on the given node",
	 callback        => sub { get_node_interfaces( @_ ) },
    method_deprecated => "This method has been deprecated in favor of interface.cgi?method=get_interfaces."
	 );
    
    #add the required input parameter node
    $method->add_input_parameter(
        name            => 'node',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
        description     => "Name of the node to get a list of available interfaces for."
        );

    #add the required input parameter workgroup_id
    $method->add_input_parameter(
        name            => 'workgroup_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "The workgroup ID that the user is currently participating in."
        );
	
    #add the optional input parameter show_down
    $method->add_input_parameter(
        name            => 'show_down',
        pattern         => $GRNOC::WebService::Regex::BOOLEAN,
        required        => 0,
        description     => "Show down interfaces on the node."
        );

    #add the optional input parameter show_trunk
    $method->add_input_parameter(
        name            => 'show_trunk',
        pattern         => $GRNOC::WebService::Regex::BOOLEAN,
        required        => 0,
        description     => "Show down interfaces on the node."
        );

    $method->add_input_parameter(
        name            => 'type',
        pattern         => $OESS::Webservice::CIRCUIT_TYPE_WITH_ALL,
        required        => 0,
        default         => 'all',
        description     => "Type of interfaces to return."
        );

    #register get_node_interfaces() method
    $svc->register_method($method);

    #get_interface
    $method = GRNOC::WebService::Method->new(
	name            => "get_interface",
	description     => "returns the interface details",
	callback        => sub { get_interface( @_ ) },
    method_deprecated => "This method has been deprecated in favor of interface.cgi?method=get_interface."
	);
    
    #add the required parameter interface_id
    $method->add_input_parameter(
        name            => 'interface_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The interface ID for which the user wants the details."
	);

    #register the get_interface() method
    $svc->register_method($method);

    #get_workgroup_interfaces
    $method = GRNOC::WebService::Method->new(
	name            => "get_workgroup_interfaces",
	description     => "returns a list of interfaces in a workgroup.",
	callback        => sub { get_workgroup_interfaces( @_ ) },
    method_deprecated => "This method has been deprecated in favor of interface.cgi?method=get_interfaces."
	);
    
    #add the required parameter workgroup_id
    $method->add_input_parameter(
        name            => 'workgroup_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The workgroup ID that the user is currently participating in."
        );
    
    #register the get_workgroup_interfaces() method
    $svc->register_method($method);

    #get_shortest_path
    $method = GRNOC::WebService::Method->new(
	name            => "get_shortest_path",
	description     => "returns the shortest contiguous path between the given nodes",
	callback        => sub { get_shortest_path( @_ ) }
	);
    
    #add the required input parameter node
    $method->add_input_parameter(
        name            => 'node',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
	multiple        => 1,
        description     => "An array of node names to connect together with the shortest path."
        );

    #add the required input parameter node                                                                                                                                                                  
    $method->add_input_parameter(
        name            => 'type',
        pattern         => $OESS::Webservice::CIRCUIT_TYPE,
        required        => 1,
        multiple        => 0,
        description     => "type of circuit we are building"
        );


    #add the required input parameter link
    $method->add_input_parameter(
        name            => 'link',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 0,
	multiple        => 1,
        description     => "A list of links to avoid when doing the shortest path calculation"
        );
    
    #register the get_shortest_path() method
    $svc->register_method($method);
    
    #get_existing_circuits
    $method = GRNOC::WebService::Method->new(
	name            => "get_existing_circuits",
	description     => "returns a list of circuits for the given workgroup",
	callback        => sub { get_existing_circuits( @_ ) },
    method_deprecated => "This method has been deprecated in favor of circuit.cgi?method=get."
	);

    #add the required input paramter workgroup_id
    $method->add_input_parameter(
        name            => 'workgroup_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The workgroup ID that the user is currently participating in."
        );

    #add the optional input parameter path_node_id
    $method->add_input_parameter(
        name            => 'path_node_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
	multiple        => 1,
        description     => "Filters the results for circuits that traverse the node of the node_id given"
        );

    #add the optional input parameter endpoint_node_id
    $method->add_input_parameter(
        name            => 'endpoint_node_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
	multiple        => 1,
        description     => "Filters the results to circuits that terminate on the specified node_id"
        );

    #register the get_existing_circuits() method
    $svc->register_method($method);
    
    #get_circuits_by_interface_id
    $method = GRNOC::WebService::Method->new(
	name            => "get_circuits_by_interface_id",
	description     => "returns a list of circuits on an interface",
	callback        => sub { get_circuits_by_interface_id( @_ ) }
	);

    #add the required input parameter interface_id
    $method->add_input_parameter(
        name            => 'interface_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The interface ID for which the user wants the circuit details."
        );  

    #register the get_circuits_by_interface_id() method
    $svc->register_method($method);

    #get_circuit_details
    $method = GRNOC::WebService::Method->new(
	name            => "get_circuit_details",
	description     => "returns all of the details for a given circuit",
	callback        => sub { get_circuit_details ( @_ ) },
    method_deprecated => "This method has been deprecated in favor of circuit.cgi?method=get."
	);
    
    #add the required input parameter circuit_id
    $method->add_input_parameter(
        name            => 'circuit_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The id of the circuit to fetch details for."
        );

    #register the get_circuit_details() method
    $svc->register_method($method);


    #get_circuit_details_by_external_identifier
    $method = GRNOC::WebService::Method->new(
	name            => "get_circuit_details_by_external_identifier",
	description     => "finds the circuit based on some external id",
	callback        => sub { get_circuit_details_by_external_identifier( @_ ) }
	);

    #add the required input parameter external_identifier
    $method->add_input_parameter(
        name            => 'external_identifier',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
        description     => "external identifier when the circuit was created or last modified."
        );

    #register the get_circuit_details_by_external_identifier() method
    $svc->register_method($method);

    
    #get_circuit_scheduled_events
    $method = GRNOC::WebService::Method->new(
	name            => "get_circuit_scheduled_events",
	description     => "returns a list of scheduled circuit events.",
	callback        => sub { get_circuit_scheduled_events( @_ ) }
	);

    #add the required input parameter circuit_id
    $method->add_input_parameter(
        name            => 'circuit_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The id of the circuit fetch scheduled events for."
        );

    #register the get_circuit_scheduled_events() method
    $svc->register_method($method);

    #get_circuit_history
    $method = GRNOC::WebService::Method->new(
	name            => "get_circuit_history",
	description     => "returns a list of network events that have affected this circuit",
	callback        => sub { get_circuit_history( @_ ) }
	);

    #add the required input parameter circuit_id
    $method->add_input_parameter(
        name            => 'circuit_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The id of the circuit fetch network events for."
        );

    #register the get_circuit_history() method
    $svc->register_method($method);

    #is_vlan_tag_available
    $method = GRNOC::WebService::Method->new(
	name            => "is_vlan_tag_available",
	description     => "returns the availability of the vlan tag for a given node and interface",
	callback        => sub { is_vlan_tag_available ( @_ ) }
	);

    #add the required input paramter interface
    $method->add_input_parameter(
        name            => 'interface',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
        description     => "The name of the interface to check the vlan tags availability."
        );
 
    #add the required input paramter node
    $method->add_input_parameter(
        name            => 'node',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
        description     => "The name of the node the interface is on."
        );

    #add the required input paramter vlan_tag
    $method->add_input_parameter(
        name            => 'vlan',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The vlan tag to check the availability of on the node/interface combination."
        );

    #add the optional input paramter inner_vlan
    $method->add_input_parameter(
        name            => 'inner_vlan',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        default         => undef,
        description     => "The inner vlan tag to check the availability of on the node/interface combination."
        );

    #add the required input paramter workgroup_id
    $method->add_input_parameter(
        name            => 'workgroup_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "The workgroup ID that the user wants to check if vlan_tag is available."
        );

    #register the is_vlan_tag_available() method
    $svc->register_method($method);

    #get_workgroup_members
    $method = GRNOC::WebService::Method->new(
	name            => "get_workgroup_members",
	description     => "descr",
	callback        => sub { get_users_in_workgroup( @_ ) },
    method_deprecated => "This method has been deprecated in favor of workgroup.cgi?method=get_workgroup_users."
	);

    #add the required input parameter workgroup_id
    $method->add_input_parameter(
        name            => 'workgroup_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The workgroup ID that the user is currently participating in."
        );

    #add the optional input parameter order_by
    $method->add_input_parameter(
        name            => 'order_by',
        pattern         => '^(given_names|auth_name)$',
        required        => 0,
        description     => "Specify how the workgroups should be ordered."
        );

    #register the get_workgroup_members() method.
    $svc->register_method($method);

    #generate_clr
    $method = GRNOC::WebService::Method->new(
	name            => "generate_clr",
	description     => "generates a human readable Circuit Layout Record describing the given circuit.",
	callback        => sub { generate_clr ( @_ ) }
	);

    #add the required input parameter circuit_id
    $method->add_input_parameter(
        name            => 'circuit_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The circuit_id of the circuit to have the CLR generated for."
        );

    #add the optional input parameter raw
    $method->add_input_parameter(
        name            => 'raw',
        pattern         => $GRNOC::WebService::Regex::BOOLEAN,
        required        => 0,
        description     => "Generate flow rule view of the circuit for every node."
        );

    #register the generate_clr() method
    $svc->register_method($method);

    #get_all_node_status
    $method = GRNOC::WebService::Method->new(
	name            => "get_all_node_status",
	description     => "returns a list of all active nodes and their operational status.",
	callback        => sub { get_all_node_status( @_ ) },
    method_deprecated => "This method has been deprecated in favor of node.cgi?method=get_nodes."    
    );
    $method->add_input_parameter(
	name            => 'type',
	pattern         => $OESS::Webservice::CIRCUIT_TYPE_WITH_ALL,
	required        => 0,
	description     => "The type of nodes that shall be included in the map."
    );

    #register the get_all_node_status() method
    $svc->register_method($method);

    #get_all_link_status
    $method = GRNOC::WebService::Method->new(
        name            => "get_all_link_status",
        description     => "returns a list of all active links and their operational status.",
        callback        => sub { get_all_link_status( @_ ) }
        );
    $method->add_input_parameter(
	name            => 'type',
	pattern         => $OESS::Webservice::CIRCUIT_TYPE_WITH_ALL,
	required        => 0,
	description     => "The type of links that shall be included."
    );

    #register the get_all_link_status() method
    $svc->register_method($method);

    #get_all_resources_for_workgroup
    $method = GRNOC::WebService::Method->new(
	name            => "get_all_resources_for_workgroup",
	description     => "returns a list of all resources (endpoints) for which the workgroup has access",
	callback        => sub { get_all_resources( @_ ) }
	);

    #add the required input parameter workgroup_id
    $method->add_input_parameter(
        name            => 'workgroup_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The workgroup ID that the user wants to get the list of resources."
	);

    #register the get_all_resources_for_workgroup() method
    $svc->register_method($method);

    #send_email
    $method = GRNOC::WebService::Method->new(
	name            => "send_email",
	description     => "sends an email o behalf of user from the OESS application",
	callback        => sub { send_message ( @_ ) }
	);

    #add the required input parameter subject
    $method->add_input_parameter(
        name            => 'subject',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
        description     => "The subject of the email."
	);
    
    #add the required input parameter body
    $method->add_input_parameter(
        name            => 'body',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
        description     => "The body of the email."
	);

    #register the send_email() method
    $svc->register_method($method);

    #get_link_by_name
    $method = GRNOC::WebService::Method->new(
	name            => "get_link_by_name",
	description     => "returns a link details given the name of the link.",
	callback        => sub {  get_link_by_name( @_ ) }
	);

    #add the required input parameter name
    $method->add_input_parameter(
        name            => 'name',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
        description     => "The name of the link."
	);

    #register the get_link_by_name() method
    $svc->register_method($method);

    #is_within_mac_limit
    $method = GRNOC::WebService::Method->new(
	name            => "is_within_mac_limit",
	description     => "Returns if a new mac address can be added on node’s interface",
	callback        => sub { is_within_mac_limit( @_ ) }
	);

    #add the required input paramter workgroup_id
    $method->add_input_parameter(
        name            => 'workgroup_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The ID of the workgroup for which the mac limit check is requested for."
	);

    #add the required input parameter mac_address
    $method->add_input_parameter(
        name            => 'mac_address',
        pattern         => $GRNOC::WebService::Regex::MAC_ADDRESS,
        required        => 1,
	multiple        => 1,
        description     => "List of mac addresses that may need to added."
	);

    #add the required input paramter node
    $method->add_input_parameter(
        name            => 'node',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
        description     => "Name of the node for which the mac address limit check is requested for."
	);
    
    #add the required input parameter interface
    $method->add_input_parameter(
        name            => 'interface',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
        description     => "Interface on the node for which the mac address limit check is requested for."
	);

    #register the is_within_mac_limit() method
    $svc->register_method($method);

    #is_within_circuit_endpoint_limit
    $method = GRNOC::WebService::Method->new(
	name            => "is_within_circuit_endpoint_limit",
	description     => "Checks that number of circuits in a workgroup on an endpoint are within the specified limit",
	callback        => sub { is_within_circuit_endpoint_limit( @_ ) }
	 );

    #add the required input parameter workgroup_id
    $method->add_input_parameter(
        name            => 'workgroup_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The ID of the workgroup for which the circuit limit check is requested for.."
	);

    #add the required input parameter endpoint_num
    $method->add_input_parameter(
        name            => 'endpoint_num',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The number for which the endpoints allowed on the circuit is checked for."
	);

    #register the is_within_circuit_endpoint_limit() method
    $svc->register_method($method);

    #is_within_circuit_limit
    $method = GRNOC::WebService::Method->new(
        name            => "is_within_circuit_limit",
        description     => "Checks that number of circuits in a workgroup  are within the specified limit",
        callback        => sub { is_within_circuit_limit( @_ ) }
	);

    #add the required input parameter workgroup_id
    $method->add_input_parameter(
        name            => 'workgroup_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The ID of the workgroup for which the circuit limit check is requested for.."
        );

    #register the is_within_circuit_limit() method
    $svc->register_method($method);

    #get_vlan_tag_range
    $method = GRNOC::WebService::Method->new(
        name            => "get_vlan_tag_range",
        description     => "returns a vlan tag range for a node on an interface in a workgroup",
        callback        => sub { get_vlan_tag_range( @_ ) }
	);

    #add the required input parameter workgroup_id
    $method->add_input_parameter(
        name            => 'workgroup_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The ID of the workgroup for which the vlan tag range is requested for."
        );

    #add the required input parameter node
    $method->add_input_parameter(
        name            => 'node',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
        description     => "Name of the node for which the vlan tag range is requested for."
        );

    #add the required input parameter interface
    $method->add_input_parameter(
        name            => 'interface',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
        description     => "Name of the interface for which the vlan tag range is requested for."
        );
    
    #register the get_vlan_tag_range() method
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new(
        name 		=> "get_users",
        description	=> "returns all the users in the database",
        callback	=> sub { get_users( @_ ) },
        method_deprecated => "This method has been deprecated in favor of user.cgi?method=get_users."
    );
    $svc->register_method($method);
}


sub get_workgroups {
    
    my ( $method, $args ) = @_ ;
    my $results;
    
    my $user = new OESS::User(db => $db2, username => $username);
    $user->load_workgroups();
    my $workgroups = $user->to_hash()->{workgroups};
    
    if ( !defined $workgroups ) {
	$method->set_error($db->get_error());
	return;
    }
    else {

	foreach my $workgroup (@$workgroups) {
	    $workgroup->{username} = $username;
	}
        $results->{'results'} = $workgroups;
    }

    
    return $results;
}

sub get_circuits_by_interface_id {
    
    my ( $method, $args ) = @_ ;
    my $interface_id = $args->{'interface_id'}{'value'};

    my $results = { results => [] };
    my $circuits = $db->get_circuits_by_interface_id( interface_id => $interface_id );
    
    if ( !defined $circuits ) {
	$method->set_error( $db->get_error() ) ;
	return;
    }
    else {
        my $circuit;
        foreach(@{$circuits}){
            my ($ok, $err) = OESS::DB::User::has_circuit_permission(db => $db2, username => $ENV{'REMOTE_USER'}, circuit_id => $_->{'circuit_id'}, permission => 'read');
            if($ok){
		push($results->{'results'}, $_);
            }
        }
    }

    return $results;
}

sub get_interface {
    
    my ( $method, $args ) = @_ ;
    my $results;

    my $interface_id = $args->{'interface_id'}{'value'};

    my $interface = $db->get_interface( interface_id => $interface_id );

    if ( !defined $interface ) {
	$method->set_error( $db->get_error() );
	return;
    }
    else {
        $results->{'results'} = $interface;
    }

    return $results;

}
sub get_workgroup_interfaces {
    
    my ( $method, $args ) = @_ ;
    my $results;

    my $workgroup_id = $args->{'workgroup_id'}{'value'};
    my $user_id = $db->get_user_id_by_auth_name(auth_name => $username);
    if(!$is_admin && !$db->is_user_in_workgroup(user_id => $user_id, workgroup_id => $workgroup_id)){
	$method->set_error('Error: you are not part of this workgroup');
	return;
    }

    my $acls = $db->get_workgroup_interfaces( workgroup_id => $workgroup_id );

    if ( !defined $acls ) {
	$method->set_error( $db->get_error() );
	return;
    }
    else {
        $results->{'results'} = $acls;
    }
    
    return $results;
}

sub is_vlan_tag_available {
    my ( $method, $args ) = @_ ;

    my $interface    = $args->{'interface'}{'value'};
    my $node         = $args->{'node'}{'value'};
    my $vlan_tag     = $args->{'vlan'}{'value'};
    my $inner_vlan_tag = $args->{'inner_vlan'}{'value'};
    my $workgroup_id = $args->{'workgroup_id'}{'value'};

    my $interface_id = $db->get_interface_id_by_names(
        node      => $node,
        interface => $interface
    );
    if (!defined $interface_id) {
	$method->set_error( "Unable to find interface '$interface' on endpoint '$node'" );
	return;
    }

    my $is_vlan_tag_accessible = $db->_validate_endpoint(
        interface_id => $interface_id,
        vlan         => $vlan_tag,
        workgroup_id => $workgroup_id
    );
    if (!defined $is_vlan_tag_accessible) {
        $method->set_error($db->get_error());
        return;
    }
    if (!$is_vlan_tag_accessible) {
        return { results => [{ available => 0 }] };
    }

    my $is_available = $db->is_external_vlan_available_on_interface(
        vlan         => $vlan_tag,
        inner_vlan   => $inner_vlan_tag,
        interface_id => $interface_id
    );
    if (!defined $is_available) {
        $method->set_error($db->get_error());
        return;
    }
    return { results => [{ available => $is_available->{status}, type => $is_available->{type} }] };
}

sub get_vlan_tag_range {

    my ( $method, $args ) = @_ ;
    my $node = $args->{'node'}{'value'};
    my $interface = $args->{'interface'}{'value'};
    my $workgroup_id = $args->{'workgroup_id'}{'value'};

    my $interface_id = $db->get_interface_id_by_names(
        interface => $interface,
        node      => $node 
    ); 

    my $vlan_tag_range = $db->_validate_endpoint(
        interface_id => $interface_id,
        workgroup_id => $workgroup_id
    );

    return {
        results => [
            {vlan_tag_range => $vlan_tag_range}
        ]
    };

}

sub get_link_by_name {
    
    my ( $method, $args ) = @_ ;
    my $results;

    $results->{'results'} = [];
    
    my $name = $args->{'name'}{'value'};
    
    my $link = $db->get_link_by_name( name => $name );
    
    if ( !defined $link ) {
	$method->set_error( $db->get_error() );
	return;
    }
    else {
        $results->{'results'} = $link;
    }

    return $results;
}

sub get_circuit_scheduled_events {
    
    my ( $method, $args ) = @_ ;
    my $results;

    my $circuit_id = $args->{'circuit_id'}{'value'};
    my ($ok, $err) = OESS::DB::User::has_circuit_permission(db => $db2, username => $ENV{'REMOTE_USER'}, circuit_id => $circuit_id, permission => 'read');
    if(!$ok){
        $results->{'error'} = $err;
        return $results;
    }

    my $events = $db->get_circuit_scheduled_events( circuit_id => $circuit_id );

    if ( !defined $events ) {
	$method->set_error( $db->get_error() );
	return;
    }
    else {
        $results->{'results'} = $events;
    }

    return $results;
}

sub get_circuit_history {
    
    my ( $method, $args ) = @_ ;
    my $results;

    my $circuit_id = $args->{'circuit_id'}{'value'};
    
    my ($ok, $err) = OESS::DB::User::has_circuit_permission(db => $db2, username => $ENV{'REMOTE_USER'}, circuit_id => $circuit_id, permission => 'read');
    if(!$ok){
        $results->{'error'} = $err;
        return $results;
    }

    my $events = $db->get_circuit_history( circuit_id => $circuit_id );

    if ( !defined $events ) {
	$method->set_error( $db->get_error() );
	return;
    }
    else {
        $results->{'results'} = $events;
    }

    return $results;
}

sub get_circuit_details {
    my $results;

    my ( $method, $args ) = @_ ;
    my $circuit_id = $args->{'circuit_id'}{'value'};
       
    my ($ok, $err) = OESS::DB::User::has_circuit_permission(db => $db2, username => $ENV{'REMOTE_USER'}, circuit_id => $circuit_id, permission => 'read');
    if(!$ok){
        $results->{'error'} = $err;
        return $results;
    }
    my $ckt = OESS::Circuit->new( circuit_id => $circuit_id, db => $db);
    my $details = $ckt->get_details();

    if ( !defined $details ) {
	$method->set_error( $db->get_error() );
	return;
    }
    else {
        $results->{'results'} = $details;
    }

    return $results;
}

sub get_circuit_details_by_external_identifier {
    
    my ( $method, $args ) = @_ ;
    my $results;

    my $external_id = $args->{'external_identifier'}{'value'};

    my $info = $db->get_circuit_by_external_identifier(
        external_identifier => $external_id );

    if ( !defined $info ) {
	$method->set_error( $db->get_error() );
        return;
    }
    my $circuit_id = $info->{'circuit_id'};
    my ($ok, $err) = OESS::DB::User::has_circuit_permission(db => $db2, username => $ENV{'REMOTE_USER'}, circuit_id => $circuit_id, permission => 'read');
    if(!$ok){
        $results->{'error'} = $err;
        return $results;
    }

    my $ckt = OESS::Circuit->new( circuit_id => $circuit_id, db => $db);
    my $details = $ckt->get_details();

    if ( !defined $details ) {
	$method->set_error( $db->get_error() );
	return;
    }
    else {
        $results->{'results'} = $details;
    }

    return $results;
}

sub get_existing_circuits {

    my ( $method, $args ) = @_ ;
    my $results;

    my $workgroup_id   = $args->{'workgroup_id'}{'value'};
    my @endpoint_nodes = $args->{'endpoint_node_id'}{'value'} || [];
    my @path_nodes     = $args->{'path_node_id'}{'value'} || [];


    my $is_admin = $db->get_user_admin_status( 'username' => $username )->[0];
    if ( !$workgroup_id ) {
        if(!$is_admin) {
	    $method->set_error( "Error: no workgroup_id specified" );
	    return;
	}
    }else {
        my $user_id = $db->get_user_id_by_auth_name(auth_name => $username);
        if(!$is_admin && !$db->is_user_in_workgroup(user_id => $user_id, workgroup_id => $workgroup_id)){
            $method->set_error( 'Error: you are not part of this workgroup' );
	    return;
	}
    }

    my %link_status;
    my $links = $db->get_current_links(type => 'all');
    foreach my $link (@$links){
        if($link->{'status'} eq 'up'){
            $link_status{$link->{'name'}} = OESS_LINK_UP;
        }elsif($link->{'status'} eq 'down'){
            $link_status{$link->{'name'}} = OESS_LINK_DOWN;
        }else{
            $link_status{$link->{'name'}} = OESS_LINK_UNKNOWN;
        }
    }

    my $circuits = $db->get_current_circuits(
        workgroup_id   => $workgroup_id,
        endpoint_nodes => @endpoint_nodes,
        path_nodes     => @path_nodes,
        link_status    => \%link_status,
	type           => 'all'
    );

    
    my @res;

    foreach my $circuit (@$circuits) {
        push( @res, $circuit->get_details() );
    }
    
    if ( !defined $circuits ) {
	$method->set_error( $db->get_error() );
	return;
    }
    else {
        $results->{'results'} = \@res;
    }

    return $results;
}

sub get_shortest_path {

    my ( $method, $args ) = @_ ;
    my $results;

    $results->{'results'} = [];

    my @nodes = $args->{'node'}{'value'};
    my @links_to_avoid = $args->{'link'}{'value'};
    my $type = $args->{'type'}{'value'};
    my $topo = $db->{'topo'};
    my $sp_links = $topo->find_path(
        nodes      => @nodes,
        used_links => @links_to_avoid,
	type => $type
    );

    if ( !defined $sp_links ) {
	$method->set_error( "No path found" );
	return;
    }

    foreach my $link (@$sp_links) {
        push( @{ $results->{'results'} }, { "link" => $link } );
    }

    return $results;

}

sub get_nodes {

    my ( $method, $args ) = @_ ;
    my $type = $args->{'type'}{'value'} || 'all';

    my $nodes = $db->get_current_nodes(type => $type);

    if ( !defined($nodes) ) {
	$method->set_error( $db->get_error() );
	return;
    }
    return ( { results => $nodes } );

}

sub get_node_interfaces {

    my ( $method, $args ) = @_ ;
    my $results;

    my $node         = $args->{'node'}{'value'};
    my $workgroup_id = $args->{'workgroup_id'}{'value'};
    my $show_down    = $args->{'show_down'}{'value'} || 0;
    my $show_trunk   = $args->{'show_trunk'}{'value'} || 0;
    my $type         = $args->{'type'}{'value'};

    my $interfaces   = $db->get_node_interfaces(
        node         => $node,
        workgroup_id => $workgroup_id,
        show_down    => $show_down,
        show_trunk   => $show_trunk,
        type         => $type
    );

    # something went wrong
    if ( !defined $interfaces ) {
	$method->set_error( $db->get_error() );
	return;
    } else {
        $results->{'results'} = $interfaces;
    }

    return $results;
}

# If link_type is specified, the returned links will be limited to
# links of the specified type. Valid link types are `openflow` and
# `mpls`.
sub get_maps {

    my ( $method, $args ) = @_ ;
    my $results;
    my $workgroup_id = $args->{'workgroup_id'}{'value'};
    my $link_type    = $args->{'link_type'}{'value'};

    my $user_id = $db->get_user_id_by_auth_name(auth_name => $username);
    if(!$is_admin && !$db->is_user_in_workgroup(user_id => $user_id, workgroup_id => $workgroup_id)){
	$method->set_error( 'Error: you are not part of this workgroup' );
	return;
    }

    my $layers = $db->get_map_layers(workgroup_id => $workgroup_id, link_type => $link_type);
    if (!defined $layers) {
	$method->set_error( $db->get_error() );
	return;
    } else {
        $results->{'results'} = $layers;
    }

    return $results;
}

sub get_users_in_workgroup {
    
    my ( $method, $args ) = @_ ;
    my $results;

    my $workgroup_id = $args->{'workgroup_id'}{'value'};
    my $order_by     = $args->{'order_by'}{'value'};
    my $user_id = $db->get_user_id_by_auth_name(auth_name => $username);
    if(!$is_admin && !$db->is_user_in_workgroup(user_id => $user_id, workgroup_id => $workgroup_id)){
	$method->set_error( 'Error: you are not part of this workgroup' );
	return;
    }

    my $users = $db->get_users_in_workgroup( workgroup_id => $workgroup_id, order_by => $order_by );

    if ( !defined $users ) {
	$method->set_error( $db->get_error() );
	return;
    }
    else {
        $results->{'results'} = $users;
    }

    return $results;
}

sub generate_clr {
    
    my ( $method, $args ) = @_ ;
    my $results;

    my $circuit_id = $args->{'circuit_id'}{'value'};
    if ( !defined($circuit_id) ) {
	$method->set_error( "No Circuit ID Specified" );
    }
    my ($ok, $err) = OESS::DB::User::has_circuit_permission(db => $db2, username => $ENV{'REMOTE_USER'}, circuit_id => $circuit_id, permission => 'read');
    if(!$ok){
        $results->{'error'} = $err;
        return $results;
    }

    my $ckt = OESS::Circuit->new( circuit_id => $circuit_id, db => $db);

    my $circuit_clr;
    if( $args->{'raw'}{'value'} ){
        $circuit_clr = $ckt->generate_clr_raw();
    }else {
        $circuit_clr = $ckt->generate_clr();
    }
    
    if ( !defined($circuit_clr) ) {
	$method->set_error( $db->get_error() );
	return;
    }
    else {
	$results->{'results'} = { clr => $circuit_clr };
    }

    return $results;
}

sub get_all_node_status {
    
    my ( $method, $args ) = @_ ;
    my $type = $args->{'type'}{'value'} || 'all';

    my $results;

    my $nodes = $db->get_current_nodes(type => $type);
    $results->{'results'} = $nodes;
    return $results;
}

sub get_all_link_status {

    my ( $method, $args ) = @_ ;
    my $type = $args->{'type'}{'value'} || 'all';

    my $results;

    my $links = $db->get_current_links(type => $type);

    $results->{'results'} = $links;
    return $results;
}

sub get_all_resources {
    
    my ( $method, $args ) = @_ ;
    my $results;

    my $workgroup_id = $args->{'workgroup_id'}{'value'};

    my $user_id = $db->get_user_id_by_auth_name(auth_name => $username);
    if(!$is_admin && !$db->is_user_in_workgroup(user_id => $user_id, workgroup_id => $workgroup_id)){
	$method->set_error( 'Error: you are not part of this workgroup' );
	return;
    }

    $results->{'results'} = $db->get_available_resources( workgroup_id => $workgroup_id );
    return $results;
}

sub is_within_circuit_limit {
    
    my ( $method, $args ) = @_ ;
    my $workgroup_id   = $args->{'workgroup_id'}{'value'};
    
    if(!$workgroup_id){
	$method->set_error( "Must send workgroup_id" );
	return;
    }
    my $return = $db->is_within_circuit_limit(
        workgroup_id => $workgroup_id
    );

    return {
        error => undef,
        results => [{
            'within_limit' => $return
        }]
    };

}

sub is_within_circuit_endpoint_limit {
    
    my ( $method, $args ) = @_ ;
    my $workgroup_id   = $args->{'workgroup_id'}{'value'};
    my $endpoint_num   = $args->{'endpoint_num'}{'value'};

    if(!defined($workgroup_id) || !defined($endpoint_num)){
	$method->set_error("Must send workgroup_id and endpoint_num" );
	return;
    }
    my $return = $db->is_within_circuit_endpoint_limit(
        workgroup_id => $workgroup_id,
        endpoint_num => $endpoint_num
    );

    return {
        error => undef,
        results => [{
            'within_limit' => $return
        }]
    };
}

sub is_within_mac_limit {

    my ( $method, $args ) = @_ ;
    my @mac_addresses  = $args->{'mac_address'}{'value'};
    my $interface      = $args->{'interface'}{'value'};
    my $node           = $args->{'node'}{'value'};
    my $workgroup_id   = $args->{'workgroup_id'}{'value'};

    if(!@mac_addresses || !$interface || !$node || !$workgroup_id){
	$method->set_error( "Must send mac_address, interface, node, and workgroup_id" );
	return;
    }

    my $return = $db->is_within_mac_limit(
        mac_address  => @mac_addresses,
        interface    => $interface,
        node         => $node,
        workgroup_id => $workgroup_id 
    );
    return {
        error => undef,
        results => [
            $return
        ]
    };
}

sub send_message {
    
    my ( $method, $args ) = @_ ;
    my $results;

    my $subject = $args->{'subject'}{'value'};
    my $body    = $args->{'body'}{'value'};

    my $username = $ENV{'REMOTE_USER'};

    my $message = MIME::Lite->new(
        From    => 'oess@' . $db->get_local_domain_name(),
        To      => $db->get_admin_email(),
        Subject => $subject,
        Type    => 'text/html',
        Data    => uri_unescape($body)
          . "<br><br>This was generated on behalf of $username from the OESS Application"
    );
    $message->send( 'smtp', 'localhost' );

    return { results => [ { success => 1 } ] };
    
}

sub send_json {
    my $output = shift;
    if (!defined($output) ||!$output) {
        $output =  { "error" => "Server error in accessing webservices." };
    }
    print "Content-type: text/plain\n\n" . encode_json($output);
}
sub get_users {
    
    my $users = $db->get_users();
    
    return { results => $users };
}
main();

