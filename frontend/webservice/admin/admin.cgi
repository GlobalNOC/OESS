#!/usr/bin/perl
#
##----- NDDI OESS Admin.cgi
##-----
##----- $HeadURL: svn+ssh://svn.grnoc.iu.edu/grnoc/oe-ss/frontend/trunk/webservice/admin/admin.cgi $
##----- $Id$
##----- $Date$
##----- $LastChangedBy$
##-----
##----- provides administrative functions to the UI
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
use Data::Dumper;
use JSON;
use LWP::UserAgent;
use Switch;

use GRNOC::RabbitMQ::Client;
use GRNOC::WebService;

use OESS::Database;
use OESS::Topology;


use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;


my $db   = new OESS::Database();
my $topo = new OESS::Topology();

my $cgi = new CGI;
my $svc = GRNOC::WebService::Dispatcher->new();

$| = 1;


=head2 authorization

Checks if the $REMOTE_USER should be authorized. If any authorization
check fails an error will be returned. Returns a user whenever possible.
Caller should check if error is defined to determine if authorization
has failed.

=over 1

=item $admin     If set to 1 authorization will be granted to admin users

=item $read_only If set to 1 authorization will be granted to read only users

=back

Returns a ($user, $error) tuple.

=cut
sub authorization {
    my %params    = @_;
    my $admin     = $params{'admin'};
    my $read_only = $params{'read_only'};

    my $username  = $ENV{'REMOTE_USER'};

    my $auth = $db->get_user_admin_status( 'username' => $remote_user);
    if (!defined $auth) {
        return (undef, { error => "Invalid or decommissioned user specified." });
    }

    my $user_id = $db->get_user_id_by_auth_name(auth_name => $username);
    if (!defined $user_id) {
        return (undef, { error => "Invalid or decommissioned user specified." });
    }
    
    my $user = $db->get_user_by_id(user_id => $user_id)->[0];
    if (!defined $user || $user->{'status'} eq 'decom') {
        return (undef, { error => "Invalid or decommissioned user specified." });
    }

    if ($admin == 1 && $authorization->[0]{'is_admin'} != 1) {
        return ($user, { error => "User $username does not have admin privileges." });
    }
    
    if ($read_only != 1 && &user->{'type'} eq 'read-only') {
        return ($user, { error => "User $username is a read only user." });
    }

    return ($user, undef);
}

sub main {
    if (!$db) {
        send_json({ error => "Unable to connect to database." });
        exit(1);
    }

    my $action      = $cgi->param('action');
    my $remote_user = $ENV{'REMOTE_USER'};
    my $output;

    # TODO - REMOVE ME BEGIN
    my $authorization = $db->get_user_admin_status( 'username' => $remote_user);
    my $user = $db->get_user_by_id( user_id => $db->get_user_id_by_auth_name( auth_name => $ENV{'REMOTE_USER'}))->[0];
    if (!defined $user || $user->{'status'} eq 'decom') {
        return send_json({ error => "Invalid or decommissioned user specified." });
    }
    if ($user->{'type'} eq 'read-only') {
        $read_only = 1;
    }    
    if ( $authorization->[0]{'is_admin'} != 1 ) {
        return send_json({ error => "User $remote_user does not have admin privileges" });
    }
    # TODO - REMOVE ME END
    
    register_webservice_methods();
    
    switch ($action) {
        case "update_node" {
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &update_node();
        }
        case "update_interface" {
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &update_interface();
        }
        case "decom_node" {
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &decom_node();
        }
        case "confirm_link" {
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &confirm_link();
        }
        case "update_link" {
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &update_link();
        }
        case "is_new_node_in_path"{
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &is_new_node_in_path();
        }
        case "insert_node_in_path" {
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &insert_node_in_path();
        }
        case "is_ok_to_decom_link" {
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &is_ok_to_decom();
        }
        case "deny_device" {
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &deny_device();
        }
        case "deny_link" {
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &deny_link();
        }
        case "decom_link" {
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &decom_link();
        }
        case "get_users" {
            $output = &get_users();
        }
        case "get_users_in_workgroup" {
            $output = &get_users_in_workgroup();
        }
        case "add_user" {
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &add_user();
        }
        case "delete_user" {
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &delete_user();
        }
        case "add_user_to_workgroup" {
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &add_user_to_workgroup();
        }
        case "remove_user_from_workgroup" {
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &remove_user_from_workgroup();
        }
        case "edit_user" {
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &edit_user();
        }
        case "get_workgroups" {
            $output = &get_workgroups();
        }
        case "update_interface_owner" {
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &update_interface_owner();
        }
        case "add_workgroup" {
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &add_workgroup();
        }
        case "add_remote_link" {
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &add_remote_link();
        }
        case "edit_remote_link" {
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &edit_remote_link();
        }
        case "remove_remote_link" {
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &remove_remote_link();
        }
        case "get_remote_links" {
            $output = &get_remote_links();
        }
        case "submit_topology" {
            $output = &submit_topology();
        }
        case "get_remote_devices" {
            $output = &get_remote_devices();
        }
        case "update_remote_device" {
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &update_remote_device();
        }
        case "populate_remote_information" {
            $output = &populate_remote_information();
        }case "get_circuits_on_interface" {
            $output = &get_circuits_on_interface();
        }case "edit_workgroup"{
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &edit_workgroup();
        }case "get_topology"{
            $output = &gen_topology();
        }case "decom_workgroup"{
            if($user->{'type'} eq 'read-only'){
                return send_json({error => 'Error: you are a readonly user'});
            }
            $output = &decom_workgroup();
        }
          else {
              return $svc->handle_request();
          }
    }

    send_json($output);
}

