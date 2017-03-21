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

my $svc = GRNOC::WebService::Dispatcher->new();

$| = 1;


=head2 authorization

Checks if the $REMOTE_USER should be authorized. If any authorization
check fails an error will be returned. Returns a user whenever possible.
Caller should check if error is defined to determine if authorization
has failed.

=over 1

=item $admin     If set to 1 authorization will be granted to admin users only

=item $read_only If set to 1 authorization will be granted to read only users

=back

Returns a ($user, $error) tuple.

=cut
sub authorization {
    my %params    = @_;
    my $admin     = $params{'admin'};
    my $read_only = $params{'read_only'};

    my $username  = $ENV{'REMOTE_USER'};

    my $auth = $db->get_user_admin_status( 'username' => $username);
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

    if ($admin == 1 && $auth->[0]{'is_admin'} != 1) {
        return ($user, { error => "User $username does not have admin privileges." });
    }
    
    if ($read_only != 1 && $user->{'type'} eq 'read-only') {
        return ($user, { error => "User $username is a read only user." });
    }

    return ($user, undef);
}

sub main {
    if (!$db) {
        send_json({ error => "Unable to connect to database." });
        exit(1);
    }
    
    register_webservice_methods();
    return $svc->handle_request();
}

sub register_webservice_methods {
    my $method = undef;

    $method = GRNOC::WebService::Method->new( name        => 'add_edge_interface_move_maintenances',
                                              description => 'Creates a list interface maintenances.',
                                              callback    => sub { add_edge_interface_move_maintenances(@_) } );
    $method->add_input_parameter( name        => 'name',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => 'Name of the new maintenance.' );
    $method->add_input_parameter( name        => 'orig_interface_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => 'Interface ID of the original interface.');
    $method->add_input_parameter( name        => 'temp_interface_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => 'Interface ID of the temporary interface.');    
    $method->add_input_parameter( name        => 'circuit_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 0,
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
                                  required    => 0,
                                  description => 'Maintenance ID of the maintenance to revert.');
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'move_edge_interface_circuits',
                                              description => "Moves an interface's circuits.",
                                              callback    => sub { move_edge_interface_circuits(@_) } );
    $method->add_input_parameter( name        => 'orig_interface_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => 'Interface ID of the original interface.');
    $method->add_input_parameter( name        => 'new_interface_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => 'Interface ID of the temporary interface.');    
    $method->add_input_parameter( name        => 'circuit_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 0,
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
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'name',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'longitude',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'latitude',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'vlan_range',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'default_drop',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'default_forward',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'tx_delay_ms',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'max_flows',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'bulk_barrier',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'update_node',
                                              description => "Updates a node.",
                                              callback    => sub { update_node(@_) } );
    $method->add_input_parameter( name        => 'node_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'name',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'longitude',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'latitude',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'vlan_range',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'default_drop',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'default_forward',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'tx_delay_ms',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'max_flows',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'bulk_barrier',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'max_static_mac_flows',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'openflow',
				  pattern     => $GRNOC::WebService::Regex::TEXT,
				  required    => 1,
				  description => "if openflow is enabled or not (0|1)");    
    $method->add_input_parameter( name        => 'mpls',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
				  description => "if mpls is enabled or not (0|1)");
    $method->add_input_parameter( name        => 'mgmt_addr',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
				  description => "IP address of node node_id");
    $method->add_input_parameter( name        => 'tcp_port',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 0,
				  description => "TCP port of node node_id");
    $method->add_input_parameter( name        => 'vendor',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
				  description => "Hardware vendor of node node_id");
    $method->add_input_parameter( name        => 'model',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
				  description => "Hardware model of node node_id");
    $method->add_input_parameter( name        => 'sw_version',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
				  description => "Software version of node node_id");
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'update_interface',
                                              description => "Updates an interface.",
                                              callback    => sub { update_interface(@_) } );
    $method->add_input_parameter( name        => 'interface_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'description',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'vlan_tag_range',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'mpls_vlan_tag_range',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'decom_node',
                                              description => 'Decommissions a node.',
                                              callback    => sub { decom_node(@_) } );
    $method->add_input_parameter( name        => 'node_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'confirm_link',
                                              description => "Approves a link.",
                                              callback    => sub { confirm_link(@_) } );
    $method->add_input_parameter( name        => 'link_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'name',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'update_link',
                                              description => "Updates a link.",
                                              callback    => sub { update_link(@_) } );
    $method->add_input_parameter( name        => 'link_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'name',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'metric',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'is_new_node_in_path',
                                              description => '',
                                              callback    => sub { is_new_node_in_path(@_) } );
    $method->add_input_parameter( name        => 'link',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'insert_node_in_path',
                                              description => '',
                                              callback    => sub { insert_node_in_path(@_) } );
    $method->add_input_parameter( name        => 'link_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'is_ok_to_decom_link',
                                              description => '',
                                              callback    => sub { is_ok_to_decom(@_) } );
    $method->add_input_parameter( name        => 'link_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'deny_device',
                                              description => '',
                                              callback    => sub { deny_device(@_) } );
    $method->add_input_parameter( name        => 'node_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'ipv4_addr',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'dpid',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'deny_link',
                                              description => '',
                                              callback    => sub { deny_link(@_) } );
    $method->add_input_parameter( name        => 'link_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'interface_a_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'interface_z_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 0,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'decom_link',
                                              description => '',
                                              callback    => sub { decom_link(@_) } );
    $method->add_input_parameter( name        => 'link_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'get_users',
                                              description => '',
                                              callback    => sub { get_users(@_) } );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'get_users_in_workgroup',
                                              description => '',
                                              callback    => sub { get_users_in_workgroup(@_) } );
    $method->add_input_parameter( name        => 'workgroup_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 0,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'add_user',
                                              description => '',
                                              callback    => sub { add_user(@_) } );
    $method->add_input_parameter( name        => 'first_name',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'family_name',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'email_address',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'auth_name',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'type',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'status',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'delete_user',
                                              description => '',
                                              callback    => sub { delete_user(@_) } );
    $method->add_input_parameter( name        => 'user_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'add_user_to_workgroup',
                                              description => '',
                                              callback    => sub { add_user_to_workgroup(@_) } );
    $method->add_input_parameter( name        => 'user_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'workgroup_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 0,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'remove_user_from_workgroup',
                                              description => '',
                                              callback    => sub { remove_user_from_workgroup(@_) } );
    $method->add_input_parameter( name        => 'user_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'workgroup_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 0,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'edit_user',
                                              description => '',
                                              callback    => sub { edit_user(@_) } );
    $method->add_input_parameter( name        => 'user_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'first_name',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'family_name',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'email_address',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'auth_name',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'type',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'status',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'get_workgroups',
                                              description => '',
                                              callback    => sub { get_workgroups(@_) } );
    $method->add_input_parameter( name        => 'user_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 0,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'update_interface_owner',
                                              description => '',
                                              callback    => sub { update_interface_owner(@_) } );
    $method->add_input_parameter( name        => 'workgroup_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'interface_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'add_workgroup',
                                              description => '',
                                              callback    => sub { add_workgroup(@_) } );
    $method->add_input_parameter( name        => 'name',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'external_id',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'type',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'add_remote_link',
                                              description => '',
                                              callback    => sub { add_remote_link(@_) } );
    $method->add_input_parameter( name        => 'urn',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'name',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'interface_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'vlan_tag_range',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'edit_remote_link',
                                              description => '',
                                              callback    => sub { edit_remote_link(@_) } );
    $method->add_input_parameter( name        => 'link_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'urn',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'name',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'interface_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'vlan_tag_range',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'remove_remote_link',
                                              description => '',
                                              callback    => sub { remove_remote_link(@_) } );
    $method->add_input_parameter( name        => 'link_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'get_remote_links',
                                              description => '',
                                              callback    => sub { get_remote_links(@_) } );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'submit_topology',
                                              description => '',
                                              callback    => sub { submit_topology(@_) } );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'get_remote_devices',
                                              description => '',
                                              callback    => sub { get_remote_devices(@_) } );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'update_remote_device',
                                              description => '',
                                              callback    => sub { update_remote_device(@_) } );
    $method->add_input_parameter( name        => 'node_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'latitude',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'longitude',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'get_circuits_on_interface',
                                              description => '',
                                              callback    => sub { get_circuits_on_interface(@_) } );
    $method->add_input_parameter( name        => 'interface_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'edit_workgroup',
                                              description => '',
                                              callback    => sub { edit_workgroup(@_) } );
    $method->add_input_parameter( name        => 'workgroup_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'name',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'external_id',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'max_circuits',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'max_circuit_endpoints',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'max_mac_address_per_end',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 0,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'get_topology',
                                              description => '',
                                              callback    => sub { gen_topology(@_) } );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'decom_workgroup',
                                              description => '',
                                              callback    => sub { decom_workgroup(@_) } );
    $method->add_input_parameter( name        => 'workgroup_id',
                                  pattern     => $GRNOC::WebService::Regex::INTEGER,
                                  required    => 1,
                                  description => '' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new( name        => 'add_mpls_switch',
                                              description => '',
                                              callback    => sub { add_mpls_switch(@_) } );
    $method->add_input_parameter( name        => 'ip_address',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'name',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'longitude',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'latitude',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'port',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'vendor',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'model',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'sw_ver',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
				  description => '' );

    $svc->register_method($method);
}

