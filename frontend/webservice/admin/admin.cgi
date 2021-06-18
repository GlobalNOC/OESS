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
use JSON::XS;
use Log::Log4perl;

use GRNOC::WebService;

use OESS::Database;
use OESS::DB;
use OESS::DB::ACL;
use OESS::DB::Interface;
use OESS::DB::Link;
use OESS::DB::User;
use OESS::DB::Workgroup;

use OESS::ACL;
use OESS::Endpoint;
use OESS::Interface;
use OESS::Workgroup;

#use Time::HiRes qw( gettimeofday tv_interval);

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;

use constant PENDING_DIFF_NONE  => 0;
use constant PENDING_DIFF       => 1;
use constant PENDING_DIFF_ERROR => 2;

Log::Log4perl::init('/etc/oess/logging.conf');

my $db = new OESS::Database();
my $db2 = new OESS::DB();

my $svc = GRNOC::WebService::Dispatcher->new(method_selector => ['method', 'action']);

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
                                  multiple    => 1,
                                  description => 'Circuit IDs of the circuits on original_interface.' );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new(
        name        => 'move_interface_configuration',
        description => "Moves an interface's entire configuration.",
        callback    => sub { move_interface_configuration(@_) }
    );
    $method->add_input_parameter(
        name        => 'orig_interface_id',
        pattern     => $GRNOC::WebService::Regex::INTEGER,
        required    => 1,
        description => 'Interface ID of the original interface.'
    );
    $method->add_input_parameter(
        name        => 'new_interface_id',
        pattern     => $GRNOC::WebService::Regex::INTEGER,
        required    => 1,
        description => 'Interface ID of the temporary interface.'
    );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new(
        name        => 'update_cache',
        description => "Rewrites a node's circuit cache file.",
        callback    => sub { update_cache(@_) }
    );
    $method->add_input_parameter(
        name        => 'node_id',
        pattern     => $GRNOC::WebService::Regex::INTEGER,
        required    => 0,
        description => 'Node ID of the network device.'
    );
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
    $method->add_input_parameter( name        => "short_name",
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => "Short name of the device as it will be found during discovery");


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
    $method->add_input_parameter( name        => 'status',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
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
    $method->add_input_parameter( name        => 'role',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
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
    $method->add_input_parameter( name        => 'short_name',
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
    $method->add_input_parameter( name        => 'controller',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 1,
                                  description => '' );
    $method->add_input_parameter( name        => 'vendor',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'model',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
                                  description => '' );
    $method->add_input_parameter( name        => 'sw_ver',
                                  pattern     => $GRNOC::WebService::Regex::TEXT,
                                  required    => 0,
				  description => '' );

    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new(
        name            => "get_diffs",
        description     => "Returns diff information for each node.",
        callback        => sub { get_diffs( @_ ) }
        );

    $method->add_input_parameter(
        name            => 'approved',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "Filters diff information by approved state."
        );
    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new(
        name            => "get_diff_text",
        description     => "Returns diff text for the specified node.",
        callback        => sub { get_diff_text(@_); }
        );

    $method->add_input_parameter(
        name            => 'node_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "Node ID of the diff to lookup."
        );
    $svc->register_method($method);


    $method = GRNOC::WebService::Method->new(
        name            => "set_diff_approval",
        description     => "Approves or rejects a large diff.",
        callback        => sub { set_diff_approval( @_ ) }
        );

    $method->add_input_parameter(
        name            => 'approved',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "Filters diff information by approved state."
        );

    $method->add_input_parameter(
        name            => 'node_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "Node ID of the diff to lookup."
        );
    $svc->register_method($method);


}

=head2 get_diffs

Returns configuration state for each node. The returned param
pending_diff, if true, indicates that a configuration diff needs manual
approval.

=cut
sub get_diffs {
    my ( $method, $args ) = @_ ;
    my $approved = $args->{'approved'}{'value'};

    my ($ok, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role => 'read-only');
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $diffs = $db->get_diffs($approved);
    if (!defined $diffs) {
        $method->set_error($db->get_error());
        return;
    }

    return { results => $diffs };
}

sub get_diff_text {
    my ( $method, $args ) = @_ ;

    my ($ok, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role => 'read-only');
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $node_id = $args->{'node_id'}{'value'};
    require OESS::RabbitMQ::Client;
    my $mq = OESS::RabbitMQ::Client->new(
        topic    => 'OF.FWDCTL.RPC',
        timeout  => 60
    );
    $mq->{'topic'} = "MPLS.FWDCTL.RPC";

    my $cv = AnyEvent->condvar;
    $mq->get_diff_text(
        node_id => $node_id,
        async_callback => sub {
            my $result = shift;
            $cv->send($result);
        }
    );

    my $result = $cv->recv();
    if (defined $result->{error}) {
        $method->set_error($result->{error});
        return;
    }
    return { results => [{ text => $result->{results}}] };
}

=head2 set_diff_approval

Approves or denies diffing for a node with pending configuration
changes. Once approved the node may apply its changes. Returns 1 on
success.

=cut
sub set_diff_approval {
    my ( $method, $args ) = @_ ;
    my $approved = $args->{'approved'}{'value'};
    my $node_id  = $args->{'node_id'}{'value'};

    my ($ok, $err) = OESS::DB::User::has_system_access(db => $db2, role => 'normal', username => $ENV{REMOTE_USER});
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    if ($approved != 1) {
        $method->set_error("Diffs may only be approved via the web API.");
        return;
    }

    my $res = $db->set_pending_diff(PENDING_DIFF_NONE, $node_id);
    if (!defined $res) {
        $method->set_error($db->get_error());
        return;
    }

    return { results => [$res] };
}

sub get_circuits_on_interface{
    my ($method, $args) = @_;

    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role=>'read-only');
    if (defined $err) {
        $method->set_error($err);
        return;
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

    #my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role=>'normal');
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $results = $db->insert_node_in_path( link => $args->{'link_id'}{'value'} );

    return {results =>  => [$results]};
    
}

sub is_new_node_in_path{
    my ($method, $args) = @_;

    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username =>$ENV{'REMOTE_USER'}, role=> 'read-only');
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $results;

    $results->{'results'} = [];

    $results->{'results'}->[0] = $db->is_new_node_in_path(link => $args->{'link'}{'value'});
    return $results;
}

sub is_ok_to_decom{
    my ($method, $args) = @_;

    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role => 'read-only');
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $results;
    $results->{'results'} = [];

    my $link_details = $db->get_link( link_id => $args->{'link_id'}{'value'} );

    my $circuits = $db->get_circuits_on_link(
        link_id => $link_details->{'link_id'},
        mpls    => $link_details->{'mpls'}
    );
    $results->{'results'}->[0]->{'active_circuits'} = $circuits;



    $results->{'results'}->[0]->{'new_node_in_path'} = $db->is_new_node_in_path(link => $link_details);

    return $results;

}