sub register_webservice_methods {
    my $method = undef;

    $method = GRNOC::WebService::Method->new( name        => 'add_edge_interface_move_maintenances',
                                              description => 'Creates a list interface maintenances.',
                                              callback    => sub { add_edge_interface_move_maintenances(@_) } );
    $method->add_input_parameter( name        => 'name',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  requried    => 0,
                                  description => 'Name of the new maintenance.' );
    $method->add_input_parameter( name        => 'orig_interface_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  requried    => 1,
                                  description => 'Interface ID of the original interface.');
    $method->add_input_parameter( name        => 'temp_interface_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  requried    => 1,
                                  description => 'Interface ID of the temporary interface.');    
    $method->add_input_parameter( name        => 'circuit_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  requried    => 0,
                                  description => 'Circuit IDs of the circuits on original_interface.');
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'get_edge_interface_move_maintenances',
                                              description => 'Returns a list interface maintenances.',
                                              callback    => sub { get_edge_interface_move_maintenances(@_) } );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'revert_edge_interface_move_maintenance',
                                              description => 'Reverts an interface maintenance.',
                                              callback    => sub { revert_edge_interface_move_maintenances(@_) } );
    $method->add_input_parameter( name        => 'maintenance_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  requried    => 0,
                                  description => 'Maintenance ID of the maintenance to revert.');
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'move_edge_interface_circuits',
                                              description => "Moves an interface's circuits.",
                                              callback    => sub { move_edge_interface_circuits(@_) } );
    $method->add_input_parameter( name        => 'orig_interface_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  requried    => 1,
                                  description => 'Interface ID of the original interface.');
    $method->add_input_parameter( name        => 'new_interface_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  requried    => 1,
                                  description => 'Interface ID of the temporary interface.');    
    $method->add_input_parameter( name        => 'circuit_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  requried    => 0,
                                  description => 'Circuit IDs of the circuits on original_interface.' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'get_pending_nodes',
                                              description => "Returns a list of nodes to be approved.",
                                              callback    => sub { get_pending_nodes(@_) } );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'get_pending_links',
                                              description => "Returns a list of links to be approved.",
                                              callback    => sub { get_pending_links(@_) } );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'confirm_node',
                                              description => "Approves a node.",
                                              callback    => sub { confirm_node(@_) } );
    $method->add_input_parameter( name        => 'node_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  requried    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'name',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  requried    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'longitude',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  requried    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'latitude',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  requried    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'vlan_range',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  requried    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'default_drop',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  requried    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'default_forward',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  requried    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'tx_delay_ms',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  requried    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'max_flows',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  requried    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'bulk_barrier',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  requried    => 1,
                                  description => '' );
    $svc->register_method($method);






    
}

sub get_circuits_on_interface{
    my $results;

    my $link = $db->get_link_by_interface_id( interface_id => $cgi->param('interface_id'),
                                              show_decom => 0 );
    if(defined($link->[0])){
        #we have a link so now its really easy just call get_circuits_on_link
        $results->{'results'} = $db->get_circuits_on_link( link_id => $link->[0]->{'link_id'} );
    }else{
        #ok... the interface is not part of a link, need to find all the circuits that have an endpoint on this interface

    }
    return $results;
}


sub insert_node_in_path{
    my $results = $db->insert_node_in_path( link => $cgi->param('link_id'));

    return {results =>  => [$results]};
    
}

sub is_new_node_in_path{
    my $results;

    $results->{'results'} = [];

    $results->{'results'}->[0] = $db->is_new_node_in_path(link => $cgi->param('link'));
    return $results;
}