sub get_circuits_on_interface{
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 1);
    if (defined $err) {
        return send_json($err);
    }

    my $results;

    my $link = $db->get_link_by_interface_id( interface_id => $args->{'interface_id'}{'value'},
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
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $results = $db->insert_node_in_path( link => $args->{'link_id'}{'value'} );

    return {results =>  => [$results]};
    
}

sub is_new_node_in_path{
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $results;

    $results->{'results'} = [];

    $results->{'results'}->[0] = $db->is_new_node_in_path(link => $args->{'link'}{'value'});
    return $results;
}

sub is_ok_to_decom{
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $results;
    $results->{'results'} = [];

    my $link_details = $db->get_link( link_id => $args->{'link_id'}{'value'} );

    my $circuits = $db->get_circuits_on_link( link_id => $link_details->{'link_id'} );
    $results->{'results'}->[0]->{'active_circuits'} = $circuits;



    $results->{'results'}->[0]->{'new_node_in_path'} = $db->is_new_node_in_path(link => $link_details);

    return $results;

}

sub get_remote_devices {
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 1);
    if (defined $err) {
        return send_json($err);
    }

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
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

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
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 1);
    if (defined $err) {
        return send_json($err);
    }

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
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $results;

    my $link_id = $args->{'link_id'}{'value'};

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
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $results;

    my $urn                = $args->{'urn'}{'value'};
    my $name               = $args->{'name'}{'value'};
    my $local_interface_id = $args->{'interface_id'}{'value'};
    my $vlan_tag_range     = $args->{'vlan_tag_range'}{'value'};
    
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
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $results;
    
    my $urn                = $args->{'urn'}{'value'};
    my $name               = $args->{'name'}{'value'};
    my $vlan_tag_range     = $args->{'vlan_tag_range'}{'value'};
    my $link_id            = $args->{'link_id'}{'value'};
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
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 1);
    if (defined $err) {
        return send_json($err);
    }

    my %parameters = ( 'user_id' => $args->{'user_id'}{'value'} || undef );

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
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $results;

    my $interface_id = $args->{'interface_id'}{'value'};
    my $workgroup_id = $args->{'workgroup_id'}{'value'};

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
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }
    my $results;

    my $name        = $args->{"name"}{'value'};
    my $external_id = $args->{'external_id'}{'value'};
    my $type        = $args->{'type'}{'value'};
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
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 0, read_only => 1);
    if (defined $err) {
        return send_json($err);
    }

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
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 0, read_only => 1);
    if (defined $err) {
        return send_json($err);
    }

    my $results;

    my $workgroup_id = $args->{'workgroup_id'}{'value'};

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
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $results;

    my $user_id = $args->{'user_id'}{'value'};
    my $wg_id   = $args->{'workgroup_id'}{'value'};
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
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $results;

    my $user_id = $args->{'user_id'}{'value'};
    my $wg_id   = $args->{'workgroup_id'}{'value'};

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
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $results;

    my $given_name  = $args->{"first_name"}{'value'};
    my $family_name = $args->{"family_name"}{'value'};
    my $email       = $args->{"email_address"}{'value'};
    my @auth_names  = $args->{"auth_name"}{'value'};
    my $type        = $args->{"type"}{'value'};
    my $status      = $args->{"status"}{'value'};
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
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $results;

    my $user_id = $args->{'user_id'}{'value'};

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
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $results;

    my $user_id     = $args->{"user_id"}{'value'};
    my $given_name  = $args->{"first_name"}{'value'};
    my $family_name = $args->{"family_name"}{'value'};
    my $email       = $args->{"email_address"}{'value'};
    my @auth_names  = $args->{"auth_name"}{'value'};
    my $type        = $args->{'type'}{'value'};
    my $status      = $args->{'status'}{'value'};

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

    my $cv = AnyEvent->condvar;
    $client->update_cache(circuit_id     => -1,
                          async_callback => sub {
                              my $result = shift;
                              $cv->send($result);
                          });

    my $cache_result = $cv->recv();

    warn Data::Dumper::Dumper($cache_result);

    if ($cache_result->{'error'} || !$cache_result->{'results'}) {
        return { results => [ {
                               "error"   => "Cache result error: $cache_result->{'error'}.",
                               "success" => 0
                              }
                            ] };
    }

    $cv = AnyEvent->condvar;
    $client->force_sync(dpid => int($node->{'dpid'}),
                        async_callback => sub {
                            my $result = shift;
                            $cv->send($result);
                        });

    $cache_result = $cv->recv();

    if ($cache_result->{'error'} || !$cache_result->{'results'}) {
        return { results => [ {
                               "error"   => "Failure occurred in force_sync against dpid: $node->{'dpid'}",
                               "success" => 0
                              }
                            ] };
    }

    return {results => [{success => 1}]};
}