sub get_remote_devices {
    my ($method, $args) = @_;

    #my ($user, $err) = authorization(admin => 1, read_only => 1);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role=>'read-only');
    if (defined $err) {
        $method->set_error($err);
        return;
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

sub get_remote_links {
    my ($method, $args) = @_;

    #my ($user, $err) = authorization(admin => 1, read_only => 1);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role=>'read-only'); 
    if (defined $err) {
        $method->set_error($err);
        return;
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

    #my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role=>'normal'); 
    if (defined $err) {
        $method->set_error($err);
        return;
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

    #my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role=>'normal'); 
    if (defined $err) {
        $method->set_error($err);
        return;
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

    #my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role=>'normal'); 
    if (defined $err) {
        $method->set_error($err);
        return;
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

#Gets workgroups based on user_id given through parameter
sub get_workgroups {
    my ($method, $args) = @_;

    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role=>'read-only');
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    my $results;
    my $user_id =  $args->{'user_id'}{'value'} || undef;
    if(!defined $user_id){
        $results->{'error'} = 'user_id is undefined';
        return $results;
    }

    my $workgroups;
    my $user = new OESS::User(db => $db2, user_id => $user_id);
    if(!defined $user){
        $results->{'error'} = 'user with the user_id \'' . $user_id . '\' was not found';
        return $results;
    }
    $user->load_workgroups();

    $workgroups = $user->to_hash()->{workgroups};
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

    #my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role=>'normal'); 
    if (defined $err) {
        $method->set_error($err);
        return;
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

    my $ok;

    my $user = new OESS::User(db => $db2, username => $ENV{REMOTE_USER});
    $user->load_workgroups;
    foreach my $wg (@{$user->workgroups}) {
        if ($wg->{role} eq 'admin') {
            $ok = 1;
            last;
        }
    }
    if (!$ok) {
        ($ok, undef) = OESS::DB::User::has_system_access(db => $db2, role => 'normal', username => $ENV{REMOTE_USER});
    }
    if (!$ok) {
        $method->set_error('Not authorized.');
        return;
    }


    #my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role=>'normal'); 


    my $results;
    my $model = {
        name => $args->{'name'}{'value'},
        external_id => $args->{'external_id'}{'value'},
        type => $args->{'type'}{'value'}
    };
    my ($new_wg_id, $createErr) =
        OESS::DB::Workgroup::create(db => $db2, model => $model);

    if ( !defined $new_wg_id ) {
        $results->{'error'} = $createErr;
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

    #my ($user, $err) = authorization(admin => 0, read_only => 1);
    my $user = OESS::DB::User::fetch(db => $db2, username => $ENV{'REMOTE_USER'}); 
    if (!defined $user) {
        my $err = "User $ENV{'REMOTE_USER'} is not a valid user";
        $method->set_error($err);
        return;
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

    #my ($user, $err) = authorization(admin => 0, read_only => 1);
    warn "Before Auth";
    my ($result, $err) = OESS::DB::User::has_workgroup_access(db => $db2, 
                                                      username => $ENV{'REMOTE_USER'}, 
                                                      workgroup_id => $args->{'workgroup_id'}{'value'}, 
                                                      role => 'read-only');
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    warn "After Auth";
    my $results;

    my $workgroup_id = $args->{'workgroup_id'}{'value'};

    my ($users, $err2) = OESS::DB::Workgroup::get_users_in_workgroup(db => $db2,  workgroup_id => $workgroup_id );
    my $returnedUsers = [];
    warn "After Getting users";
    if ( !defined $users ) {
        $results->{'error'}   = $err2;
        $results->{'results'} = [];
    }
    else {
        foreach my $user (@$users) {
            push @$returnedUsers, $user->to_hash();
        }
        $results->{'results'} = $returnedUsers;
    }

    return $results;
}

sub add_user_to_workgroup {
    my ($method, $args) = @_;

    #my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_workgroup_access(db => $db2, 
                                                      username => $ENV{'REMOTE_USER'}, 
                                                      workgroup_id => $args->{'workgroup_id'}{'value'}, 
                                                      role => 'admin'); 
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $results;

    my $user_id = $args->{'user_id'}{'value'};
    my $wg_id   = $args->{'workgroup_id'}{'value'};
    my $role    = $args->{'role'}{'value'};
    my ($resultA, $err2) = OESS::DB::Workgroup::add_user(
        db           => $db2,
        user_id      => $user_id,
        workgroup_id => $wg_id,
        role         => $role
        );

    if ( !defined $resultA ) {
        $results->{'error'}   = $err2;
        $results->{'results'} = [];
    }
    else {
        $results->{'results'} = [ { success => 1 } ];
    }

    return $results;
}

sub remove_user_from_workgroup {
    my ($method, $args) = @_;

    #my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_workgroup_access(db => $db2, 
                                                      username => $ENV{'REMOTE_USER'}, 
                                                      workgroup_id => $args->{'workgroup_id'}{'value'}, 
                                                      role => 'admin'); 
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $results;

    my $user_id = $args->{'user_id'}{'value'};
    my $wg_id   = $args->{'workgroup_id'}{'value'};

    my ($resultA, $err2) = OESS::DB::Workgroup::remove_user(db => $db2,
        user_id      => $user_id,
        workgroup_id => $wg_id
        );

    if ( !defined $resultA ) {
        $results->{'error'}   = $err2;
        $results->{'results'} = [];
    }
    else {
        $results->{'results'} = [ { success => 1 } ];
    }

    return $results;
}

sub add_user {
    my ($method, $args) = @_;

    #my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role=>'normal');  
    if (defined $err) {
        $method->set_error($err);
        return;
    }
    

    my $results;

    my $given_name  = $args->{"first_name"}{'value'};
    my $family_name = $args->{"family_name"}{'value'};
    my $email       = $args->{"email_address"}{'value'};
    my @auth_names  = $args->{"auth_name"}{'value'};
    my $status      = $args->{"status"}{'value'};

    my ($new_user_id, $err2) = OESS::DB::User::add_user(db => $db2,

        given_name    => $given_name,
        family_name   => $family_name,
        email         => $email,
        auth_names    => \@auth_names
        );

    if ( !defined $new_user_id ) {
        $results->{'error'} = $err2;
        $results->{'results'} = [ { success => 0 } ];
    }
    else {
        $results->{'results'} = [ { success => 1, user_id => $new_user_id } ];
    }

    return $results;
}

sub delete_user {
    my ($method, $args) = @_;

    #my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role=>'normal'); 
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $results;

    my $user_id = $args->{'user_id'}{'value'};

    my ($output, $err2) = OESS::DB::User::delete_user(db => $db2,  user_id => $user_id );

    if ( !defined $output ) {
        $results->{'error'} = $err2;
        $results->{'results'} = [ { success => 0 } ];
    }
    else {
        $results->{'results'} = [ { success => 1 } ];
    }

    return $results;
}

sub edit_user {
    my ($method, $args) = @_;

    #my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role=>'normal'); 
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $results;

    my $user_id     = $args->{"user_id"}{'value'};
    my $given_name  = $args->{"first_name"}{'value'};
    my $family_name = $args->{"family_name"}{'value'};
    my $email       = $args->{"email_address"}{'value'};
    my @auth_names  = $args->{"auth_name"}{'value'};
    my $status      = $args->{'status'}{'value'};

    my ($success, $err2) = OESS::DB::User::edit_user( db => $db2,
        given_name    => $given_name,
        family_name   => $family_name,
        email         => $email,
        auth_names    => \@auth_names,
        user_id       => $user_id,
        status        => $status
        );

    if ( !defined $success ) {
        $results->{'error'} = $err2;
        $results->{'results'} = [ { success => 0 } ];
    }
    else {
        $results->{'results'} = [ { success => 1 } ];
    }

    return $results;
}

sub get_edge_interface_move_maintenances {
    my ($method, $args) = @_;

    # my ($user, $err) = authorization(admin => 1, read_only => 1);                                   
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role => 'read-only');
    if (defined $err) {
        $method->set_error($err);
        return;
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

    # my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role => 'normal');
    if (defined $err) {
        $method->set_error($err);
        return;
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
    if(!_update_cache_and_sync_node($res->{'node'})){
        $results->{'error'}   = "Issue diffing node";
    }

    return $results;
}

sub revert_edge_interface_move_maintenance {
    my ($method, $args) = @_;

    # my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role => 'normal');
    if (defined $err) {
        $method->set_error($err);
        return;
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
    if(!_update_cache_and_sync_node($res->{'node'})){
	$results->{'error'}   = "Issue diffing node";
    }

    return $results;
}

sub move_edge_interface_circuits {
    my ($method, $args) = @_;

    # my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role => 'normal'); 
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $results = { 'results' => [] };
    my $orig_interface_id  = $args->{"orig_interface_id"}{'value'};
    my $new_interface_id   = $args->{"new_interface_id"}{'value'};
    my $circuit_ids        = $args->{"circuit_id"}{'value'};

    my $res = $db->move_edge_interface_circuits(
        orig_interface_id => $orig_interface_id,
        new_interface_id  => $new_interface_id,
        circuit_ids       => $circuit_ids
        );


    if ( !defined $res || !defined($res->{'node'})) {
        $results->{'error'}   = $db->get_error();
	warn "Error: " . $db->get_error();
	return $results;
    }

    $results->{'results'} = [$res];

    # now diff node
    if(!_update_cache_and_sync_node($res->{'node'})){
	$results->{'error'}   = "Issue diffing node";
    }

    return $results;
}

=head2 move_interface_configuration

move_interface_configuration moves any ACLs, Cloud Interconnects,
Circuit Endpoints, VRF Endpoints and Workgroup Membership on
C<orig_interface_id> to C<new_interface_id>. After the move
C<orig_interface_id> will be an unowned interface without any of the
previously mentioned configuration.

move_interface_configuration replaces move_edge_interface_circuits and
the related _interface_move_maintenance methods.

=cut
sub move_interface_configuration {
    my ($method, $args) = @_;

    # my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role => 'normal'); 
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $new_interface_id = $args->{new_interface_id}{value};
    my $orig_interface_id = $args->{orig_interface_id}{value};

    $db2->start_transaction();

    # Cloud Interconnects and Workgroup
    my $orig_interface = OESS::Interface->new(
        db => $db2,
        interface_id => $orig_interface_id
    );
    my $new_interface = OESS::Interface->new(
        db => $db2,
        interface_id => $new_interface_id
    );

    $new_interface->{cloud_interconnect_id} = $orig_interface->{cloud_interconnect_id};
    $new_interface->{cloud_interconnect_type} = $orig_interface->{cloud_interconnect_type};
    $new_interface->{workgroup_id} = $orig_interface->{workgroup_id};
    my $new_ok = $new_interface->update_db();
    if (!defined $new_ok) {
        $method->set_error("Couldn't update new interface: " . $db2->get_error());
        $db2->rollback();
        return;
    }

    $orig_interface->{cloud_interconnect_id} = undef;
    $orig_interface->{cloud_interconnect_type} = undef;
    $orig_interface->{workgroup_id} = undef;
    my $orig_ok = $orig_interface->update_db();
    if (!defined $orig_ok) {
        $method->set_error("Couldn't update original interface: " . $db2->get_error());
        $db2->rollback();
        return;
    }

    # Endpoints 'n VRF Endpoints
    my $endpoints_ok = OESS::Endpoint::move_endpoints(
        db => $db2,
        new_interface_id => $new_interface_id,
        orig_interface_id => $orig_interface_id
    );
    if (!defined $endpoints_ok) {
        $method->set_error("Couldn't move Endpoints: " . $db2->get_error());
        $db2->rollback();
        return;
    }

    # ACLs
    my $acls = OESS::DB::ACL::fetch_all(
        db => $db2,
        interface_id => $orig_interface_id
    );
    foreach my $acl (@$acls) {
        my $obj = OESS::ACL->new(db => $db2, model => $acl);
        $obj->{interface_id} = $new_interface_id;

        my $ok = $obj->update_db();
        if (!defined $ok) {
            $method->set_error("Couldn't move ACLs: $err");
            $db2->rollback();
            return;
        }
    }

    $db2->commit();

    use OESS::RabbitMQ::Client;

    my $mq = OESS::RabbitMQ::Client->new(
        topic    => 'MPLS.FWDCTL.RPC',
        timeout  => 60
    );
    if (!defined $mq) {
        $method->set_error("Couldn't create RabbitMQ client.");
        return;
    }

    my $cv = AnyEvent->condvar;
    $mq->update_cache(
        async_callback => sub {
            my $resultM = shift;
            $cv->send($resultM);
        }
    );

    my $resultC = $cv->recv();
    if (!defined $resultC) {
        $method->set_error("Error while calling `update_cache` via RabbitMQ.");
        return;
    }
    if (defined $resultC->{'error'}) {
        $method->set_error("Error while calling `update_cache`: $resultC->{error}");
        return;
    }

    my $status = $resultC->{results}->{status};
    return { results => [ { status => $status } ] };
}

sub update_cache {
    my ($method, $args) = @_;

    # my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role => 'normal'); 
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $node_id = $args->{node_id}{value};

    use OESS::RabbitMQ::Client;

    my $mq = OESS::RabbitMQ::Client->new(
        topic    => 'MPLS.FWDCTL.RPC',
        timeout  => 60
    );
    if (!defined $mq) {
        $method->set_error("Couldn't create RabbitMQ client.");
        return;
    }

    my $cv = AnyEvent->condvar;
    $mq->update_cache(
        node_id        => $node_id,
        async_callback => sub {
            my $resultM = shift;
            $cv->send($resultM);
        }
    );

    my $resultC = $cv->recv();
    if (!defined $resultC) {
        $method->set_error("Error while calling `update_cache` via RabbitMQ.");
        return;
    }
    if (defined $resultC->{'error'}) {
        $method->set_error("Error while calling `update_cache`: $resultC->{error}");
        return;
    }

    my $status = $resultC->{results}->{status};
    return { results => [ { status => $status } ] };
}

sub get_pending_nodes {
    my ($method, $args) = @_;

    # my ($user, $err) = authorization(admin => 1, read_only => 1);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role => 'read-only'); 
    if (defined $err) {
        $method->set_error($err);
        return;
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

    # my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role => 'normal'); 
    if (defined $err) {
        $method->set_error($err);
        return;
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

    my $result2 = $db->confirm_node(
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

    if ( !defined $result2 ) {
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
    require OESS::RabbitMQ::Client;
    my $mq = OESS::RabbitMQ::Client->new( topic    => 'OF.FWDCTL.RPC',
                                          timeout  => 60 );
    if (!defined $mq) {
        $results->{'results'} = [ {
                                   "error"   => "Internal server error occurred. Message queue connection failed.",
                                   "success" => 0
                                  }
                                ];
        return $results;
    } else {
	$mq->{'topic'} = 'OF.FWDCTL.RPC';
    }

    my $cv = AnyEvent->condvar;
    $mq->update_cache(circuit_id     => -1,
                          async_callback => sub {
                              my $resultM = shift;
                              $cv->send($resultM);
                          });

    my $cache_result = $cv->recv();

    if ($cache_result->{'error'} || !$cache_result->{'results'}) {
        return { results => [ {
                               "error"   => "Cache result error: $cache_result->{'error'}.",
                               "success" => 0
                              }
                            ] };
    }

    $cv = AnyEvent->condvar;
    $mq->force_sync(dpid => int($node->{'dpid'}),
                        async_callback => sub {
                            my $resultM = shift;
                            $cv->send($resultM);
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

    # my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role => 'normal'); 
    if (defined $err) {
        $method->set_error($err);
        return;
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
    my $short_name = $args->{'short_name'}{'value'};

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
    require OESS::RabbitMQ::Client;
    my $mq = OESS::RabbitMQ::Client->new( topic    => 'OF.FWDCTL.RPC',
                                          timeout  => 60 );

    warn 'update_node: updating generic switch data';
    my $result2 = $db->update_node(
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
        max_static_mac_flows => $max_static_mac_flows,
        short_name      => $short_name
    );

    if ( !defined $result2 ) {
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

    my $cv = AnyEvent->condvar;
    $cv->begin;

    if ($mpls == 1) {
	warn 'update_node: updating mpls switch data';

        my $result3 = $db->update_node_instantiation(
            node_id    => int($node_id),
            mpls       => int($mpls),
            mgmt_addr  => $mgmt_addr,
            tcp_port   => int($tcp_port),
            vendor     => $vendor,
            model      => $model,
            sw_version => $sw_version
	);

        if (!defined $result3 ) {
            $results->{'results'} = [ { "error"   => $db->get_error(),
                                        "success" => 0 } ];
            return $results;
        }

	if (!defined $mq) {
	    $results->{'results'} = [ {
		"error"   => "Internal server error occurred. Message queue connection failed.",
		"success" => 0
	    } ];
	    return $results;
	} else {
	    $mq->{'topic'} = 'OF.FWDCTL.RPC';
	}

	warn 'update_node: starting mpls switch forwarding process';
	#no reason to do these individually!
	$mq->{'topic'} = 'MPLS.FWDCTL.RPC';
	$cv->begin;
        $mq->new_switch(
            node_id        => int($node_id),
	    async_callback => sub {
		my $res = shift;
		
		$cv->end($res);
	    });
	$mq->{'topic'} = 'MPLS.Discovery.RPC';

	$cv->begin;
	$mq->new_switch(
	    node_id => $node_id,
	    async_callback => sub {
		my $res = shift;
		$cv->end($res);
	    });
    }

    if ($openflow) {
	warn 'update_node: updating openflow switch data';
	
	if (!defined $mq) {
	    $results->{'results'} = [ {
		"error"   => "Internal server error occurred. Message queue connection failed.",
		"success" => 0
	    } ];
	    return $results;
	} else {
	    $mq->{'topic'} = 'OF.FWDCTL.RPC';
	}
	
	my $node = $db->get_node_by_id(node_id => $node_id);

	$cv->begin;
        $mq->update_cache(circuit_id     => -1,
			  async_callback => sub {
			      my $resultM = shift;
			      $cv->end($resultM);
			  });

        $cv->begin;
        $mq->force_sync(dpid => int($node->{'dpid'}),
			async_callback => sub {
			    my $resultM = shift;
			    $cv->end($resultM);
			});
    }

    $cv->end;
    $cv->recv();

    return {results => [{success => 1}]};
}


sub update_interface {
    my ($method, $args) = @_;

    # my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role => 'normal'); 
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $results;
    my $interface_id = $args->{'interface_id'}{'value'};
    my $description  = $args->{'description'}{'value'};
    my $vlan_tags    = $args->{'vlan_tag_range'}{'value'};
    my $mpls_vlan_tags = $args->{'mpls_vlan_tag_range'}{'value'};

    $db->_start_transaction();

    if(defined($description)){
	my $result2 = $db->update_interface_description( 'interface_id' => $interface_id,
							'description'  => $description );
	if(!defined($result2)){
	    $db->_rollback();
	    return {results => [{success => 0}], error => "Unable to update description"};
	}
    }

    if(defined($vlan_tags)){
	my $result3 = $db->update_interface_vlan_range( 'vlan_tag_range' => $vlan_tags,
							'interface_id'   => $interface_id );

        if(!defined($result3)){
            $db->_rollback();
            return {results => [{success => 0}], error => "Unable to update vlan tag range"};
        }
    }

    if(defined($mpls_vlan_tags)){
	my $result4 = $db->update_interface_mpls_vlan_range( 'vlan_tag_range' => $mpls_vlan_tags,
							    'interface_id'   => $interface_id );
	
	if(!defined($result4)){
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

    # my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role => 'normal'); 
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $results;

    my $node_id = $args->{'node_id'}{'value'};

    my $result2 = $db->decom_node( node_id => $node_id );

    if ( !defined $result2 ) {
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
    require OESS::RabbitMQ::Client;
    my $mq = OESS::RabbitMQ::Client->new( topic    => 'OF.FWDCTL.RPC',
                                          timeout  => 60 );

    if (!defined $mq) {
        return;
    } else {
	$mq->{'topic'} = 'OF.FWDCTL.RPC';
    }
    
    my $cv = AnyEvent->condvar;
    $mq->update_cache(circuit_id     => -1,
		      async_callback => sub {
			  my $resultM = shift;
			  $cv->send($resultM);
		      });

    my $cache_result = $cv->recv();

    if ($cache_result->{'error'} || !$cache_result->{'results'}) {
        return;
    }

    return $results;
}

sub confirm_link {
    my ($method, $args) = @_;

    # my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role => 'normal'); 
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $results;

    my $link_id = $args->{'link_id'}{'value'};
    my $name    = $args->{'name'}{'value'};

    my $result2 = $db->confirm_link(
        link_id => $link_id,
        name    => $name,
        );

    if ( !defined $result2 ) {
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

    # my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role => 'normal'); 
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $results;

    my $link_id = $args->{'link_id'}{'value'};
    my $name    = $args->{'name'}{'value'};
    my $metric  = $args->{'metric'}{'value'} || 1;

    my $result2 = $db->update_link(
        link_id => $link_id,
        name    => $name,
        metric  => $metric
        );

    if ( !defined $result2 ) {
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
    
    # my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role => 'normal'); 
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $results;
    my $node_id   = $args->{'node_id'}{'value'};
    my $ipv4_addr = $args->{'ipv4_addr'}{'value'};
    my $dpid      = $args->{'dpid'}{'value'};

    my $result2 = $db->decom_node(node_id => $node_id);

    if ( !defined $result2 ) {
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
    $result2 = $db->create_node_instance(node_id => $node_id,ipv4_addr => $ipv4_addr,admin_state => "decom", dpid => $dpid);

    if ( !defined $result2 ) {
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
    
    # my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role => 'normal'); 
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $results;
    my $link_id  = $args->{'link_id'}{'value'};
    my $int_a_id = $args->{'interface_a_id'}{'value'};
    my $int_z_id = $args->{'interface_z_id'}{'value'};

    my $result2 = $db->decom_link_instantiation( link_id => $link_id );
    
    if ( !defined $result2 ) {
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

    $result2 = $db->create_link_instantiation( link_id => $link_id, interface_a_id => $int_a_id, interface_z_id => $int_z_id, state => "decom" );

    if ( !defined $result2 ) {
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

    # my ($user, $error) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role => 'normal'); 
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $terror = $db2->start_transaction;
    if (defined $terror) {
        $method->set_error("$terror");
        return;
    }

    my ($link, $lerror) = OESS::DB::Link::fetch(db => $db2, link_id => $args->{link_id}->{value});
    if (defined $lerror) {
        $method->set_error("$lerror");
        return;
    }
    if ($link->{link_state} eq 'decom' || $link->{link_state} eq 'available') {
        $method->set_error("Link has already been decom'd or hasn't yet been approved.");
        $db2->rollback;
        return;
    }

    my $link_state;
    if ($link->{status} eq 'down') {
        # Set role of associated interfaces to unknown.
        my $err1 = OESS::DB::Interface::update(db => $db2, interface => {
            interface_id => $link->{interface_a_id},
            role         => 'unknown'
        });
        my $err2 = OESS::DB::Interface::update(db => $db2, interface => {
            interface_id => $link->{interface_z_id},
            role         => 'unknown'
        });
        if (defined $err1 || defined $err2) {
            $method->set_error("Couldn't update link endpoints: $err1 $err2");
            $db2->rollback;
            return;
        }

        # Set link_state to 'decom'.
        $link_state = 'decom';
    } else {
        # Set link_state to 'available'; This resets the link to the
        # discovered / unapproved state.
        $link_state = 'available';
    }

    my ($ok, $errL) = OESS::DB::Link::update(
        db   => $db2,
        link => {
            link_id => $link->{link_id},
            link_state => $link_state,
            interface_a_id => $link->{interface_a_id},
            interface_z_id => $link->{interface_z_id},
            ip_a => $link->{ip_a},
            ip_z => $link->{ip_z}
        }
    );
    if (defined $errL) {
        $method->set_error($errL);
        $db2->rollback;
        return;
    }

    $db2->commit;
    return { results => [{ success => 1 }] };
}

sub get_pending_links {
    my ($method, $args) = @_;

    # my ($user, $err) = authorization(admin => 1, read_only => 1);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role => 'read-only'); 
    if (defined $err) {
        $method->set_error($err);
        return;
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

    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role => 'read-only');
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $topo = $db->gen_topo();
    my $results;

    if(!$topo){
        $results->{'results'} = [];
        $results->{'error'} = 1;
        $results->{'error_text'} = $db->get_error();
    }
    else {
        $results->{'results'} = [{'topo' => $topo}];
    }
    return $results;
}

sub edit_workgroup{
    my ($method, $args) = @_;

    my $workgroup = new OESS::Workgroup(db => $db2, workgroup_id => $args->{workgroup_id}{value});
    if (!defined $workgroup) {
        $method->set_error("Workgroup $args->{workgroup_id}{value} not found.");
        return;
    }

    my $ok;
    my $err;
    if ($workgroup->type eq 'admin') {
        ($ok, $err) = OESS::DB::User::has_system_access(db => $db2, role => 'admin', username => $ENV{REMOTE_USER});
    } else {
        ($ok, $err) = OESS::DB::User::has_workgroup_access(db => $db2, role => 'admin', username => $ENV{REMOTE_USER}, workgroup_id => $args->{workgroup_id}{value});
    }
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $workgroup_id            = $args->{'workgroup_id'}{'value'};
    my $workgroup_name          = $args->{'name'}{'value'};
    my $external_id             = $args->{'external_id'}{'value'};
    my $max_circuits            = $args->{'max_circuits'}{'value'};
    my $max_circuit_endpoints   = $args->{'max_circuit_endpoints'}{'value'};
    my $max_mac_address_per_end = $args->{'max_mac_address_per_end'}{'value'};
    my $model = {
        workgroup_id            => $workgroup_id,
        name                    => $workgroup_name,
        external_id             => $external_id,
        max_mac_address_per_end => $max_mac_address_per_end,
        max_circuits            => $max_circuits,
        max_circuit_endpoints   => $max_circuit_endpoints,
    };
    my ($res, $err2) = OESS::DB::Workgroup::update(db => $db2, 
              model => $model
        );

    my $results;
    if(defined($res)){
        $results->{'results'} = [{success => 1}];
    }else{
        $results->{'error'} = $err2;
    }
    return $results;
}

sub decom_workgroup{
    my ($method, $args) = @_;

    #Find the workgroup to be decommissioned
    my $workgroup_id = $args->{'workgroup_id'}{'value'};
    my $workgroup = new OESS::Workgroup(db => $db2, workgroup_id => $workgroup_id);

    if (!defined $workgroup) {
        $method->set_error("No workgroup with that ID found");
        return;
    }

    my $ok;
    my $err;
    if ($workgroup->type eq 'admin') {
        ($ok, $err) = OESS::DB::User::has_system_access(db => $db2, role => 'admin', username => $ENV{REMOTE_USER});
    } else {
        ($ok, $err) = OESS::DB::User::has_workgroup_access(db => $db2, role => 'admin', username => $ENV{REMOTE_USER}, workgroup_id => $args->{workgroup_id}{value});
    }
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    # Gather interfaces to remove the acls and start the transaction
    my $interfaces = OESS::DB::Interface::get_interfaces(db => $db2, workgroup_id => $workgroup_id);

    $db2->start_transaction();

    foreach my $interface (@$interfaces) {
        my ($count, $acl_error) = OESS::DB::ACL::remove_all(db => $db2, interface_id => $interface);
        if (defined $acl_error) {
            $method->set_error($acl_error);
            $db2->rollback();
            return;
        }
    }
    #After commiting changes for deleteing all ACLs switch workgroups status to decom and update the databse with the new status
    $workgroup->{'status'} = 'decom';
    my $updateErr = $workgroup->update();
    if (defined $updateErr){
        $method->set_error($updateErr);
        $db2->rollback();
        return;
    }

    $db2->commit();
    return;

}

sub update_remote_device{
    my ($method, $args) = @_;

    # my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role => 'normal'); 
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $node_id = $args->{'node_id'}{'value'};
    my $latitude = $args->{'latitude'}{'value'};
    my $longitude = $args->{'longitude'}{'value'};

    my $res = $db->update_remote_device(node_id => $node_id, lat => $latitude, lon => $longitude);
    
    return {results => $res};
}

sub add_mpls_switch{
    my ($method, $args) = @_;

    # my ($user, $err) = authorization(admin => 1, read_only => 0);
    my ($result, $err) = OESS::DB::User::has_system_access(db => $db2, username => $ENV{'REMOTE_USER'}, role => 'normal'); 
    if (defined $err) {
        $method->set_error($err);
        return;
    }

    my $name = $args->{'name'}{'value'};
    my $short_name = $args->{'short_name'}{'value'};
    my $ip_address = $args->{'ip_address'}{'value'};
    my $latitude = $args->{'latitude'}{'value'};
    my $longitude = $args->{'longitude'}{'value'};
    my $port = $args->{'port'}{'value'};
    my $controller = $args->{'controller'}{'value'};
    my $vendor = $args->{'vendor'}{'value'};
    my $model = $args->{'model'}{'value'};
    my $sw_ver = $args->{'sw_ver'}{'value'};

    if ($ip_address !~ /^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$/) {
        $method->set_error("ip_address $ip_address is an invalid IPv4 Address.");
        return;
    }

    my $node = $db->add_mpls_node(
        name => $name,
        short_name => $short_name,
        ip => $ip_address,
        lat => $latitude,
        long => $longitude,
        port => $port,
        controller => $controller,
        vendor => $vendor,
        model => $model,
        sw_ver => $sw_ver
    );
    if (!defined $node) {
        $method->set_error($db->get_error);
        return;
    }

    require OESS::RabbitMQ::Client;
    my $mq = OESS::RabbitMQ::Client->new(
        topic    => 'NSO.FWDCTL.RPC',
        timeout  => 60
    );
    if (!defined $mq) {
        $method->set_error("Internal server error occurred. Message queue connection failed.");
        return;
    }

    my $fwdctl_topic;
    my $discovery_topic;

    if ($controller eq 'netconf') {
        $fwdctl_topic = 'MPLS.FWDCTL.RPC';
        $discovery_topic = 'MPLS.Discovery.RPC';
    }
    if ($controller eq 'nso') {
        $fwdctl_topic = 'NSO.FWDCTL.RPC';
        $discovery_topic = 'NSO.Discovery.RPC';
    }

    my $cv = AnyEvent->condvar;
    $mq->{'topic'} = $fwdctl_topic;
    $mq->new_switch(
        node_id        => $node->{'node_id'},
        async_callback => sub {
            my $resultM = shift;
            $mq->{'topic'} = $discovery_topic;
            $mq->new_switch(
                node_id => $node->{'node_id'},
                async_callback => sub {
                    my $resultM = shift;
                    $cv->send($resultM);
                }
            );
        }
    );
    $cv->recv;

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
    my $node = shift;

    require OESS::RabbitMQ::Client;
    my $mq = OESS::RabbitMQ::Client->new( topic    => 'OF.FWDCTL.RPC',
                                          timeout  => 20 );

    if ( !defined($mq) ) {
        return;
    } else {
	$mq->{'topic'} = 'OF.FWDCTL.RPC';
    }

    my $cv = AnyEvent->condvar;
    $cv->begin();
    if($node->{'openflow'}){
	warn "Updating OF Cache\n";
	$cv->begin();
	$mq->update_cache(circuit_id     => -1,
			  async_callback => sub {
			      my $result = shift;
			      $cv->send();
			  });
	warn "Requesting OF Force Sync\n";
	$cv->begin();
	$mq->force_sync(dpid => int($node->{'dpid'}),
			async_callback => sub {
			    my $result = shift;
			    $cv->send();
			});
	
	
    }

    if($node->{'mpls'}){
	warn "Syncing MPLS\n";
	$mq->{'topic'} = 'MPLS.FWDCTL.RPC';
	$cv->begin();
	$mq->new_switch(
	    node_id => int($node->{'node_id'}),
	    async_callback => sub {
		my $result = shift;
		$cv->send();
	    });
    }

    $cv->recv();
    warn "Complete syncing node\n";
    return 1;
}

main();