sub is_ok_to_decom{

    my $results;
    $results->{'results'} = [];

    my $link_details = $db->get_link( link_id => $cgi->param('link_id'));

    my $circuits = $db->get_circuits_on_link( link_id => $link_details->{'link_id'} );
    $results->{'results'}->[0]->{'active_circuits'} = $circuits;



    $results->{'results'}->[0]->{'new_node_in_path'} = $db->is_new_node_in_path(link => $link_details);

    return $results;

}

sub get_remote_devices {
    my $results;

    $results->{'results'} = [];

    my $devices = $db->get_remote_nodes();

    if ( !defined $devices ) {
        $results->{'error'} = $db->get_error();
    }
    else {
        $results->{'results'} = $devices;
    }

    return $results;
}

sub submit_topology {
    my $results;

    my $topology_xml = $db->gen_topo();
    my $httpEndpoint = $db->get_oscars_topo();

    my $xml = "";
    $xml .=
        '<SOAP-ENV:Envelope xmlns:SOAP-ENC="http://schemas.xmlsoap.org/soap/encoding/"
                   xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                   xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                   xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
             <SOAP-ENV:Header/>
             <SOAP-ENV:Body>';
    $xml .=
        '<nmwg:message type="TSReplaceRequest" xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/">
               <nmwg:metadata id="meta0">
                  <nmwg:eventType>http://ggf.org/ns/nmwg/topology/20070809</nmwg:eventType>
                     </nmwg:metadata>
                       <nmwg:data id="data0" metadataIdRef="meta0">';
    $xml .= $topology_xml;
    $xml .= '          </nmwg:data>
              </nmwg:message>
              </SOAP-ENV:Body>
              </SOAP-ENV:Envelope>';

    my $method_uri = "http://ggf.org/ns/nmwg/base/2.0/message/";
    my $userAgent = LWP::UserAgent->new( 'timeout' => 10 );
    my $sendSoap =
        HTTP::Request->new( 'POST', $httpEndpoint, new HTTP::Headers, $xml );
    $sendSoap->header( 'SOAPAction' => $method_uri );
    $sendSoap->content_type('text/xml');
    $sendSoap->content_length( length($xml) );

    my $httpResponse = $userAgent->request($sendSoap);
    warn Dumper($httpResponse);
    warn Dumper($httpResponse->code());
    warn Dumper($httpResponse->message());
    
    if($httpResponse->code() == 200 && $httpResponse->message() eq 'success'){
        $results->{'results'} = [ { success => 1 } ];
    }else{
        $results->{'error'} = $httpResponse->message();
    }
    return $results;
}

sub get_remote_links {
    my $results;

    my $output = $db->get_remote_links();

    if ( !defined $output ) {
        $results->{'error'} = $db->get_error();
    }
    else {
        $results->{'results'} = $output;
    }

    return $results;
}

sub remove_remote_link {
    my $results;

    my $link_id = $cgi->param('link_id');

    my $output = $db->delete_link( link_id => $link_id );

    $results->{'results'} = [];

    if ( !defined $output ) {
        $results->{'error'} = $db->get_error();
    }
    else {
        $results->{'results'} = [ { success => 1 } ];
    }

    return $results;
}

sub add_remote_link {
    my $results;

    my $urn                = $cgi->param('urn');
    my $name               = $cgi->param('name');
    my $local_interface_id = $cgi->param('interface_id');
    my $vlan_tag_range     = $cgi->param('vlan_tag_range');
    
    warn "add_remote_link: ".$vlan_tag_range;
    my $output = $db->add_remote_link(
        urn                => $urn,
        name               => $name,
        local_interface_id => $local_interface_id,
        vlan_tag_range     => $vlan_tag_range
        );

    $results->{'results'} = [];
    if ( !defined $output ) {
        $results->{'error'} = $db->get_error();
    }
    else {
        $results->{'results'} = [ { "success" => 1 } ];
    }

    return $results;
}

sub edit_remote_link {
    my $results;
    
    my $urn                = $cgi->param('urn');
    my $name               = $cgi->param('name');
    my $vlan_tag_range     = $cgi->param('vlan_tag_range');
    my $link_id            = $cgi->param('link_id');
    warn "updating_remote_link: ".$vlan_tag_range;
    my $output = $db->edit_remote_link(
        link_id            => $link_id,
        urn                => $urn,
        name               => $name,
        vlan_tag_range     => $vlan_tag_range
        );

    $results->{'results'} = [];
    if ( !defined $output ) {
        $results->{'error'} = $db->get_error();
    }
    else {
        $results->{'results'} = [ { "success" => 1 } ];
    }

    return $results;

}