sub update_node {
    my ($method, $args) = @_;
    warn 'update_node: entering function';

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $results;

    my $node_id = $args->{'node_id'}{'value'};
    my $name    = $args->{'name'}{'value'};
    my $long    = $args->{'longitude'}{'value'};
    my $lat     = $args->{'latitude'}{'value'};
    my $range   = $args->{'vlan_range'}{'value'};

    my $openflow        = $args->{'openflow'}{'value'};
    my $bulk_barrier    = $args->{'bulk_barrier'}{'value'} || 0;
    my $default_drop    = $args->{'default_drop'}{'value'};
    my $default_forward = $args->{'default_forward'}{'value'};
    my $max_flows       = $args->{'max_flows'}{'value'} || 0;
    my $max_static_mac_flows = $args->{'max_static_mac_flows'}{'value'} || 0;
    my $tx_delay_ms     = $args->{'tx_delay_ms'}{'value'} || 0;

    my $mpls       = $args->{'mpls'}{'value'};
    my $mgmt_addr  = $args->{'mgmt_addr'}{'value'};
    my $model      = $args->{'model'}{'value'};
    my $sw_version = $args->{'sw_version'}{'value'};
    my $tcp_port   = $args->{'tcp_port'}{'value'};
    my $vendor     = $args->{'vendor'}{'value'};

    if ($default_drop eq 'true') {
        $default_drop = 1;
    } else {
        $default_drop = 0;
    }

    if ($default_forward eq 'true') {
        $default_forward = 1;
    } else {
        $default_forward = 0;
    }

    if ($bulk_barrier eq 'true') {
        $bulk_barrier = 1;
    } else {
        $bulk_barrier = 0;
    }

    if ($openflow eq 'true') {
	$openflow = 1;
    } else {
	$openflow = 0;
    }

    if ($mpls eq 'true') {
	$mpls = 1;
    } else {
	$mpls = 0;
    }

    warn 'update_node: updating generic switch data';
    my $result = $db->update_node(
        node_id         => $node_id,
        openflow        => $openflow,
	mpls            => $mpls,
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
	return $results;
    } else {
        $results->{'results'} = [ { "success" => 1 } ];
    }

    if ($mpls == 1) {
	warn 'update_node: updating mpls switch data';

        my $result = $db->update_node_instantiation(
            node_id    => int($node_id),
            mpls       => int($mpls),
            mgmt_addr  => $mgmt_addr,
            tcp_port   => int($tcp_port),
            vendor     => $vendor,
            model      => $model,
            sw_version => $sw_version
            );

        if (!defined $result ) {
            $results->{'results'} = [ { "error"   => $db->get_error(),
                                        "success" => 0 } ];
            return $results;
        }

        my $client = GRNOC::RabbitMQ::Client->new( topic => 'MPLS.FWDCTL.RPC',
                                                   exchange => 'OESS',
                                                   user => $db->{'rabbitMQ'}->{'user'},
                                                   pass => $db->{'rabbitMQ'}->{'pass'},
                                                   host => $db->{'rabbitMQ'}->{'host'},
                                                   port => $db->{'rabbitMQ'}->{'port'});

	my $cv = AnyEvent->condvar;

	warn 'update_node: starting mpls switch forwarding process';
        my $res = $client->new_switch(
            node_id        => int($node_id),
	    async_callback => sub {
		warn 'update_node: starting mpls switch discovery process';

		$client->{'topic'} = 'MPLS.Discovery.RPC';
		$client->new_switch(
                    node_id => $node_id,
                    async_callback => sub {
                        warn 'update_node: done starting mpls switch processes';
                        $cv->send();
                    }
                )
            }
        );
	$cv->recv();
    }

    if ($openflow) {
	warn 'update_node: updating openflow switch data';
	
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

        my $cv = AnyEvent->condvar;
        $client->update_cache(circuit_id     => -1,
                              async_callback => sub {
                                  my $result = shift;
                                  $cv->send($result);
                              });

        my $cache_result = $cv->recv();
	if ($cache_result->{'error'} || !$cache_result->{'results'}) {
	    return;
	}

        $cv = AnyEvent->condvar;
        $client->force_sync(dpid => int($node->{'dpid'}),
                            async_callback => sub {
                                my $result = shift;
                                $cv->send($result);
                            });

        $cache_result = $cv->recv();
	if ($cache_result->{'error'} || !$cache_result->{'results'}) {
	    return;
	}

        return {results => [{success => 1}]};
    }

    return {results => [{success => 1}]};
}


sub update_interface {
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $results;
    my $interface_id = $args->{'interface_id'}{'value'};
    my $description  = $args->{'description'}{'value'};
    my $vlan_tags    = $args->{'vlan_tag_range'}{'value'};
    my $mpls_vlan_tags = $args->{'mpls_vlan_tag_range'}{'value'};

    $db->_start_transaction();

    if(defined($description)){
	my $result = $db->update_interface_description( 'interface_id' => $interface_id,
							'description'  => $description );
	if(!defined($result)){
	    $db->_rollback();
	    return {results => [{success => 0}], error => "Unable to update description"};
	}
    }

    if(defined($vlan_tags)){
	my $result = $db->update_interface_vlan_range( 'vlan_tag_range' => $vlan_tags,
							'interface_id'   => $interface_id );

        if(!defined($result)){
            $db->_rollback();
            return {results => [{success => 0}], error => "Unable to update vlan tag range"};
        }
    }
    
    if(defined($mpls_vlan_tags)){
	my $result = $db->update_interface_mpls_vlan_range( 'vlan_tag_range' => $mpls_vlan_tags,
							    'interface_id'   => $interface_id );
	
	if(!defined($result)){
            $db->_rollback();
            return {results => [{success => 0}], error => "Unable to update MPLS Vlan tag range"};
        }
    }

    $db->_commit();
    $results->{'results'} = [ { "success" => 1 } ];
    
    return $results;

}