sub get_workgroups {

    my %parameters = ( 'user_id' => $cgi->param('user_id') || undef );

    my $results;
    my $workgroups;

    $workgroups = $db->get_workgroups(%parameters);

    if ( !defined $workgroups ) {
        $results->{'error'}   = $db->get_error();
        $results->{'results'} = [];
    }
    else {
        $results->{'results'} = $workgroups;
    }

    return $results;
}

sub update_interface_owner {
    my $results;

    my $interface_id = $cgi->param('interface_id');
    my $workgroup_id = $cgi->param('workgroup_id');

    my $success = $db->update_interface_owner(
        interface_id => $interface_id,
        workgroup_id => $workgroup_id
        );

    if ( !defined $success ) {
        $results->{'error'}   = $db->get_error();
        $results->{'results'} = [];
    }
    else {
        $results->{'results'} = [ { success => 1 } ];
    }

    return $results;
}

sub add_workgroup {
    my $results;

    my $name        = $cgi->param("name");
    my $external_id = $cgi->param('external_id');
    my $type        = $cgi->param('type');
    my $new_wg_id =
        $db->add_workgroup( name => $name, external_id => $external_id , type => $type);

    if ( !defined $new_wg_id ) {
        $results->{'error'} = $db->get_error();
        $results->{'results'} = [ { success => 0 } ];
    }
    else {
        $results->{'results'} =
            [ { success => 1, workgroup_id => $new_wg_id } ];
    }

    return $results;
}

sub get_users {
    my $results;

    my $users = $db->get_users();

    if ( !defined $users ) {
        $results->{'error'} = $db->get_error();
    }
    else {
        $results->{'results'} = $users;
    }

    return $results;
}

sub get_users_in_workgroup {
    my $results;

    my $workgroup_id = $cgi->param('workgroup_id');

    my $users = $db->get_users_in_workgroup( workgroup_id => $workgroup_id );

    if ( !defined $users ) {
        $results->{'error'}   = $db->get_error();
        $results->{'results'} = [];
    }
    else {
        $results->{'results'} = $users;
    }

    return $results;
}

sub add_user_to_workgroup {
    my $results;

    my $user_id = $cgi->param('user_id');
    my $wg_id   = $cgi->param('workgroup_id');
    my $result = $db->add_user_to_workgroup(
        user_id      => $user_id,
        workgroup_id => $wg_id
        );

    if ( !defined $result ) {
        $results->{'error'}   = $db->get_error();
        $results->{'results'} = [];
    }
    else {
        $results->{'results'} = [ { success => 1 } ];
    }

    return $results;
}

sub remove_user_from_workgroup {
    my $results;

    my $user_id = $cgi->param('user_id');
    my $wg_id   = $cgi->param('workgroup_id');

    my $result = $db->remove_user_from_workgroup(
        user_id      => $user_id,
        workgroup_id => $wg_id
        );

    if ( !defined $result ) {
        $results->{'error'}   = $db->get_error();
        $results->{'results'} = [];
    }
    else {
        $results->{'results'} = [ { success => 1 } ];
    }

    return $results;
}

sub add_user {
    my $results;

    my $given_name  = $cgi->param("first_name");
    my $family_name = $cgi->param("family_name");
    my $email       = $cgi->param("email_address");
    my @auth_names  = $cgi->param("auth_name");
    my $type        = $cgi->param("type");
    my $status      = $cgi->param("status");
    my $new_user_id = $db->add_user(
        given_name    => $given_name,
        family_name   => $family_name,
        email_address => $email,
        auth_names    => \@auth_names,
        type          => $type,
        status        => $status
        );

    if ( !defined $new_user_id ) {
        $results->{'error'} = $db->get_error();
        $results->{'results'} = [ { success => 0 } ];
    }
    else {
        $results->{'results'} = [ { success => 1, user_id => $new_user_id } ];
    }

    return $results;
}

sub delete_user {
    my $results;

    my $user_id = $cgi->param('user_id');

    my $output = $db->delete_user( user_id => $user_id );

    if ( !defined $output ) {
        $results->{'error'} = $db->get_error();
        $results->{'results'} = [ { success => 0 } ];
    }
    else {
        $results->{'results'} = [ { success => 1 } ];
    }

    return $results;
}

sub edit_user {
    my $results;

    my $user_id     = $cgi->param("user_id");
    my $given_name  = $cgi->param("first_name");
    my $family_name = $cgi->param("family_name");
    my $email       = $cgi->param("email_address");
    my @auth_names  = $cgi->param("auth_name");
    my $type        = $cgi->param('type');
    my $status      = $cgi->param('status');

    my $success = $db->edit_user(
        given_name    => $given_name,
        family_name   => $family_name,
        email_address => $email,
        auth_names    => \@auth_names,
        user_id       => $user_id,
        type          => $type,
        status        => $status
        );

    if ( !defined $success ) {
        $results->{'error'} = $db->get_error();
        $results->{'results'} = [ { success => 0 } ];
    }
    else {
        $results->{'results'} = [ { success => 1 } ];
    }

    return $results;
}

sub get_edge_interface_move_maintenances {
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 1);
    if (defined $err) {
        return send_json($err);
    }

    my $results;
    my $maints = $db->get_edge_interface_move_maintenances();

    if ( !defined $maints ) {
        $results->{'error'} = $db->get_error();
    }else {
        $results->{'results'} = $maints;
    }

    return $results;
}

sub add_edge_interface_move_maintenance {
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }
    
    my $results = { 'results' => [] };
    my $name               = ($args->{"name"}{'value'} eq '') ? undef : $args->{"name"}{'value'};
    my $orig_interface_id  = $args->{"orig_interface_id"}{'value'};
    my $temp_interface_id  = $args->{"temp_interface_id"}{'value'};
    my @circuit_ids        = $args->{"circuit_id"}{'value'};

    my $res = $db->add_edge_interface_move_maintenance(
        name => $name,
        orig_interface_id => $orig_interface_id,
        temp_interface_id => $temp_interface_id,
        circuit_ids       => (@circuit_ids > 0) ? \@circuit_ids : undef
        );

    if ( !defined $res ) {
        $results->{'error'}   = $db->get_error();
        return $results;
    }
    $results->{'results'} = [$res];

    # now diff node
    if(!_update_cache_and_sync_node($res->{'dpid'})){
        $results->{'error'}   = "Issue diffing node";
    }

    return $results;
}

sub revert_edge_interface_move_maintenance {
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $results = { 'results' => [] };
    my $maintenance_id  = $args->{"maintenance_id"}{'value'};

    my $res = $db->revert_edge_interface_move_maintenance(
        maintenance_id => $maintenance_id
        );
    if ( !defined $res ) {
        $results->{'error'}   = $db->get_error();
        return $results;
    }
    $results->{'results'} = [$res];

    # now diff node
    if(!_update_cache_and_sync_node($res->{'dpid'})){
        $results->{'error'}   = "Issue diffing node";
    }

    return $results;
}

sub move_edge_interface_circuits {
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $results = { 'results' => [] };
    my $orig_interface_id  = $args->{"orig_interface_id"}{'value'};
    my $new_interface_id   = $args->{"new_interface_id"}{'value'};
    my @circuit_ids        = $args->{"circuit_id"}{'value'};

    my $res = $db->move_edge_interface_circuits(
        orig_interface_id => $orig_interface_id,
        new_interface_id  => $new_interface_id,
        circuit_ids       => (@circuit_ids > 0) ? \@circuit_ids : undef
        );
    if ( !defined $res ) {
        $results->{'error'}   = $db->get_error();
    }
    $results->{'results'} = [$res];

    # now diff node
    if(!_update_cache_and_sync_node($res->{'dpid'})){
        $results->{'error'}   = "Issue diffing node";
    }

    return $results;
}

sub get_pending_nodes {
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 1);
    if (defined $err) {
        return send_json($err);
    }

    my $results;

    my $nodes = $db->get_pending_nodes();

    if ( !defined $nodes ) {
        $results->{'error'} = $db->get_error();
    }
    else {
        $results->{'results'} = $nodes;
    }

    return $results;
}