sub decom_node {
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $results;

    my $node_id = $args->{'node_id'}{'value'};

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
    
    my $cv = AnyEvent->condvar;
    $client->update_cache(circuit_id     => -1,
                          async_callback => sub {
                              my $result = shift;
                              $cv->send($result);
                          });

    my $cache_result = $cv->recv();

    if ($cache_result->{'error'} || !$cache_result->{'results'}) {
        return;
    }

    return $results;
}

sub confirm_link {
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $results;

    my $link_id = $args->{'link_id'}{'value'};
    my $name    = $args->{'name'}{'value'};

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
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $results;

    my $link_id = $args->{'link_id'}{'value'};
    my $name    = $args->{'name'}{'value'};
    my $metric  = $args->{'metric'}{'value'} || 1;

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
    my ($method, $args) = @_;
    
    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $results;
    my $node_id   = $args->{'node_id'}{'value'};
    my $ipv4_addr = $args->{'ipv4_addr'}{'value'};
    my $dpid      = $args->{'dpid'}{'value'};

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
    my ($method, $args) = @_;
    
    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $results;
    my $link_id  = $args->{'link_id'}{'value'};
    my $int_a_id = $args->{'interface_a_id'}{'value'};
    my $int_z_id = $args->{'interface_z_id'}{'value'};

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
    my ($method, $args) = @_;
    
    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $results;

    my $link_id = $args->{'link_id'}{'value'};

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
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 1);
    if (defined $err) {
        return send_json($err);
    }

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
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }
    
    my $workgroup_id            = $args->{'workgroup_id'}{'value'};
    my $workgroup_name          = $args->{'name'}{'value'};
    my $external_id             = $args->{'external_id'}{'value'};
    my $max_circuits            = $args->{'max_circuits'}{'value'};
    my $max_circuit_endpoints   = $args->{'max_circuit_endpoints'}{'value'};
    my $max_mac_address_per_end = $args->{'max_mac_address_per_end'}{'value'};

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
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $workgroup_id = $args->{'workgroup_id'}{'value'};
    my $results;

    my $circuits = $db->get_circui
}

sub update_remote_device{
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }

    my $node_id = $args->{'node_id'}{'value'};
    my $latitude = $args->{'latitude'}{'value'};
    my $longitude = $args->{'longitude'}{'value'};

    my $res = $db->update_remote_device(node_id => $node_id, lat => $latitude, lon => $longitude);
    
    return {results => $res};
}

sub add_mpls_switch{
    my ($method, $args) = @_;

    my ($user, $err) = authorization(admin => 1, read_only => 0);
    if (defined $err) {
        return send_json($err);
    }
    
    my $name = $args->{'name'}{'value'};
    my $ip_address = $args->{'ip_address'}{'value'};
    my $latitude = $args->{'latitude'}{'value'};
    my $longitude = $args->{'longitude'}{'value'};
    my $port = $args->{'port'}{'value'};
    my $vendor = $args->{'vendor'}{'value'};
    my $model = $args->{'model'}{'value'};
    my $sw_ver = $args->{'sw_ver'}{'value'};

    my $node = $db->add_mpls_node( name => $name,
				   ip => $ip_address,
				   lat => $latitude,
				   long => $longitude,
				   port => $port,
				   vendor => $vendor,
				   model => $model,
				   sw_ver => $sw_ver);

    if(!defined($node)){
	return $db->get_error();
    }

    my $client = GRNOC::RabbitMQ::Client->new( topic => 'MPLS.FWDCTL.RPC',
					       exchange => 'OESS',
					       user => $db->{'rabbitMQ'}->{'user'},
					       pass => $db->{'rabbitMQ'}->{'pass'},
					       host => $db->{'rabbitMQ'}->{'host'},
					       port => $db->{'rabbitMQ'}->{'port'});

    

    warn Data::Dumper::Dumper($node);

    my $cv = AnyEvent->condvar;
    $client->new_switch(
        node_id        => $node->{'node_id'},
        async_callback => sub {
            my $result = shift;
            
            $client->{'topic'} = 'MPLS.Discovery.RPC';
            $client->new_switch(
                node_id => $node->{'node_id'},
                async_callback => sub {
                    my $result = shift;
                    $cv->send($result);
                }
            );
        }
    );
    my $res = $cv->recv();

    return {results => [{success => 1, node_id => $node->{'node_id'}}]};

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

    my $cv = AnyEvent->condvar;
    $client->update_cache(circuit_id     => -1,
                          async_callback => sub {
                              my $result = shift;
                              $cv->send($result);
                          });

    my $result = $cv->recv();

    if ($result->{'error'} || !$result->{'results'}) {
        return;
    }

    $cv = AnyEvent->condvar;
    $client->force_sync(dpid => int($dpid),
                        async_callback => sub {
                            my $result = shift;
                            $cv->send($result);
                        });

    $result = $cv->recv();

    if ($result->{'error'} || !$result->{'results'}) {
        return;
    }

    return 1;
}

main();