sub confirm_node {
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $results;

    my $node_id         = $args->{'node_id'}{'value'};
    my $name            = $args->{'name'}{'value'};
    my $long            = $args->{'longitude'}{'value'};
    my $lat             = $args->{'latitude'}{'value'};
    my $range           = $args->{'vlan_range'}{'value'};
    my $default_drop    = $args->{'default_drop'}{'value'};
    my $default_forward = $args->{'default_forward'}{'value'};
    my $tx_delay_ms     = $args->{'tx_delay_ms'}{'value'};
    my $max_flows       = $args->{'max_flows'}{'value'};
    my $bulk_barrier    = $args->{'bulk_barrier'}{'value'};

    if ( $default_drop eq 'true' ) {
        $default_drop = 1;
    }
    else {
        $default_drop = 0;
    }

    if ( $default_forward eq 'true' ) {
        $default_forward = 1;
    }
    else {
        $default_forward = 0;
    }

    if($bulk_barrier eq 'true'){
        $bulk_barrier = 1;
    }else{
        $bulk_barrier = 0;
    }

    my $result = $db->confirm_node(
        node_id         => $node_id,
        name            => $name,
        longitude       => $long,
        latitude        => $lat,
        vlan_range      => $range,
        default_forward => $default_forward,
        default_drop    => $default_drop,
        tx_delay_ms     => $tx_delay_ms,
        max_flows       => $max_flows,
        bulk_barrier    => $bulk_barrier
        );

    if ( !defined $result ) {
        $results->{'results'} = [
            {
                "error"   => $db->get_error(),
                "success" => 0
            }
            ];
    }
    else {
        $results->{'results'} = [ { "success" => 1 } ];
    }

    my $node = $db->get_node_by_id( node_id => $node_id);

    my $client  = new GRNOC::RabbitMQ::Client(
                                              topic => 'OF.FWDCTL.RPC',
                                              exchange => 'OESS',
                                              user => 'guest',
                                              pass => 'guest',
                                              host => 'localhost',
                                              port => 5672,
                                              timeout => 15
        );
    if (!defined $client) {
        $results->{'results'} = [ {
                                   "error"   => "Internal server error occurred. Message queue connection failed.",
                                   "success" => 0
                                  }
                                ];
        return $results;
    }

    my $cache_result = $client->update_cache(circuit_id => -1);
    warn Data::Dumper::Dumper($cache_result);
    
    if($cache_result->{'error'} || !$cache_result->{'results'}->{'event_id'}){
        $results->{'results'} = [ {
                                   "error"   => "Cache result error: $cache_result->{'error'}.",
                                   "success" => 0
                                  }
                                ];
        return $results;
    }

    my $event_id  = $cache_result->{'results'}->{'event_id'};
    my $final_res = FWDCTL_WAITING;

    while ($final_res == FWDCTL_WAITING) {
        sleep(1);
        $final_res = $client->get_event_status(event_id => $event_id)->{'results'}->{'status'};
    }

    $cache_result = $client->force_sync(dpid => int($node->{'dpid'}));
    if($cache_result->{'error'} || !$cache_result->{'results'}->{'event_id'}){
        $results->{'results'} = [ {
                                   "error"   => "Failure occurred in force_sync against dpid: $node->{'dpid'}",
                                   "success" => 0
                                  }
                                ];
        return $results;
    }

    $event_id = $cache_result->{'results'}->{'event_id'};

    $final_res = FWDCTL_WAITING;
    
    while($final_res == FWDCTL_WAITING){
        sleep(1);
        $final_res = $client->get_event_status(event_id => $event_id)->{'results'}->{'status'};
    }


    return {results => [{success => $final_res}]};
}

sub update_node {
    my $results;

    my $node_id         = $cgi->param('node_id');
    my $name            = $cgi->param('name');
    my $long            = $cgi->param('longitude');
    my $lat             = $cgi->param('latitude');
    my $range           = $cgi->param('vlan_range');
    my $default_drop    = $cgi->param('default_drop');
    my $default_forward = $cgi->param('default_forward');
    my $max_flows       = $cgi->param('max_flows') || 0;
    my $tx_delay_ms     = $cgi->param('tx_delay_ms') || 0;
    my $bulk_barrier    = $cgi->param('bulk_barrier') || 0;
    my $max_static_mac_flows = $cgi->param('max_static_mac_flows') || 0;

    if ( $default_drop eq 'true' ) {
        $default_drop = 1;
    }
    else {
        $default_drop = 0;
    }

    if ( $default_forward eq 'true' ) {
        $default_forward = 1;
    }
    else {
        $default_forward = 0;
    }

    if($bulk_barrier eq 'true'){
        $bulk_barrier = 1;
    }else{
        $bulk_barrier = 0;
    }

    my $result = $db->update_node(
        node_id         => $node_id,
        name            => $name,
        longitude       => $long,
        latitude        => $lat,
        vlan_range      => $range,
        default_forward => $default_forward,
        default_drop    => $default_drop,
        tx_delay_ms     => $tx_delay_ms,
        max_flows       => $max_flows,
        bulk_barrier    => $bulk_barrier,
        max_static_mac_flows => $max_static_mac_flows
        );

    if ( !defined $result ) {
        $results->{'results'} = [
            {
                "error"   => $db->get_error(),
                "success" => 0
            }
            ];
    }
    else {
        $results->{'results'} = [ { "success" => 1 } ];
    }

    my $client  = new GRNOC::RabbitMQ::Client(
        topic => 'OF.FWDCTL.RPC',
        exchange => 'OESS',
        user => 'guest',
        pass => 'guest',
        host => 'localhost',
        port => 5672
        );

    if ( !defined($client) ) {
        return;
    }

    my $node = $db->get_node_by_id(node_id => $node_id);

    my $cache_result = $client->update_cache(circuit_id => -1);

    if($cache_result->{'error'} || !$cache_result->{'results'}->{'event_id'}){
        return;
    }

    my $event_id = $cache_result->{'results'}->{'event_id'};

    my $final_res = FWDCTL_WAITING;

    while($final_res == FWDCTL_WAITING){
        sleep(1);
        $final_res = $client->get_event_status(event_id => $event_id)->{'results'}->{'status'};
    }

    $cache_result = $client->force_sync(dpid => $node->{'dpid'});

    if($cache_result->{'error'} || !$cache_result->{'results'}->{'event_id'}){
        return;
    }

    $event_id = $cache_result->{'results'}->{'event_id'};

    $final_res = FWDCTL_WAITING;

    while($final_res == FWDCTL_WAITING){
        sleep(1);
        $final_res = $client->get_event_status(event_id => $event_id)->{'results'}->{'status'};
    }

    return {results => [{success => $final_res}]};
}


sub update_interface {
    my $results;
    my $interface_id= $cgi->param('interface_id');
    my $description= $cgi->param('description');
    my $vlan_tags = $cgi->param('vlan_tag_range');

    my $result = $db->update_interface_description( 'interface_id' => $interface_id,
                                                    'description'  => $description );

    my $result2 = $db->update_interface_vlan_range( 'vlan_tag_range' => $vlan_tags,
                                                    'interface_id'   => $interface_id );

    if ( !defined $result || !defined($result2) ) {
        $results->{'results'} = [
            {
                "error"   => $db->get_error(),
                "success" => 0
            }
            ];
    }
    else {
        $results->{'results'} = [ { "success" => 1 } ];
    }

    return $results;

}

sub decom_node {
    my $results;

    my $node_id = $cgi->param('node_id');

    my $result = $db->decom_node( node_id => $node_id );

    if ( !defined $result ) {
        $results->{'results'} = [
            {
                "error"   => $db->get_error(),
                "success" => 0
            }
            ];
    }
    else {
        $results->{'results'} = [ { "success" => 1 } ];
    }

    my $client  = new GRNOC::RabbitMQ::Client(
        topic => 'OF.FWDCTL.RPC',
        exchange => 'OESS',
        user => 'guest',
        pass => 'guest',
        host => 'localhost',
        port => 5672
    );

    if ( !defined($client) ) {
        return;
    }
    
    my $cache_result = $client->update_cache(circuit_id => -1);

    if($cache_result->{'error'} || !$cache_result->{'results'}->{'event_id'}){
        return;
    }

    my $event_id = $cache_result->{'results'}->{'event_id'};

    my $final_res = FWDCTL_WAITING;

    while($final_res == FWDCTL_WAITING){
        sleep(1);
        $final_res = $client->get_event_status(event_id => $event_id)->{'results'}->{'status'};
    }


    return $results;

}

sub confirm_link {
    my $results;

    my $link_id = $cgi->param('link_id');
    my $name    = $cgi->param('name');

    my $result = $db->confirm_link(
        link_id => $link_id,
        name    => $name,
        );

    if ( !defined $result ) {
        $results->{'results'} = [
            {
                "error"   => $db->get_error(),
                "success" => 0
            }
            ];
    }
    else {
        $results->{'results'} = [ { "success" => 1 } ];
    }

    return $results;
}

sub update_link {
    my $results;

    my $link_id = $cgi->param('link_id');
    my $name    = $cgi->param('name');
    my $metric  = $cgi->param('metric') || 1;

    my $result = $db->update_link(
        link_id => $link_id,
        name    => $name,
        metric  => $metric
        );

    if ( !defined $result ) {
        $results->{'results'} = [
            {
                "error"   => $db->get_error(),
                "success" => 0
            }
            ];
    }
    else {
        $results->{'results'} = [ { "success" => 1 } ];
    }

    return $results;
}

sub deny_device {
    my $results;
    my $node_id = $cgi->param('node_id');
    my $ipv4_addr = $cgi->param('ipv4_addr');
    my $dpid = $cgi->param('dpid');

    my $result = $db->decom_node(node_id => $node_id);

    if ( !defined $result ) {
        $results->{'results'} = [
            {
                "error"   => $db->get_error(),
                "success" => 0
            }
            ];
    }
    else {
        $results->{'results'} = [ { "success" => 1 } ];
    }
    $result = $db->create_node_instance(node_id => $node_id,ipv4_addr => $ipv4_addr,admin_state => "decom", dpid => $dpid);

    if ( !defined $result ) {
        $results->{'results'} = [
            {
                "error"   => $db->get_error(),
                "success" => 0
            }
            ];
    }
    else {
        $results->{'results'} = [ { "success" => 1 } ];
    }

    return $results;
}

sub deny_link {
    my $results;

    my $link_id = $cgi->param('link_id');
    my $int_a_id = $cgi->param('interface_a_id');
    my $int_z_id = $cgi->param('interface_z_id');
    my $result = $db->decom_link_instantiation( link_id => $link_id );
    
    if ( !defined $result ) {
        $results->{'results'} = [
            {
                "error"   => $db->get_error(),
                "success" => 0
            }
            ];
    }
    else {
        $results->{'results'} = [ { "success" => 1 } ];
    }

    $result = $db->create_link_instantiation( link_id => $link_id, interface_a_id => $int_a_id, interface_z_id => $int_z_id, state => "decom" );

    if ( !defined $result ) {
        $results->{'results'} = [
            {
                "error"   => $db->get_error(),
                "success" => 0
            }
            ];
    }
    else {
        $results->{'results'} = [ { "success" => 1 } ];
    }

    return $results;
}

sub decom_link {
    my $results;

    my $link_id = $cgi->param('link_id');

    my $result = $db->decom_link( link_id => $link_id );

    if ( !defined $result ) {
        $results->{'results'} = [
            {
                "error"   => $db->get_error(),
                "success" => 0
            }
            ];
    }
    else {
        $results->{'results'} = [ { "success" => 1 } ];
    }

    return $results;
}

sub get_pending_links {
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 1);
    if (defined $err) {
        return send_json($err);
    }

    my $results;

    my $links = $db->get_pending_links();

    if ( !defined $links ) {
        $results->{'error'} = $db->get_error();
    }
    else {
        $results->{'results'} = $links;
    }

    return $results;
}

sub gen_topology{
    my $topo = $db->gen_topo();
    my $results;

    if(!$topo){
        $results->{'results'} = [];
        $results->{'error'} = 1;
        $results->{'error_text'} = $db->get_error();
    }
    else{
        $results->{'results'} = [{'topo' => $topo}];
    }
    return $results;
}

sub edit_workgroup{
    
    my $workgroup_id = $cgi->param('workgroup_id');
    my $workgroup_name = $cgi->param('name');
    my $external_id = $cgi->param('external_id');
    my $max_circuits = $cgi->param('max_circuits');
    my $max_circuit_endpoints = $cgi->param('max_circuit_endpoints');
    my $max_mac_address_per_end = $cgi->param('max_mac_address_per_end');

    my $res = $db->update_workgroup( 
        workgroup_id => $workgroup_id,
		name => $workgroup_name,
	    external_id => $external_id,
	    max_circuits => $max_circuits,
	    max_circuit_endpoints => $max_circuit_endpoints,
	    max_mac_address_per_end => $max_mac_address_per_end
        );

    my $results;
    if(defined($res)){
        $results->{'results'} = [{success => 1}];
    }else{
        $results->{'error'} = $db->get_error();
    }
    return $results;
}

sub decom_workgroup{
    my $workgroup_id = $cgi->param('workgroup_id');
    my $results;

    my $circuits = $db->get_circui
}

sub update_remote_device{
    my $node_id = $cgi->param('node_id');
    my $latitude = $cgi->param('latitude');
    my $longitude = $cgi->param('longitude');

    my $res = $db->update_remote_device(node_id => $node_id, lat => $latitude, lon => $longitude);
    
    return {results => $res};
}

sub send_json {
    my $output = shift;
    if (!defined($output) || !$output) {
        $output =  { "error" => "Server error in accessing webservices." };
    }
    print "Content-type: text/plain\n\n" . encode_json($output);
}

sub _update_cache_and_sync_node {
    my $dpid = shift;    

    my $client  = new GRNOC::RabbitMQ::Client(
        topic => 'OF.FWDCTL.RPC',
        exchange => 'OESS',
        user => 'guest',
        pass => 'guest',
        host => 'localhost',
        port => 5672
    );

    if ( !defined($client) ) {
        return;
    }

    # first update fwdctl's cache
    my $result = $client->update_cache(circuit_id => -1);

    if($result->{'error'} || !$result->{'results'}->{'event_id'}){
        return;
    }

    my $event_id = $result->{'results'}->{'event_id'};

    my $final_res = FWDCTL_WAITING;
    while($final_res == FWDCTL_WAITING){
        sleep(1);
        $final_res = $client->get_event_status(event_id => $event_id)->{'results'}->{'status'};
    }
    # now sync the node
    $result = $client->force_sync(dpid => int($dpid));

    if($result->{'error'} || !$result->{'results'}->{'event_id'}){
        return;
    }

    $event_id = $result->{'results'}->{'event_id'};

    $final_res = FWDCTL_WAITING;
    while($final_res == FWDCTL_WAITING){
        sleep(1);
        $final_res = $client->get_event_status(event_id => $event_id)->{'results'}->{'status'};
    }

    return 1;
}

main();
