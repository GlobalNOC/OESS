#!/usr/bin/perl
eval 'exec /usr/bin/perl  -S $0 ${1+"$@"}'
    if 0; # not running under some shell
#------ NDDI OESS Database Interaction Module
##-----
##----- $HeadURL: svn+ssh://svn.grnoc.iu.edu/grnoc/oe-ss/perl-lib/OESS-Database/trunk/lib/OESS/Database.pm $
##----- $Id$
##----- $Date$
##----- $LastChangedBy$
##-----
##----- Provides object oriented methods to interact with the OESS Database
##-------------------------------------------------------------------------
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
=head1 NAME

OESS::Database - Database Interaction Module

=head1 VERSION

Version 1.1.8

=cut

our $VERSION = '1.1.8';

=head1 SYNOPSIS

This is a module to provide a simplified object oriented way to connect to
and interact with the OESS database.

Some examples:

    use OESS::Database;

    my $db = new OESS::Database();

    my $circuits = $db->get_current_circuits();

    if (! defined $circuits){
        warn "Uh oh, something bad happened: " . $db->get_error();
        exit(1);
    }

    foreach my $circuit_info (@$circuits){

        my $circuit_id = $circuit_info->{'circuit_id'};

        my $endpoints = $db->get_circuit_endpoints(circuit_id => $circuit_id);

        # etc...
    }

=cut

use strict;
use warnings;

package OESS::Database;

use DBI;
use XML::Simple;

use Array::Utils qw(intersect);
use XML::Writer;
use Net::DBus;
use OESS::Topology;
use DateTime;
use Data::Dumper;

use constant VERSION => '1.1.8';
use constant MAX_VLAN_TAG => 4096;
use constant MIN_VLAN_TAG => 1;
use constant SHARE_DIR => "/usr/share/doc/perl-OESS-" . VERSION . "/";
use constant UNTAGGED => -1;
use constant OSCARS_WG => 'OSCARS IDC';

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;

our $ENABLE_DEVEL=0;

=head1 PUBLIC METHODS

=head2 new

Constructor for the Database object. Returns the object on
success and undefined on error such as unable to connect.

=over

=item config (optional)

The path on disk to the configuration file for database connection
information. This defauls to "/etc/oess/database.xml".

=back

=cut

sub new {
    my $that  = shift;
    my $class = ref($that) || $that;

    my %args = (
	config => '/etc/oess/database.xml' ,
	topo   => undef,
	@_,
	);
    my $self = \%args;
    bless $self, $class;

    my $config_filename = $args{'config'};
    my $config = XML::Simple::XMLin($config_filename);
    my $username = $config->{'credentials'}->{'username'};
    my $password = $config->{'credentials'}->{'password'};
    my $database = $config->{'credentials'}->{'database'};

    my $snapp_config_location = $config->{'snapp_config_location'};
    my $oscars_info = {
	host => $config->{'oscars'}->{'host'},
	key  => $config->{'oscars'}->{'key'},
	cert => $config->{'oscars'}->{'cert'},
	topo => $config->{'oscars'}->{'topo'}
    };
    
    my $dbh      = DBI->connect("DBI:mysql:$database", $username, $password,
				{mysql_auto_reconnect => 1 }
        );

    if (! $dbh){
	return ;
    }

    # set the defualt vlan range, if not defined in config default to 1-4096
    $self->default_vlan_range(range => $config->{'default_vlan_range'} || '1-4096');

    $dbh->{'mysql_auto_reconnect'}   = 1;
    $self->{'admin_email'}           = $config->{'admin_email'};
    $self->{'snapp_config_location'} = $snapp_config_location;
    $self->{'dbh'}                   = $dbh;
    $self->{'oscars'}                = $oscars_info;

    $self->{'discovery_vlan'}        = $config->{'discovery_vlan'} || -1;
    $self->{'forwarding_verification'} = $config->{'forwarding_verification'};
    if (! defined $self->{'topo'}){
	$self->{'topo'} = OESS::Topology->new(db => $self);
    }

    $self->{'processes'} = $config->{'process'};
    
    return $self;
}


=head2 get_error

A simple method that returns a string detailing what the last error was. Usually this
is called to check what happened when an undefined value is returned somewhere.

=cut

sub get_error {
    my $self = shift;

    return $self->{'error'};
}


=head2 get_oess_schema_version

=cut

sub get_oess_schema_version{
    my $self = shift;
    my $query = "select * from oess_version";
    my $res = $self->_execute_query($query,[]);
    if(!defined($res)){
	#must be < version 1.0.3
	return;
    }else{
	$res = $res->[0]->{'version'};
	return $res;
    }
}

=head2 update_circuit_state

Changes a circuit instantiation identified by $circuit_id from $old_state to $new_state.
In reality this decommissions the present circuit instantiation and creates a new one.

=over

=item circuit_id

The internal MySQL primary key int identifier for this circuit.

=item old_state

The state that the old circuit instantiation should be in.

=item new_state

The state that the new circuit instantiation should be in.

=item modified_by_user_id

The internal MySQL primary key int identifier for the user performing this update.

=item no_transact

If defined, rollback, commi, and transaction functions are ignored.

=back

=cut

sub update_circuit_state{
    my $self = shift;
    my %args = @_;

    my $circuit_id  = $args{'circuit_id'};
    my $old_state   = $args{'old_state'};
    my $new_state   = $args{'new_state'};
    my $user_id     = $args{'modified_by_user_id'};
    my $no_transact = $args{'no_transact'};

    if (!defined $no_transact) {
        $self->_start_transaction();
    }

    my $details = $self->get_circuit_details(circuit_id => $circuit_id);
    if (!defined $details){
	$self->_set_error("Unable to find circuit information for circuit $circuit_id");
        if (!defined $no_transact) {
            $self->_rollback();
        }
	return;
    }

    my $bandwidth = $details->{'bandwidth'};

    my $query = "update circuit_instantiation set end_epoch = unix_timestamp(NOW()) " .
	" where circuit_id = ? and end_epoch = -1";
    my $result = $self->_execute_query($query, [$circuit_id]);
    if (!defined $result){
	$self->_set_error("Unable to decom old circuit instantiation.");
        if (!defined $no_transact) {
            $self->{'dbq'}->rollback();
        }
	return;
    }

    $query = "insert into circuit_instantiation (circuit_id, end_epoch, start_epoch, reserved_bandwidth_mbps, circuit_state, modified_by_user_id) values (?, -1, unix_timestamp(now()), ?, ?, ?)";
    $result = $self->_execute_query($query, [$circuit_id, $bandwidth, $new_state, $user_id]);
    if (!defined $result){
        if (!defined $no_transact) {
            $self->_rollback();
        }
	$self->_set_error("Unable to create new circuit instantiation record.");
	return;
    }

    $query = "update circuit set circuit_state= ? where circuit_id = ?";
    $result = $self->_execute_query($query, [$new_state, $circuit_id]);
    if (!defined $result){
        if (!defined $no_transact) {
            $self->_rollback();
        }
	$self->_set_error("Unable to set state of new circuit record.");
	return;
    }

    if (!defined $no_transact) {
        $self->_commit();
    }
    return 1;
}


=head2 update_circuit_path_state

Changes a path_instantiation state from $old_state to $new_state for circuit identified by $circuit_id. This does not create a new instantiation but actually updates the current one.

=over

=item circuit_id

The internal MySQL primary key int identifier for this circuit.

=item old_state

The state that the path instatiation should be in currently.

=item new_state

The state that the path instatiation should be set to.

=back

=cut

sub update_circuit_path_state {
    my $self = shift;
    my %args = @_;

    my $circuit_id  = $args{'circuit_id'};
    my $old_state   = $args{'old_state'};
    my $new_state   = $args{'new_state'};

    $self->_start_transaction();

    my $query = "update path_instantiation set path_state = ? " .
	        " where end_epoch = -1 and path_state = ? " .
		" and path_instantiation.path_id in (select path_id from path where circuit_id = ?)";

    my $result = $self->_execute_query($query, [$new_state, $old_state, $circuit_id]);

    if (! defined $result){
	$self->_set_error("Unable to update path instantiation for circuit $circuit_id");
	$self->_rollback();
	return;
    }

    $self->_commit();

    return 1;
}

=head2 update_circuit_name

=cut
sub update_circuit_name{
    my $self = shift;
    my %args = @_;

    return if !defined($args{'circuit_id'});
    return if (!defined($args{'circuit_name'}) || $args{'circuit_name'} eq '');

    my $query = "update circuit set name = ? where circuit_id = ?";

    if(!defined($self->_execute_query($query, [$args{'circuit_name'},$args{'circuit_id'}]))){
	return 0;
    }

    return 1;
}

=head2 switch_circuit_to_alternate_path

Changes a circuit's records over to its available path. If the circuit is presently
on the primary path it will attempt to go onto backup and vice versa.

I<This does not actually do any provisioning, it just changes the records in the database.>

=over

=item circuit_id

The internal MySQL primary key int identifier for this circuit.

=back

=cut

# sub switch_circuit_to_alternate_path {
#     my $self = shift;
#     my %args = @_;

#     my $query;

#     my $circuit_id     = $args{'circuit_id'};

#     my $new_active_path_id = $self->circuit_has_alternate_path(circuit_id => $circuit_id );

#     if(!$new_active_path_id){
# 	$self->_set_error("Circuit $circuit_id has no alternate path, refusing to try to switch to alternate.");
# 	return;
#     }

#     $self->_start_transaction();


#     # grab the path_id of the one we're switching away from
#     $query = "select path_instantiation.path_id, path_instantiation.path_instantiation_id from path " .
# 	     " join path_instantiation on path.path_id = path_instantiation.path_id " .
# 	     " where path_instantiation.path_state = 'active' and path_instantiation.end_epoch = -1 " .
# 	     " and path.circuit_id = ?";

#     my $results = $self->_execute_query($query, [$circuit_id]);

#     if (! defined $results || @$results < 1){
# 	$self->_set_error("Unable to find path_id for current path.");
# 	$self->_rollback();
# 	return;
#     }

#     my $old_active_path_id   = @$results[0]->{'path_id'};
#     my $old_instantiation    = @$results[0]->{'path_instantiation_id'};

#     # decom the current path instantiation
#     $query = "update path_instantiation set path_instantiation.end_epoch = unix_timestamp(NOW()) " .
# 	     " where path_instantiation.path_id = ? and path_instantiation.end_epoch = -1";

#     my $success = $self->_execute_query($query, [$old_active_path_id]);

#     if (! $success ){
# 	$self->_set_error("Unable to change path_instantiation of current path to inactive.");
# 	$self->_rollback();
# 	return;
#     }

#     # create a new path instantiation of the old path
#     $query = "insert into path_instantiation (path_id, start_epoch, end_epoch, path_state) " .
# 	     " values (?, unix_timestamp(NOW()), -1, 'available')";

#     my $new_available = $self->_execute_query($query, [$old_active_path_id]);

#     if (! defined $new_available){
# 	$self->_set_error("Unable to create new available path based on old instantiation.");
# 	$self->_rollback();
# 	return;
#     }

#     # point the internal vlan mappings from the old over to the new path instance
#     #$query = "update path_instantiation_vlan_ids set path_instantiation_id = ? where path_instantiation_id = ?";

#     #$success = $self->_execute_query($query, [$new_available, $old_instantiation]);

#     if (! defined $success){
# 	$self->_set_error("Unable to move internal vlan id mappings over to new path instance.");
# 	$self->_rollback();
# 	return;
#     }

#     # at this point, the old path instantiation has been decom'd by virtue of its end_epoch
#     # being set and another one has been created in 'available' state based on it.

#     # now let's change the state of the old available one to active
#     $query = "update path_instantiation set path_state = 'active' where path_id = ? and end_epoch = -1";

#     $success = $self->_execute_query($query, [$new_active_path_id]);

#     if (! $success){
# 	$self->_set_error("Unable to change state to active in alternate path.");
# 	$self->_rollback();
# 	return;
#     }

#     $self->_commit();

#     return 1;
# }

=head2 circuit_has_alternate_path

Returns whether or not the circuit given has an alternate path available. Presently this only checks to see
if an available path instantiation is available, though it should also in the future determine whether that path
is even valid based on port / link statuses along the path.

=over

=item circuit_id

The internal MySQL primary key int identifier for this circuit.

=back

=cut

sub circuit_has_alternate_path {
    my $self = shift;
    my %args = @_;

    my $circuit_id = $args{'circuit_id'};
    my $query  = "select path.path_id from path " .
	         " join path_instantiation on path.path_id = path_instantiation.path_id " .
		 "  and path_instantiation.path_state = 'available' and path_instantiation.end_epoch = -1 " .
	         " where circuit_id = ?";

    my $result = $self->_execute_query($query, [$circuit_id]);

    if (! defined $result){
	$self->_set_error("Internal error determing if circuit has available alternate path.");
	return;
    }

    if (@$result > 0){
	return $result->[0]->{'path_id'};
    }

    return;
}

=head2 get_affected_circuits_by_link_id

Returns an array of hashes containing base circuit information for all active circuits that have a current
component across the link identified by $link_id.

=over

=item link_id

The internal MySQL primary key int identifier for this link.

=back

=cut

sub get_affected_circuits_by_link_id {
    my $self = shift;
    my %args = @_;

    my $link = $args{'link_id'};


    my $query = "select circuit.name, circuit.circuit_id, circuit_instantiation.circuit_state as state from circuit " .
	        " join circuit_instantiation on circuit.circuit_id = circuit_instantiation.circuit_id " .
		"  and circuit_instantiation.end_epoch = -1 and circuit_instantiation.circuit_state = 'active' " .
		" join path on path.circuit_id = circuit.circuit_id " .
		" join path_instantiation on path_instantiation.path_id = path.path_id " .
		"  and path_instantiation.end_epoch = -1 and path_instantiation.path_state = 'active' " .
		" join link_path_membership on link_path_membership.path_id = path.path_id " .
		" join link on link.link_id = link_path_membership.link_id and link_path_membership.end_epoch = -1" .
		"  where link.link_id = ?";

    my @circuits;

    my $results = $self->_execute_query($query, [$link]);

    if (! defined $results){
	return;
    }

    foreach my $circuit (@$results){
	push(@circuits, {"name" => $circuit->{'name'},
			 "id"   => $circuit->{'circuit_id'},
			 "state" => $circuit->{'state'}
	                 }
	    );
    }

    return \@circuits;
}

=head2 is_external_vlan_available_on_interface

Returns a boolean indicating whether or not the given tag is currently available (ie not actively in use) on the interface
identified by $interface_id. This should only be used to check for edge interfaces and not the internal vlan tags
specific to the OESS forwarding rules.

=over

=item vlan

The vlan tag. This should be a number from 1 to 4096.

=item interface_id

The internal MySQL primary key int identifier for this interface.

=back

=cut

sub is_external_vlan_available_on_interface {
    my $self = shift;
    my %args = @_;

    my $vlan_tag     = $args{'vlan'};
    my $interface_id = $args{'interface_id'};
    my $circuit_id = $args{'circuit_id'};

    if(!defined($interface_id)){
	$self->_set_error("No Interface ID Specified");
	return undef
    }

    if(!defined($vlan_tag)){
	$self->_set_error("No VLAN Tag specified");
	return undef
    }

    my $query = "select circuit.name, circuit.circuit_id from circuit join circuit_edge_interface_membership " .
	        " on circuit.circuit_id = circuit_edge_interface_membership.circuit_id " .
		" where circuit_edge_interface_membership.interface_id = ? " .
		"  and circuit_edge_interface_membership.extern_vlan_id = ? " .
		"  and circuit_edge_interface_membership.end_epoch = -1";

    my $result = $self->_execute_query($query, [$interface_id, $vlan_tag]);

    if (! defined $result){
	$self->_set_error("Internal error while finding available external vlan tags.");
	return;
    }

    $query = "select * from interface where interface.interface_id = ?";

    my $interface = $self->_execute_query( $query, [$interface_id])->[0];

    my $tags = $self->_process_tag_string($interface->{'vlan_tag_range'});


    #first verify tag is in available range
    my $found = 0;
    foreach my $tag (@$tags){
	if($tag == $vlan_tag){
	    $found = 1;
	}
    }

    if(!$found){
	return 0;
    }

    #verify no other circuit is using it
    if (@$result > 0){
	if(defined($circuit_id)){
	    foreach my $circuit (@$result){
		if($circuit->{'circuit_id'} == $circuit_id){
		    #no problem here, we are editing the circuit
		}else{
		    warn "In Use on another circuit\n";
                    $self->_set_error("VLAN Tag already in use on another circuit");
		    return 0;
		}
	    }
	}else{
            warn "In Use on another circuit\n";
            $self->_set_error("VLAN Tag already in use on another circuit");
            return 0;
        }
    }

    return 1;
}

=head2 get_user_by_id

=cut

sub get_user_by_id {
    my $self = shift;
    my %args = @_;

    my $user_id = $args{'user_id'};
    if(!defined($user_id)){
	$self->_set_error("user_id was not defined");
	return;
    }

    my $query = "select * from user left join remote_auth on user.user_id = remote_auth.user_id where user.user_id = ?";
    return $self->_execute_query($query,[$user_id]);
}

=head2 get_user_admin_status

=cut
sub get_user_admin_status{
	my $self = shift;
	my %args = @_;
	my $username = $args{'username'};
	my $user_id  = $args{'user_id'};

    if(!defined($username) && !defined($user_id)){
	    $self->_set_error("user_id or username must be defined");
        return []; 
    }

	my $query = "select a.auth_name, 1 as is_admin ";
    $query   .= "from user u ";
    $query   .= "join remote_auth a on (u.user_id = a.user_id) ";
    $query   .= "join user_workgroup_membership m on (u.user_id = m.user_id) ";
    $query   .= "join workgroup w on (m.workgroup_id = w.workgroup_id) ";
    $query   .= "where w.type='admin' ";
    $query   .= "and a.auth_name = ? " if($username);
    $query   .= "and u.user_id = ? " if($user_id);
    $query   .= "limit 1";

    my $params = [];
    push(@$params, $username) if($username);
    push(@$params, $user_id)  if($user_id);

	return $self->_execute_query($query,$params);

}

=head2 get_user_id_by_given_name

Returns the internal user_id for a user identified by $name.

=over

=item name

The given name of the user.

=back

=cut

sub get_user_id_by_given_name {
    my $self = shift;
    my %args = @_;

    my $name = $args{'name'};
    if(!defined($name)){
	$self->_set_error("user name was not defined\n");
	return;
    }
    my $query = "select user_id from user where given_names = ?";

    my $result = $self->_execute_query($query, [$name]);

    if (! defined $result || @$result < 1){
	$self->_set_error("Unable to find user $name");
	return;
    }

    return @$result[0]->{'user_id'};
}

=head2 get_user_id_by_auth_name

Returns the internal user id of the user who has the associated auth_name of $auth_name.

=over

=item auth_name

The auth_name of the user. This is likely what you would get in $ENV{'REMOTE_USER'} in a protected http environment, for example.

=back

=cut

sub get_user_id_by_auth_name {
    my $self = shift;
    my %args = @_;

    my $auth_name = $args{'auth_name'};

    my $query = "select user.user_id from user join remote_auth on remote_auth.user_id = user.user_id where remote_auth.auth_name = ?";

    my $user_id = $self->_execute_query($query, [$auth_name])->[0]->{'user_id'};

    return $user_id;
}


=head2 get_remote_nodes

Returns an array of hashes containing information for all nodes that belong to non local networks.

=cut

sub get_remote_nodes {
    my $self = shift;
    my %args = @_;

    my $query = "select network.name as network, node_id, node.name, node.longitude, node.latitude from node " .
	" join network on network.network_id = node.network_id " .
	" where network.is_local = 0 order by network, name";

    my $rows = $self->_execute_query($query, []);

    if (! defined $rows){
	$self->_set_error("Internal error fetching remote nodes.");
	return;
    }

    my @results;

    foreach my $row (@$rows){
	push(@results, {"node_id"   => $row->{'node_id'},
			"name"      => $row->{'name'},
			"longitude" => $row->{'longitude'},
			"latitude"  => $row->{'latitude'},
			"network"   => $row->{'network'}
	                }
	    );
    }

    return \@results;
}

=head2 get_node_dpid_hash

Returns an array of hashes containing base information for active nodes.

=cut

sub get_node_dpid_hash {
    my $self = shift;
    my %args = @_;

    my $sth = $self->_prepare_query("select node.node_id, node_instantiation.dpid, inet_ntoa(node_instantiation.management_addr_ipv4) as address, " .
                                    " node.name, node.longitude, node.latitude " .
                                    " from node join node_instantiation on node.node_id = node_instantiation.node_id " .
                                    " where node_instantiation.admin_state = 'active'"
                                   ) or return;

    $sth->execute();

    my $results = {};

    while (my $row = $sth->fetchrow_hashref()){
	$results->{$row->{'name'}} = $row->{'dpid'};
    }

    return $results;
}

=head2 get_current_nodes

=cut

sub get_current_nodes{
    my $self = shift;

    my $nodes = $self->_execute_query("select node.max_flows, node.in_maint, node.name, node_instantiation.dpid,node.operational_state,node.node_id, node.send_barrier_bulk from node,node_instantiation where node.node_id = node_instantiation.node_id and node_instantiation.end_epoch = -1 and node_instantiation.admin_state = 'active' order by node.name",[]);

    return $nodes;
}

=head2 add_link

=cut

sub add_link{
    my $self = shift;
    my %args = @_;

    if(!defined($args{'name'})){
	$self->_set_error("No Name was defined");
	return;
    }

    my $res = $self->_execute_query("insert into link (name, remote_urn,status,vlan_tag_range) VALUES (?, ?,'up', ?)",
				    [$args{'name'}, $args{'remote_urn'}, $args{'vlan_tag_range'}]);

    if(defined($res)){
	return $res;
    }

    $self->_set_error("Problem creating link");
    return;

}


=head2 edit_link

=cut

sub edit_link {
    my $self = shift;
    my %args = @_;
    my $link_id = $args{'link_id'};
    if (!defined($args{'link_id'})) {
        $self->_set_error("No Link id was defined");
        return;
    }
    my $res = $self->_execute_query("update link set name = ?, remote_urn =?, status= ?, vlan_tag_range = ? where link_id = ?",
        [$args{'name'}, $args{'remote_urn'}, $args{'status'}, $args{'vlan_tag_range'}, $link_id]);

    if(defined($res)){
        return $res;
    }

    $self->_set_error("Problem editing link");
    return;

}

=head2 create_link_instantiation

=cut

sub create_link_instantiation{
    my $self = shift;
    my %args = @_;
    if(!defined($args{'link_id'})){
	$self->_set_error("Link ID was not specified");
	return;
    }

    if(!defined($args{'state'})){
	$args{'state'} = "Unknown";
    }

    if(!defined($args{'interface_a_id'})){
	$self->_set_error("Interface A was not specified");
	return;
    }

    if(!defined($args{'interface_z_id'})){
	$self->_set_error("Interface Z was not specified");
	return;
    }

    my $res = $self->_execute_query("insert into link_instantiation (link_id,end_epoch,start_epoch,link_state,interface_a_id,interface_z_id) VALUES (?,-1,UNIX_TIMESTAMP(NOW()),?,?,?)",[$args{'link_id'},$args{'state'},$args{'interface_a_id'},$args{'interface_z_id'}]);

    if(!defined($res)){
	return;
    }

    return $res;


}


=head2 decom_link_instantiation

=cut

sub decom_link_instantiation{
    my $self = shift;
    my %args = @_;

    if(!defined($args{'link_id'})){
	$self->_set_error("No Link ID Specified to decom_link_instantiation");
	return;
    }

    my $res = $self->_execute_query("update link_instantiation set end_epoch = UNIX_TIMESTAMP(NOW()) where link_id = ? and end_epoch = -1",[$args{'link_id'}]);

    return 1;

}

=head2 get_edge_links

=cut

sub get_edge_links{
    my $self = shift;
    my $reserved_bw = shift;
    my $links = $self->_execute_query("select link.link_id, link.name,link.metric, link_instantiation.interface_a_id, link_instantiation.interface_z_id, node_a.name as node_a_name,node_b.name as node_b_name,least(interface_inst_a.capacity_mbps,interface_inst_b.capacity_mbps) as link_capacity, sum(reserved_bandwidth_mbps) as reserved_bw_mbps, link.metric from link_instantiation,interface as interface_a,interface as interface_b,node as node_a, node as node_b, interface_instantiation as interface_inst_a, interface_instantiation as interface_inst_b,link left join link_path_membership on link_path_membership.link_id=link.link_id and link_path_membership.end_epoch=-1  left join path on link_path_membership.path_id=path.path_id left join path_instantiation on path_instantiation.path_id=path.path_id and path_instantiation.end_epoch=-1 and path_instantiation.path_state='active' left join circuit on path.circuit_id=circuit.circuit_id left join circuit_instantiation on circuit.circuit_id=circuit_instantiation.circuit_id and circuit_instantiation.circuit_state='active' where link.link_id=link_instantiation.link_id and link_instantiation.link_state = 'active' and interface_inst_a.end_epoch=-1 and interface_inst_a.interface_id=interface_a.interface_id and link_instantiation.end_epoch=-1 and  interface_a.node_id=node_a.node_id and interface_b.node_id=node_b.node_id and link_instantiation.interface_a_id=interface_a.interface_id and link_instantiation.interface_z_id=interface_b.interface_id and interface_inst_b.end_epoch=-1 and interface_inst_b.interface_id=interface_b.interface_id and interface_a.operational_state = 'up' and interface_b.operational_state = 'up' group by link.link_id", []); # having (link_capacity-(IFNULL(reserved_bw_mbps,0)))>?",[$reserved_bw]);
    # TEMPORARY HACK UNTIL OPENFLOW PROPERLY SUPPORTS QUEUING. WE CANT
    # DO BANDWIDTH RESERVATIONS SO FOR NOW ASSUME EVERYTHING HAS 0 BANDWIDTH RESERVED
    # AND EVERY LINK IS AVAILABLE

    return $links;

}


=head2 get_node_interfaces

Returns an array of hashes containing base information about edge interfaces that are currently up on the given node. If a workgroup
id is given, it limits the intefaces to those presently available to that workgroup.

=over

=item node

The name of the node to query.

=item workgroup_id (optional)

=item show_down (optional)

The internal MySQL primary key int identifier for this workgroup.

=back

=cut

sub get_node_interfaces {
    my $self = shift;
    my %args = @_;

    my $node_name    = $args{'node'};
    my $workgroup_id = $args{'workgroup_id'};
    my $show_down    = $args{'show_down'};
    my $show_trunk   = $args{'show_trunk'} || 0;

    if(!defined($show_down)){
	$show_down = 0;
    }
    my @query_args;

    push(@query_args, $node_name);

    my $query = "select interface.role,interface.vlan_tag_range,interface.port_number,interface.operational_state, interface.name, interface.description, interface.interface_id, interface.workgroup_id, workgroup.name as workgroup_name from interface " .
	        " join node on node.name = ? and node.node_id = interface.node_id " .
            " left join workgroup on interface.workgroup_id = workgroup.workgroup_id " .
		" join interface_instantiation on interface_instantiation.end_epoch = -1 and interface_instantiation.interface_id = interface.interface_id ";

    # get all the interfaces that have an acl rule that applies to this workgroup
    # only used if workgroup_id is passed in
    my $acl_query = "select interface.role, interface.port_number, interface.description,interface.operational_state as operational_state, interface.name as int_name, interface.interface_id, node.name as node_name, node.node_id, interface_acl.vlan_start, interface_acl.vlan_end, interface.workgroup_id, workgroup.name as workgroup_name " .
            " from interface_acl " .
        "  join interface on interface.interface_id = interface_acl.interface_id " .
        "  left join workgroup on interface.workgroup_id = workgroup.workgroup_id " .
        "  join interface_instantiation on interface.interface_id = interface_instantiation.interface_id " .
        "    and interface_instantiation.end_epoch = -1" .
        "  join node on node.node_id = interface.node_id " .
        "  join node_instantiation on node.node_id = node_instantiation.node_id " .
        "    and node_instantiation.end_epoch = -1 " .
        " where (interface_acl.workgroup_id = ? " .
        " or interface_acl.workgroup_id IS NULL) " .
        " and node.name = ? ";


    if ($show_trunk == 0){
        $query     .= " where interface.role != 'trunk' ";
        $acl_query .= " and interface.role != 'trunk' ";
    }
    if($show_down == 0){
	    $query .= " and interface.operational_state = 'up' ";
	    $acl_query .= " and interface.operational_state = 'up' ";
    }

    if (defined $workgroup_id){
	    push(@query_args, $workgroup_id);
	    $query .= " and interface.workgroup_id = ?";
    }


    my $rows = $self->_execute_query($query, \@query_args);


    my @results;
    # if workgroup id was passed in we must execute the acl_query to get
    # all of the available interfaces

    # finish up acl query
    $acl_query .= " group by interface_acl.interface_id " .
                  " order by node_name ASC, int_name ASC";
    my %interface_already_added;
    if(defined $workgroup_id){
        my $available_interfaces = $self->_execute_query($acl_query, [
            $workgroup_id,
            $node_name
        ]);
        foreach my $available_interface (@$available_interfaces){
            my $vlan_tag_range = $self->_validate_endpoint(
                interface_id => $available_interface->{'interface_id'},
                workgroup_id => $workgroup_id
            );
            # keep track of this b/c we don't want to add the owned interface again
            $interface_already_added{$available_interface->{'interface_id'}} = 1;
            if($vlan_tag_range) {
                push(@results, {
                    "name"           => $available_interface->{'int_name'},
			        "description"    => $available_interface->{'description'},
			        "interface_id"   => $available_interface->{'interface_id'},
			        "port_number"    => $available_interface->{'port_number'},
			        "status"         => $available_interface->{'operational_state'},
			        "vlan_tag_range" => $vlan_tag_range,
			        "int_role"       => $available_interface->{'role'},
                    "workgroup_id"   => $available_interface->{'workgroup_id'},
                    "workgroup_name"   => $available_interface->{'workgroup_name'}
	            });
            }
        }
    }

    # push on the initial rows
    foreach my $row (@$rows){
        # skip if we already added this interface b/c of an acl rule
        next if($interface_already_added{$row->{'interface_id'}});

        my $vlan_tag_range = $row->{'vlan_tag_range'};
        if($workgroup_id) {
            $vlan_tag_range = $self->_validate_endpoint(
                interface_id => $row->{'interface_id'},
                workgroup_id => $workgroup_id
            );
        }

	    push(@results, {
            "name"           => $row->{'name'},
			"description"    => $row->{'description'},
			"interface_id"   => $row->{'interface_id'},
			"port_number"    => $row->{'port_number'},
			"status"         => $row->{'operational_state'},
			"vlan_tag_range" => $vlan_tag_range,
			"int_role"       => $row->{'role'},
            "workgroup_id"   => $row->{'workgroup_id'},
            "workgroup_name" => $row->{'workgroup_name'}
	    });
    }

    return \@results;

}

=head2 get_map_layers

Returns information such as name, capacity, position, and status about the current network layout including nodes and the links between them.

=cut

sub get_map_layers {
    my $self = shift;
    my %args = @_;

    my $workgroup_id= $args{'workgroup_id'};
    my $dbh = $self->{'dbh'};

    # grab only the local network
    my $query = <<HERE;
    select network.longitude as network_long,
    network.latitude as network_lat,
    network.name as network_name,
    node.longitude as node_long,
    node.max_flows,
    node.tx_delay_ms,
    node.latitude as node_lat,
    node.name as node_name,
    node.node_id,
    node.vlan_tag_range,
    node.node_id as node_id,
    node.default_drop as default_drop,
    node.default_forward as default_forward,
    node.send_barrier_bulk as barrier_bulk,
    node.max_static_mac_flows as max_static_mac_flows,
    node_instantiation.dpid as dpid,
    node.in_maint,
    maintenance.end_epoch 
    from node
    join node_instantiation on node.node_id = node_instantiation.node_id and node_instantiation.end_epoch = -1 
    and  node_instantiation.admin_state = 'active'
    join network on node.network_id = network.network_id and network.is_local = 1
    left join  node_maintenance on node.node_id = node_maintenance.node_id
    left join  maintenance on node_maintenance.maintenance_id = maintenance.maintenance_id
HERE
        
    my $networks;
    
    my $rows = $self->_execute_query($query);
    
    my $nodes_endpoints= {};
    
    
    
    #default_count_endpoints for when there are no results, if we have no workgroup_id return 1.
    my $default_endpoint_count=1;
    if($workgroup_id){
        $default_endpoint_count=0;
        foreach my $row(@$rows){
            my $ints = $self->get_node_interfaces(
                node => $row->{'node_name'},
                workgroup_id => $workgroup_id,
                show_down => 1
            );
            my $count = @$ints;
            $nodes_endpoints->{$row->{'network_name'}}{$row->{'node_name'}} = $count;
        }
    }

    my $network_name = "";

    foreach my $row(@$rows){
            
        $network_name = $row->{'network_name'};
        my $node_name    = $row->{'node_name'};
        my $avail_endpoints = ( defined($nodes_endpoints->{$network_name}->{$node_name})? $nodes_endpoints->{$network_name}->{$node_name} : $default_endpoint_count);
            
            
        $networks->{$network_name}->{'meta'} = {"network_long" => $row->{'network_long'},
                            "network_lat"  => $row->{'network_lat'},
                            "network_name" => $network_name,
                            "local"        => 1
        };
            
        $networks->{$network_name}->{'nodes'}->{$node_name} = {"node_name"    => $node_name,
                                                                   "node_id"      => $row->{'node_id'},
                                       "node_lat"     => $row->{'node_lat'},
                                       "node_long"    => $row->{'node_long'},
                                       "node_id"      => $row->{'node_id'},
                                       "vlan_range"   => $row->{'vlan_tag_range'},
                                       "default_drop" => $row->{'default_drop'},
                                       "default_forward" => $row->{'default_forward'},
                                       "max_static_mac_flows" => $row->{'max_static_mac_flows'},
                                       "max_flows"    => $row->{'max_flows'},
                                       "tx_delay_ms" => $row->{'tx_delay_ms'},
                                       "dpid"         => sprintf("%x",$row->{'dpid'}),
                                       "barrier_bulk" => $row->{'barrier_bulk'},
                                       "end_epoch"   => $row->{"end_epoch"},
                                       "number_available_endpoints" => $avail_endpoints,
                                       "in_maint"   => $row->{"in_maint"}
            };
            
        # make sure we have an array even if we never get any links for this node
        if (! exists $networks->{$network_name}->{'links'}->{$node_name}){
            $networks->{$network_name}->{'links'}->{$node_name} = [];
        }
        
    }
    
    my $links = $self->get_current_links();

    my $link_maintenances = $self->get_link_maintenances();
    foreach my $link (@$links){
    
        my $inta = $self->get_interface( interface_id => $link->{'interface_a_id'});
        my $intb = $self->get_interface( interface_id => $link->{'interface_z_id'});
        my $maint_results = $self->get_link_maintenance($link->{'link_id'});
        my $maint_epoch;
        foreach my $link_maintenance (@$link_maintenances) {
            if ($link->{'link_id'} == $link_maintenance->{'link'}->{'id'}) {
                $maint_epoch = $link_maintenance->{'end_epoch'};
            }
            
        }

        push(@{$networks->{$network_name}->{'links'}->{$inta->{'node_name'}}},{"link_name"   => $link->{'name'},
                                                                               "link_state"  => $link->{'link_state'},
                                                                               "link_capacity" => $intb->{'speed'},
                                                                               "remote_urn"  => $link->{'remote_urn'},
                                                                               "to"          => $intb->{'node_name'},
                                                                               "link_id"     => $link->{'link_id'},
                                                                               "maint_epoch" => $maint_epoch});

        push(@{$networks->{$network_name}->{'links'}->{$intb->{'node_name'}}},{"link_name"   => $link->{'name'},
                                                                               "link_state"  => $link->{'link_state'},
                                                                               "remote_urn"  => $link->{'remote_urn'},
                                                                               "link_capacity" => $inta->{'speed'},
                                                                               "to"          => $inta->{'node_name'},
                                                                               "link_id"     => $link->{'link_id'},
                                                                                "maint_epoch" => $maint_epoch});
    }
  

    # now grab the foreign networks (no instantiations, is_local = 0)
    $query = "select network.longitude as network_long, network.latitude as network_lat, network.name as network_name, network.network_id as network_id, " .
	" node.longitude as node_long, node.latitude as node_lat, node.name as node_name, node.node_id as node_id " .
	" from network " .
	"  join node on node.network_id = network.network_id " .
	" where network.is_local = 0";

    $rows = $self->_execute_query($query, []);
    if($workgroup_id && @$rows ){
        foreach my $row(@$rows){
            my $ints = $self->get_node_interfaces(
                node => $row->{'node_name'},
                workgroup_id => $workgroup_id,
                show_down => 1
            );
            my $count = @$ints;
            $nodes_endpoints->{$row->{'network_name'}}{$row->{'node_name'}} = $count;
        }
    }

    foreach my $row (@$rows){

        my $node_id      = $row->{'node_id'};
        my $network_id   = $row->{'network_id'};
        my $network_name = $row->{'network_name'};
        my $node_name    = $row->{'node_name'};
        my $avail_endpoints = ( defined($nodes_endpoints->{$network_name}->{$node_name})? $nodes_endpoints->{$network_name}->{$node_name} : $default_endpoint_count);
        $networks->{$network_name}->{'meta'} = {"network_long" => $row->{'network_long'},
                            "network_lat"  => $row->{'network_lat'},
                            "network_name" => $network_name,
                            "local"        => 0
        };

        my $node_lat = $row->{'node_lat'};
        my $node_lon = $row->{'node_long'};

        if ($node_lat eq 0 && $node_lon eq 0){
            $node_lat  = $row->{'network_lat'};
            $node_lon  = $row->{'network_long'};
        }

        $networks->{$network_name}->{'nodes'}->{$node_name} = {"node_name"    => $node_name,
                                       "node_lat"     => $node_lat,
                                       "node_long"    => $node_lon,
                                       "number_available_endpoints" => $avail_endpoints
        };

    }

    my $results = [];

    foreach my $network_name (keys %$networks){

	push (@$results, $networks->{$network_name});

    }

    return $results;

}

=head2 get_current_links

=cut

sub get_current_links {
    my $self = shift;
    #We don't set the end_epoch when a link is available or when it is decom, we only want active links ISSUE 5759
    my $query = "select * from link natural join link_instantiation where link_instantiation.end_epoch = -1 and link_instantiation.link_state = 'active' and link.remote_urn is NULL order by link.name";

    my $res = $self->_execute_query($query,[]);

    return $res;
}

=head2 get_circuits_on_link

=cut

sub get_circuits_on_link{
    my $self = shift;
    my %args = @_;

    my $link_id = $args{'link_id'};

    if(!defined($link_id)){
	return;
    }

    my $query = "select link_path_membership.end_epoch as lpm_end, circuit_instantiation.end_epoch as ci_end, circuit.*, circuit_instantiation.*, path.* from link_path_membership, path, circuit, circuit_instantiation  where path.path_id = link_path_membership.path_id and link_path_membership.link_id = ? and link_path_membership.end_epoch = -1 and circuit.circuit_id = path.circuit_id and circuit_instantiation.circuit_id = circuit.circuit_id and link_path_membership.end_epoch = -1 and circuit_instantiation.end_epoch = -1 and (circuit_instantiation.circuit_state = 'active' or circuit_instantiation.circuit_state = 'reserved' or circuit_instantiation.circuit_state = 'provisioned' or circuit_instantiation.circuit_state = 'scheduled')";

    my $circuits = $self->_execute_query($query,[$link_id]);

    return $circuits;

}

=head2 cancel_scheduled_action

=cut

sub cancel_scheduled_action{
    my $self = shift;
    my %params = @_;

    if(!defined($params{'scheduled_action_id'})){
	print "NO SCHEDULED ACTION ID SPECIFIED\n";
	return;
    }

    my $str = "delete from scheduled_action where scheduled_action_id = ?";
    my $result = $self->_execute_query($str,[$params{'scheduled_action_id'}]);
    if(defined($result)){
	return 1;
    }else{
	return;
    }
}

=head2 get_circuit_scheduled_events

Returns an array of hashes containing information about user scheduled events for this circuit.

=over

=item circuit_id

The internal MySQL primary key int identifier for this circuit.

=back

=cut

sub get_circuit_scheduled_events {
    my $self = shift;
    my %args = @_;

    my $circuit_id = $args{'circuit_id'};
    if(!defined($circuit_id)){
	return;
    }

    my $include_completed = $args{'show_completed'};
    if(!defined($include_completed)){
	$include_completed = 1;
    }


    my $events = [];

    my $query = "select user.user_id, remote_auth.auth_name, concat(user.given_names, ' ', user.family_name) as full_name, " .
	        " from_unixtime(registration_epoch) as registration_time, from_unixtime(activation_epoch) as activation_time, " .
		" scheduled_action.circuit_layout, scheduled_action.scheduled_action_id, " .
		" from_unixtime(scheduled_action.completion_epoch) as completion_time " .
		" from scheduled_action " .
		" join user on user.user_id = scheduled_action.user_id " .
		" left join remote_auth on remote_auth.user_id = user.user_id " .
		" where scheduled_action.circuit_id = ?";

    if($include_completed != 1){
	$query .= " and scheduled_action.completion_epoch = -1";
    }

    my $sth = $self->_prepare_query($query);

    $sth->execute($circuit_id) or die "Failed execute: $DBI::errstr";

    while (my $row = $sth->fetchrow_hashref()){
	push (@$events, {"username"  => $row->{'auth_name'},
			 "fullname"  => $row->{'full_name'},
			 "scheduled" => $row->{'registration_time'},
			 "activated" => $row->{'activation_time'},
			 "layout"    => $row->{'circuit_layout'},
			 "completed" => $row->{'completion_time'},
			 "user_id"   => $row->{'user_id'},
			 "scheduled_action_id" => $row->{'scheduled_action_id'}
	      });
    }

    return $events;
}


=head2 get_circuit_history

Returns an array of hashes containing information about events for this circuit that have were network driven, such as links going down or
ports and nodes dropping off the network.

=over

=item circuit_id

The internal MySQL primary key int identifier for this circuit.

=back

=cut

sub get_circuit_history {
    my $self = shift;
    my %args = @_;

    my $events;

    my $circuit_id = $args{'circuit_id'};

    # figure out past instantiations during this circuit's life
    my $query = "select remote_auth.auth_name, concat(user.given_names, ' ', user.family_name) as full_name, " .
	     " from_unixtime(circuit_instantiation.end_epoch) as end_time, " .
	     " from_unixtime(circuit_instantiation.start_epoch) as start_time " .
	     " from circuit " .
	     " join circuit_instantiation on circuit.circuit_id = circuit_instantiation.circuit_id " .
	     " join user on user.user_id = circuit_instantiation.modified_by_user_id " .
	     " left join remote_auth on remote_auth.user_id = user.user_id " .
	     "where circuit.circuit_id = ?";

    my $results = $self->_execute_query($query, [$circuit_id]);

    if (! defined $results){
	$self->_set_error("Internal error fetching circuit instantiation events.");
	return;
    }

    foreach my $row (@$results){
	push (@$events, {"username"  => $row->{'auth_name'},
			 "fullname"  => $row->{'full_name'},
			 "scheduled" => -1,
			 "activated" => $row->{'start_time'},
			 "layout"    => "",
			 "completed" => $row->{'end_time'}
	      }
	    );
    }

    return $events;
}

=head2 get_workgroups

Returns an array of hashes containing basic information for all workgroups.

=cut

sub get_workgroups {
    my $self = shift;

    my %args = ( 
        'user_id' => undef,
		 @_,
	);

    my @dbargs = ();
    my $workgroups = [];
    my $sql="select w.workgroup_id, w.name,w.type, w.external_id, w.max_mac_address_per_end, w.max_circuits, w.max_circuit_endpoints from workgroup w ";

    if(defined $args{'user_id'}){
	$sql .= "join user_workgroup_membership m on w.workgroup_id = m.workgroup_id ".
	    "join user u on m.user_id = u.user_id and u.user_id = ?";

	push(@dbargs, $args{'user_id'});
    }

    $sql .= " where w.status = 'active'";
    $sql .= " order by w.name";
    my $results = $self->_execute_query($sql,\@dbargs);

#    if (! defined $results){
#	$self->_set_error("Internal error while fetching workgroups");
#	return;
#    }

    foreach my $workgroup (@$results){
	push (@$workgroups, {
            workgroup_id => $workgroup->{'workgroup_id'},
            name         => $workgroup->{'name'},
            external_id  => $workgroup->{'external_id'},
            type         => $workgroup->{'type'},
            max_circuits => $workgroup->{'max_circuits'},
            max_circuit_endpoints => $workgroup->{'max_circuit_endpoints'},
            max_mac_address_per_end => $workgroup->{'max_mac_address_per_end'}
	      });
    }

    return $workgroups;
}

=head2 update_workgroup

=cut

sub update_workgroup {
    my $self = shift;
    my %args = @_;

    my $results = $self->_execute_query("update workgroup set name = ?, external_id = ?, max_mac_address_per_end = ?, max_circuits = ?, max_circuit_endpoints = ? where workgroup_id = ?",[$args{'name'},$args{'external_id'},$args{'max_mac_address_per_end'}, $args{'max_circuits'}, $args{'max_circuit_endpoints'}, $args{'workgroup_id'}]);

    if(!defined($results)){
	$self->_set_error("Internal error while fetching workgroups");
	return;
    }

    return $results;

}

=head2 get_workgroup_by_id

=cut

sub get_workgroup_by_id{
    my $self = shift;
    my %args = @_;

    my $results = $self->_execute_query("select * from workgroup where workgroup_id = ?",[$args{'workgroup_id'}])->[0];

    if (! defined $results){
	$self->_set_error("Internal error while fetching workgroups");
        return;
    }


    return $results
}

=head2 get_workgroup_details_by_name

Returns the details for a workgroup with the name $name.

=over

=item name

The name of the workgroup to get details for.

=back

=cut

sub get_workgroup_details_by_name {
    my $self = shift;
    my %args = @_;

    my $name = $args{'name'};

    my $result = $self->_execute_query("select workgroup_id, name, description from workgroup where name = ?", [$name]);

    if (! defined $result){
	$self->_set_error("Internal error while fetching workgroup details.");
	return;
    }

    return @$result[0];
}

=head2 get_workgroup_details_by_id

=cut
sub get_workgroup_details_by_id{
    my $self = shift;
    my %args = @_;

    my $workgroup_id = $args{'workgroup_id'};

    my $result = $self->_execute_query("select workgroup_id, name, description from workgroup where workgroup_id = ?", [$workgroup_id]);

    if (! defined $result){
        $self->_set_error("Internal error while fetching workgroup details.");
        return;
    }

    return @$result[0];
}

=head2 get_workgroup_details

Returns the details for a workgroup identified by $workgroup_id.

=over

=item workgroup_id

The internal MySQL primary key int identifier for this workgroup.

=back

=cut

sub get_workgroup_details {
    my $self = shift;
    my %args = @_;

    my $workgroup_id = $args{'workgroup_id'};

    my $result = $self->_execute_query("select workgroup_id, name, description from workgroup where workgroup_id = ?", [$workgroup_id]);

    if (! defined $result){
	$self->_set_error("Internal error while fetching workgroup details.");
	return;
    }

    return @$result[0];
}

=head2 get_workgroups_by_auth_name

Returns an array of hashes containing workgroup information for all workgroups that the user identified by
$auth_name has access to.

=over

=item auth_name

The auth_name of the user. This is likely what you would get in $ENV{'REMOTE_USER'} in a protected http environment, for example.

=back

=cut

sub get_workgroups_by_auth_name {
    my $self = shift;
    my %args = @_;

    my $auth_name = $args{'auth_name'};

    my $query = "select workgroup.name, workgroup.workgroup_id " .
	        " from workgroup ";
    my $results;
    # if user is admin show all workgroups regardless of membership
    my $user_id = $self->get_user_id_by_auth_name(auth_name => $auth_name);
    if($self->get_user_admin_status( 'user_id' => $user_id)->[0]{'is_admin'}) {
        $results = $self->_execute_query($query);
    } else {
        $query .= 
	    " join user_workgroup_membership on user_workgroup_membership.workgroup_id = workgroup.workgroup_id " .
		" join user on user.user_id = user_workgroup_membership.user_id " .
		" join remote_auth on remote_auth.user_id = user.user_id " .
		"  and remote_auth.auth_name = ? and workgroup.status = 'active'" .
		" order by workgroup.name ";
        $results = $self->_execute_query($query, [$auth_name]);
    }

    if (! defined $results){
	$self->_set_error("Internal error fetching user workgroups.");
	return;
    }

    my @workgroups;

    foreach my $row (@$results){
	push(@workgroups, {"name"         => $row->{'name'},
			   "workgroup_id" => $row->{'workgroup_id'}
	                  }
	    );
    }

    return \@workgroups;
}

=head2 get_workgroup_interfaces

Returns an array of hashes containing node and interface information for what interfaces are owned by this workgroup.

=over

=item workgroup_id

The internal MySQL primary key int identifier for this workgroup.

=back

=cut

sub get_workgroup_interfaces {
    my $self = shift;
    my %args = @_;

    my $workgroup_id = $args{'workgroup_id'};
    if (!defined $workgroup_id){
	    $self->_set_error("Must pass in a workgroup_id.");
	    return;
    }

    if(!defined($workgroup_id)){
	return;
    }

    my $interfaces = [];

    my $query = "select interface.description,interface.operational_state as operational_state, interface.name as int_name, interface.interface_id, interface.vlan_tag_range, node.name as node_name, node.node_id " .
	        " from workgroup " .
		"  join interface on interface.workgroup_id = workgroup.workgroup_id " .
		"  join interface_instantiation on interface.interface_id = interface_instantiation.interface_id " .
		"    and interface_instantiation.end_epoch = -1" .
		"  join node on node.node_id = interface.node_id " .
		"  join node_instantiation on node.node_id = node_instantiation.node_id " .
		"    and node_instantiation.end_epoch = -1 " .
		" where workgroup.workgroup_id = ? " .
		"order by node_name ASC, int_name ASC";

    my $results = $self->_execute_query($query, [$workgroup_id]);

    if (! defined $results){
	$self->_set_error("Internal error fetching workgroup acls.");
	return;
    }
    

    foreach my $row (@$results){

        my $links = $self->get_link_by_interface_id( interface_id => $row->{'interface_id'});
        my $remote_link = "";
        my @remote_links;
        foreach my $link (@$links){
            if(defined($link->{'remote_urn'}) && $link->{'remote_urn'} ne ''){
                #$remote_link = $link->{'remote_urn'};
                push(@remote_links, {remote_urn => $link->{'remote_urn'},
                                     vlan_tag_range => $link->{'vlan_tag_range'}});
            }
        }

	push(@$interfaces, {"interface_id"   => $row->{'interface_id'},
                            "vlan_tag_range" => $row->{'vlan_tag_range'},
                            "interface_name" => $row->{'int_name'},
                            "node_id"        => $row->{'node_id'},
                            "node_name"      => $row->{'node_name'},
                            "remote_links"    => \@remote_links,
                            "operational_state" => $row->{'operational_state'},
                            "description"    => $row->{'description'}
	     });
    }

    return $interfaces;
}

=head2 get_available_resources

Gets the resources available for a given workgroup

=over

=item workgroup_id

The workgroup_id to return the resources for

=back

=cut

sub get_available_resources {
    my $self = shift;
    my %args = @_;

    my $workgroup_id = $args{'workgroup_id'};

    if(!defined($workgroup_id)) {
	    $self->_set_error("Must pass in a workgroup_id");
        return;
    }

    # get all the interfaces the workgroup owns
    my $owned_interfaces = $self->get_workgroup_interfaces( workgroup_id => $workgroup_id ) || return;

    # get all the interfaces that have an acl rule that applies to this workgroup
    my $query = "select interface.description,interface.operational_state as operational_state, interface.name as int_name, interface.interface_id, node.name as node_name, node.node_id, interface_acl.vlan_start, interface_acl.vlan_end, interface.workgroup_id " .
            " from interface_acl " .
        "  join interface on interface.interface_id = interface_acl.interface_id " .
        "  join interface_instantiation on interface.interface_id = interface_instantiation.interface_id " .
        "    and interface_instantiation.end_epoch = -1" .
        "  join node on node.node_id = interface.node_id " .
        "  join node_instantiation on node.node_id = node_instantiation.node_id " .
        "    and node_instantiation.end_epoch = -1 " .
        " where (interface_acl.workgroup_id = ? " .
        " or interface_acl.workgroup_id IS NULL) " .
        " group by interface_acl.interface_id " .
        " order by node_name ASC, int_name ASC";

    my $interfaces = $self->_execute_query($query, [$workgroup_id]);
    if (! defined $interfaces){
        $self->_set_error("Internal error fetching accessible interfaces.");
        return;
    }
    my $available_interfaces = [];
    my %interface_already_added;
    foreach my $interface (@$interfaces) {
        my $vlan_tag_range = $self->_validate_endpoint(interface_id => $interface->{'interface_id'}, workgroup_id => $workgroup_id );
        $interface_already_added{$interface->{'interface_id'}} = 1;
        if ( $vlan_tag_range ){
            my $is_owner = 0;
            if($workgroup_id == $interface->{'workgroup_id'}){
                $is_owner = 1;
            } 
            
            my $links = $self->get_link_by_interface_id( interface_id =>  
                                                         $interface->{'interface_id'});
            my @remote_links;
            foreach my $link (@$links){
                if(defined($link->{'remote_urn'}) && $link->{'remote_urn'} ne ''){
                    push(@remote_links, {remote_urn => $link->{'remote_urn'},
                                         vlan_tag_range => $link->{'vlan_tag_range'}});
                }
            }
            
            push(@$available_interfaces, {
                "interface_id"      => $interface->{'interface_id'},
                "interface_name"    => $interface->{'int_name'},
                "node_id"           => $interface->{'node_id'},
                "node_name"         => $interface->{'node_name'},
                "operational_state" => $interface->{'operational_state'},
                "description"       => $interface->{'description'},
                "remote_links"      => \@remote_links,
                "vlan_tag_range"    => $vlan_tag_range,
                "is_owner"          => $is_owner,
		"owning_workgroup"  => $self->get_workgroup_by_id(workgroup_id => $interface->{'workgroup_id'})
            });
        }
    }
    # now push on all the owned interfaces
    foreach my $owned_interface (@$owned_interfaces) {
        # we already added this interface b/c there was an acl rule for it
        next if($interface_already_added{$owned_interface->{'interface_id'}});
        $owned_interface->{'is_owner'}   = 1;
        push(@$available_interfaces, $owned_interface);
    }

    return $available_interfaces;
}

=head2 update_interface_owner

Changes the owner of an interface.

=over

=item interface_id

The internal MySQL primary key int identifier for the interface.

=item workgroup_id

The internal MySQL primary key int identifier for this workgroup.

=back

=cut

sub update_interface_owner {
    my $self = shift;
    my %args = @_;

    if(!defined($args{'interface_id'}) || !exists($args{'workgroup_id'})){
	$self->_set_error("Invalid parameters to add workgroup, please provide a workgroup_id and an interface_id");
    return;
    }
    my $interface_id = $args{'interface_id'};
    my $workgroup_id = $args{'workgroup_id'};

    my $query;
    if(defined($args{'workgroup_id'})){
        $query = "select 1 from interface where workgroup_id = ? and interface_id = ?";
        my $results = $self->_execute_query($query, [$workgroup_id, $interface_id]);
        if (@$results > 0){
	    $self->_set_error("Interface already belongs to this workgroup.");
	    return;
        }
    }
    else {
        $query = "select 1 from interface where workgroup_id IS NOT NULL and interface_id = ?";
        my $results = $self->_execute_query($query, [$interface_id]);

        if (@$results < 1){
        $self->_set_error("Interface does not currently belong to a workgroup.");
        return;
        }
    }

    # determine if the workgroup is moving from one to another
    my $changing_workgroup = 0;
    $query = "select 1 from interface where workgroup_id IS NOT NULL and workgroup_id != ? and interface_id = ?";
    my $results = $self->_execute_query($query, [$workgroup_id, $interface_id]);
    if (@$results > 0){
        $changing_workgroup = 1;
    }


    $self->_start_transaction();

    $query = "update interface set workgroup_id = ? where interface_id = ?";
    my $success = $self->_execute_query($query, [$workgroup_id, $interface_id]);

    if (! defined $success ){
	$self->_set_error("Internal error while adding edge port to workgroup ACL.");
	$self->_rollback();
	return;
    }


    # remove prior acl rules since those were set by the old workgroup
    if(!defined($args{'workgroup_id'}) || $changing_workgroup) {
        $query = "delete from interface_acl where interface_id = ?";
        my $success = $self->_execute_query($query, [$interface_id]);
        if (! defined $success ){
	        $self->_set_error("Internal error while removing edge port to workgroup ACL.");
	        $self->_rollback();
	        return;
        }
    }

    # insert default rule if were adding a workgroup or changing workgroups
    if(defined($args{'workgroup_id'})) {
        $query = "insert into interface_acl (interface_id, allow_deny, eval_position, vlan_start, vlan_end, notes) values (?,?,?,?,?,?)";

        my $vlan_tag_range = $self->get_interface(interface_id => $interface_id)->{'vlan_tag_range'};
        my $vlan_end;
        my $vlan_start;
        if ($vlan_tag_range =~ /(^-?[0-9]*),?([0-9]*)-([0-9]*)/){
            
            #if the vlan range doesn't have a -1 in it, (i.e. it's something like 400-4032, rather than -1,1-4000) only grab the first and third capture groups.
            if ($2 eq ''){
                $vlan_start = $1;
                $vlan_end = $3;
            }
            #otherwise, just grab the first and third.
            else{
                $vlan_start = $1;
                $vlan_end = $3;
            }
        }    
 
        my $query_args = [$interface_id, 'allow', 10, $vlan_start, $vlan_end, 'Default ACL Rule' ];
        #my $query_args = [$interface_id, 'allow', 10, -1, 4095, 'Default ACL Rule' ];
        my $success = $self->_execute_query($query, $query_args);
        if (! defined $success ){
	        $self->_set_error("Internal error while adding default acl rule.");
	        $self->_rollback();
	        return;
        }
    }

    $self->_commit();

    return 1;
}

=head2 get_all_workgroups

Gets all the workgroups

=cut

sub get_all_workgroups {
    my $self = shift;

    my $workgroups = [];
    my $sql="select w.workgroup_id, w.name,w.type, w.external_id from workgroup w where w.status = 'active'";
    $sql .= " order by w.name";
    my $results = $self->_execute_query($sql);

    if (! defined $results){
    $self->_set_error("Internal error while fetching workgroups");
    return;
    }

    foreach my $workgroup (@$results){
        push (@$workgroups, {
                workgroup_id => $workgroup->{'workgroup_id'},
                name         => $workgroup->{'name'},
                external_id  => $workgroup->{'external_id'},
                type         => $workgroup->{'type'}
        });
    }

    return $workgroups;
}

=head2 start_node_maintenance
=cut
sub start_node_maintenance {
    my $self = shift;
    my $node_id = shift;
    my $description = shift;

    # Validate node exists, and grab relevant data.
    my $sql = "SELECT node.name FROM node where node_id = ?";
    my $nodes = $self->_execute_query($sql, [$node_id]);
    if (!defined @$nodes[0]) {
        $self->_set_error("Node doesn't exist.");
        return;
    }

    # Check if the node is already under maintenance.
    my $sql1 = "SELECT m.maintenance_id FROM maintenance as m, node_maintenance as n where m.maintenance_id = n.maintenance_id AND m.end_epoch = -1 AND n.node_id = ?";
    my $node_maintenance = $self->_execute_query($sql1, [$node_id]);
    if (defined @$node_maintenance[0]) {
        $self->_set_error("Node is already in maintenance mode.");
        return;
    }

    my $sql2 = "INSERT into maintenance (description, start_epoch, end_epoch) ";
    $sql2   .= "VALUES (?, unix_timestamp(NOW()), -1)";
    my $maintenance_id = $self->_execute_query($sql2, [$description]);
    if (!defined $maintenance_id) {
        $self->_set_error("Could not insert row into maintenance table.");
        return;
    }

    my $sql3 = "INSERT into node_maintenance (node_id, maintenance_id) ";
    $sql3   .= "VALUES (?, ?)";
    my $node_maintenance_id = $self->_execute_query($sql3, [$node_id, $maintenance_id]);
    if (!defined $node_maintenance_id) {
        $self->_set_error("Could not insert row into node_maintenance table.");
        return;
    }

    my $sql4 = "UPDATE node set in_maint = 'yes' where node_id = ?";
    my $update = $self->_execute_query($sql4, [$node_id]);
    if (!defined $update) {
        $self->_set_error("Could not put node into maintenance.");
        return;
    }
    
    my $m = $self->get_node_maintenance($node_id);
    if (!defined $m) {
        $self->_set_error("Could not retrieve node maintenance.");
        return;
    }

    my $result = {
        maintenance_id => $maintenance_id,
        node           => { name => @$nodes[0]->{'name'}, id => $node_id },
        description    => $description,
        start_epoch    => $m->{'start_epoch'},
        end_epoch      => $m->{'end_epoch'}
    };
    return $result;
}

=head2 end_node_maintenance
=cut
sub end_node_maintenance {
    my $self = shift;
    my $node_id = shift;
    
    my $m = $self->get_node_maintenance($node_id);
    if (!defined $m) {
        return;
    }
    
    my $sql = "UPDATE maintenance SET end_epoch = unix_timestamp(NOW()) WHERE maintenance_id = ?";
    my $result = $self->_execute_query($sql, [$m->{'maintenance_id'}]);
    if (!defined $result) {
        $self->_set_error("Internal error while ending node maintenance.");
        return;
    }
    $sql = "UPDATE node set in_maint = 'no' where node_id = ?";
    my $update = $self->_execute_query($sql, [$node_id]);
    if (!defined $update) {
        $self->_set_error("Could not remove node from maintenance.");
        return;
    }
    return $result;
}

=head2 get_node_maintenance
=cut
sub get_node_maintenance {
    my $self = shift;
    my $node_id = shift;

    my $sql = "SELECT m.maintenance_id, m.description, node.name, node.node_id, m.start_epoch, m.end_epoch ";
    $sql   .= "FROM maintenance as m, node as node, node_maintenance as info ";
    $sql   .= "WHERE m.maintenance_id = info.maintenance_id ";
    $sql   .= "AND info.node_id = node.node_id ";
    $sql   .= "AND node.node_id = ? ";
    $sql   .= "AND m.end_epoch = -1";

    my $maintenance = $self->_execute_query($sql, [$node_id]);
    my $m = @$maintenance[0];
    if (!defined $m) {
        $self->_set_error("Internal error while fetching node maintenance.");
        return;
    }
    
    my $result = {
        maintenance_id => $m->{'maintenance_id'},
        node           => { name => $m->{'name'}, id => $m->{'node_id'} },
        description    => $m->{'description'},
        start_epoch    => $m->{'start_epoch'},
        end_epoch      => $m->{'end_epoch'}
    };
    return $result;
}

=head2 get_node_maintenances
=cut
sub get_node_maintenances {
    my $self = shift;

    my $sql = "SELECT m.maintenance_id, m.description, node.name, node.node_id, m.start_epoch, m.end_epoch ";
    $sql   .= "FROM maintenance as m, node as node, node_maintenance as info ";
    $sql   .= "WHERE m.maintenance_id = info.maintenance_id ";
    $sql   .= "AND info.node_id = node.node_id ";
    $sql   .= "AND m.end_epoch = -1";

    my $maintenances = $self->_execute_query($sql, []);
    if (!defined @$maintenances[0]) {
        return [];
    }

    my $result = [];
    foreach my $m (@$maintenances){
        push (@$result,
              {
                  maintenance_id => $m->{'maintenance_id'},
                  node           => { name => $m->{'name'}, id => $m->{'node_id'} },
                  description    => $m->{'description'},
                  start_epoch    => $m->{'start_epoch'},
                  end_epoch      => $m->{'end_epoch'}
              });
    }
    return $result;
}

=head2 start_link_maintenance
=cut
sub start_link_maintenance {
    my $self = shift;
    my $link_id = shift;
    my $description = shift;

    # Validate link exists, and grab relevant data.
    my $sql = "SELECT link.name FROM link where link_id = ?";
    my $links = $self->_execute_query($sql, [$link_id]);
    if (!defined @$links[0]) {
        $self->_set_error("Link doesn't exist.");
        return;
    }

    # Check if the link is already under maintenance.
    my $sql1 = "SELECT m.maintenance_id FROM maintenance as m, link_maintenance as n where m.maintenance_id = n.maintenance_id AND m.end_epoch = -1 AND n.link_id = ?";
    my $link_maintenance = $self->_execute_query($sql1, [$link_id]);
    if (defined @$link_maintenance[0]) {
        $self->_set_error("Link is already in maintenance mode.");
        return;
    }

    my $sql2 = "INSERT into maintenance (description, start_epoch, end_epoch) ";
    $sql2   .= "VALUES (?, unix_timestamp(NOW()), -1)";
    my $maintenance_id = $self->_execute_query($sql2, [$description]);
    if (!defined $maintenance_id) {
        $self->_set_error("Could not insert row into maintenance table.");
        return;
    }

    my $sql3 = "INSERT into link_maintenance (link_id, maintenance_id) ";
    $sql3   .= "VALUES (?, ?)";
    my $link_maintenance_id = $self->_execute_query($sql3, [$link_id, $maintenance_id]);
    if (!defined $link_maintenance_id) {
        $self->_set_error("Could not insert row into link_maintenance table.");
        return;
    }

    my $sql4 = "UPDATE link set in_maint = 'yes' where link_id = ?";
    my $update = $self->_execute_query($sql4, [$link_id]);
    if (!defined $update) {
        $self->_set_error("Could not put link into maintenance.");
        return;
    }
    my $m = $self->get_link_maintenance($link_id);
    if (!defined $m) {
        $self->_set_error("Could not retrieve link maintenance.");
        return;
    }
    my $result = {
        maintenance_id => $maintenance_id,
        link           => { name => @$links[0]->{'name'}, id => $link_id },
        description    => $description,
        start_epoch    => $m->{'start_epoch'},
        end_epoch      => $m->{'end_epoch'}
    };
    return $result;
}

=head2 end_link_maintenance
=cut
sub end_link_maintenance {
    my $self = shift;
    my $link_id = shift;
    
    my $m = $self->get_link_maintenance($link_id);
    if (!defined $m) {
        return;
    }
    
    my $sql = "UPDATE link set in_maint = 'no' where link_id = ?";
    my $update = $self->_execute_query($sql, [$link_id]);
    if (!defined $update) {
        $self->_set_error("Could not remove link from maintenance.");
        return;
    }

    $sql = "UPDATE maintenance SET end_epoch = unix_timestamp(NOW()) WHERE maintenance_id = ?";
    my $result = $self->_execute_query($sql, [$m->{'maintenance_id'}]);
    if (!defined $result) {
        $self->_set_error("Internal error while ending link maintenance.");
        return;
    }
    return $result;
}

=head2 get_link_maintenance
=cut
sub get_link_maintenance {
    my $self = shift;
    my $link_id = shift;

    my $sql = "SELECT m.maintenance_id, m.description, link.name, link.link_id, m.start_epoch, m.end_epoch ";
    $sql   .= "FROM maintenance as m, link as link, link_maintenance as info ";
    $sql   .= "WHERE m.maintenance_id = info.maintenance_id ";
    $sql   .= "AND info.link_id = link.link_id ";
    $sql   .= "AND link.link_id = ? ";
    $sql   .= "AND m.end_epoch = -1";

    my $maintenance = $self->_execute_query($sql, [$link_id]);
    if (!defined $maintenance) {
        $self->_set_error("Internal error while fetching link maintenance.");
        return;
    }
    my $m = @$maintenance[0];

    my $result = {
        maintenance_id => $m->{'maintenance_id'},
        link           => { name => $m->{'name'}, id => $m->{'link_id'} },
        description    => $m->{'description'},
        start_epoch    => $m->{'start_epoch'},
        end_epoch      => $m->{'end_epoch'}
    };
    return $result;
}

=head2 get_link_maintenances
=cut
sub get_link_maintenances {
    my $self = shift;

    my $sql = "SELECT m.maintenance_id, m.description, link.name, link.link_id, m.start_epoch, m.end_epoch ";
    $sql   .= "FROM maintenance as m, link as link, link_maintenance as info ";
    $sql   .= "WHERE m.maintenance_id = info.maintenance_id ";
    $sql   .= "AND info.link_id = link.link_id ";
    $sql   .= "AND m.end_epoch = -1";

    my $maintenances = $self->_execute_query($sql, []);
    if (!defined $maintenances) {
        $self->_set_error("Internal error while fetching link maintenances.");
        return;
    }

    my $result = [];
    foreach my $m (@$maintenances){
        push (@$result,
              {
                  maintenance_id => $m->{'maintenance_id'},
                  link           => { name => $m->{'name'}, id => $m->{'link_id'} },
                  description    => $m->{'description'},
                  start_epoch    => $m->{'start_epoch'},
                  end_epoch      => $m->{'end_epoch'}
              });
    }
    return $result;
}

=head2 add_acl

Adds acl information to an interface

=cut

sub add_acl {
    my $self = shift;
    my %args = @_;

    if(!defined($args{'user_id'}) && !defined($args{'interface_id'})){
        $self->_set_error("Must pass in a user_id and an interface_id");
        return;
    }

    my $interface = $self->_authorize_interface_acl(
        interface_id => $args{'interface_id'},
        user_id => $args{'user_id'}
    ) || return;

    # check to make sure vlan start and end are valid
    $self->_check_vlan_range(
        vlan_tag_range => $interface->{'vlan_tag_range'},
        vlan_start     => $args{'vlan_start'},
        vlan_end       => $args{'vlan_end'}
    ) || return;

    if(defined($args{'eval_position'})){
        if(  $self->_has_used_eval_position( interface_id  => $args{'interface_id'},
                                             eval_position => $args{'eval_position'} ) ){
            return;
        }
    }else {
        $args{'eval_position'} = $self->_get_next_eval_position( interface_id => $args{'interface_id'} );
    }

    my $args = [
        $args{'workgroup_id'},
        $args{'interface_id'},
        $args{'allow_deny'},
        $args{'eval_position'},
        $args{'vlan_start'},
        $args{'vlan_end'},
        $args{'notes'}
    ];

    my $user_id = $args{'user_id'};


    my $query = "insert into interface_acl (workgroup_id, interface_id, allow_deny, eval_position, vlan_start, vlan_end, notes) values (?,?,?,?,?,?,?)";
    my $acl_id = $self->_execute_query($query, $args);

    if (! defined $acl_id){
        $self->_set_error("Unable to add new workgroup");
        return;
    }

    return $acl_id;

}

=head2 update_acl

Updates acl

=cut

sub update_acl {
    my $self = shift;
    my %args = @_;


    if(!defined($args{'user_id'})){
    $self->_set_error("user_id not specified");
    return;
    }
    if(!defined($args{'interface_acl_id'})){
    $self->_set_error("interface_acl_id not specified");
    return;
    }

    # get the current acl state
    my $query = "select * from interface_acl where interface_acl_id = ?";
    my $interface_acl = $self->_execute_query($query, [$args{'interface_acl_id'}]);
    if(!$interface_acl) {
        $self->_set_error("Error updating acl");
        return;
    }
    $interface_acl = $interface_acl->[0];

    # check if the user is authorized to edit this acl
    my $interface = $self->_authorize_interface_acl(
        interface_id => $interface_acl->{'interface_id'},
        user_id => $args{'user_id'}
    ) || return;

    # check to make sure vlan start and end are valid
    $self->_check_vlan_range(
        vlan_tag_range => $interface->{'vlan_tag_range'},
        vlan_start     => $args{'vlan_start'},
        vlan_end       => $args{'vlan_end'}
    ) || return;

    if(!defined($args{'interface_acl_id'})){
    $self->_set_error("interface_acl_id was not specified");
    return;
    }
    if(!defined($args{'vlan_start'})){
    $self->_set_error("vlan_start not specified");
    return;
    }
    if(!defined($args{'allow_deny'})){
    $self->_set_error("allow_deny not specified");
    return;
    }
    my $res;
    my $update_positions = 0;
    my $int_acl_at_position;
    my $all_int_acls;
    if(!defined($args{'eval_position'})){
        $self->_set_error("eval_position not specified");
        return;
    }
    # we may need to do some reordering
    else {
        # see if its position is changing
        if($interface_acl->{'eval_position'} != $args{'eval_position'}) {
            my $moving_lower = ($interface_acl->{'eval_position'} > $args{'eval_position'}) ? 1 : 0;

            $query = "select * from interface_acl where interface_id = ? and eval_position = ? and interface_acl_id != ?";
            $int_acl_at_position = $self->_execute_query($query, [$interface_acl->{'interface_id'}, $args{'eval_position'}, $args{'interface_acl_id'}]);
            if(!$int_acl_at_position) {
                $self->_set_error("Error updating acl");
                return;
            }
            # if we received a result at the same eval position we are and the result is not the same acl
            # as the one we are editing, we need to update the positions
            if( @$int_acl_at_position > 0 ) {
                $update_positions = 1;
                # get all the acls for this interface except the one were editing
                $query = "select * from interface_acl where interface_id = ? and interface_acl_id != ? order by eval_position";
                my $all_other_acls = $self->_execute_query($query, [$interface_acl->{'interface_id'}, $args{'interface_acl_id'}]);
                if(!$all_other_acls) {
                    $self->_set_error("Error updating acl");
                    return;
                }
                # loop through the acls and determine were to insert ours into the list
                foreach my $other_acl (@$all_other_acls) {
                    # must insert acl before if were moving it to a lower position
                    if( $moving_lower && ($other_acl->{'eval_position'} == $args{'eval_position'}) ){
                        push(@$all_int_acls, $args{'interface_acl_id'});
                    }

                    push(@$all_int_acls, $other_acl->{'interface_acl_id'});

                    # must insert acl after if were moving it to a higher position
                    if( !$moving_lower && ($other_acl->{'eval_position'} == $args{'eval_position'}) ){
                        push(@$all_int_acls, $args{'interface_acl_id'});
                    }
                }
            }
        }
    }

    $query = "update interface_acl set workgroup_id = ?, allow_deny = ?, eval_position = ?, vlan_start = ?, vlan_end = ?, notes = ? where interface_acl_id = ?";

    my $params = [
        $args{'workgroup_id'},
        $args{'allow_deny'},
        $args{'eval_position'},
        $args{'vlan_start'},
        $args{'vlan_end'},
        $args{'notes'},
        $args{'interface_acl_id'}
    ];

    $self->_start_transaction();

    $res = $self->_execute_query($query, $params);
    if(!defined($res)){
    $self->_set_error("Unable to update interface acl");
	$self->_rollback();
    return;
    }

    # do we need to reorder?
    if($update_positions) {
        # reorder all the acls in the order we defined above starting with 10
        my $eval = 10;
        foreach my $interface_acl_id (@$all_int_acls) {
            $query = "update interface_acl set eval_position = ? where interface_acl_id = ?";
            $res = $self->_execute_query($query, [$eval, $interface_acl_id]);
            if(!$res) {
                $self->_set_error("Error updating interface acl");
	            $self->_rollback();
                return;
            }
            $eval += 10;
        }
    }

    $self->_commit();

    return 1;
}

=head2 remove_acl

Removes an interface acl

=cut
sub remove_acl {
    my $self = shift;
    my %args = @_;

    if(!defined($args{'user_id'}) || !defined($args{'interface_acl_id'}) ){
        $self->_set_error("Must pass in a user_id and an interface_acl_id");
        return;
    }

    # get the current acl state
    my $query = "select * from interface_acl where interface_acl_id = ?";
    my $interface_acl = $self->_execute_query($query, [$args{'interface_acl_id'}]);
    if(!$interface_acl) {
        $self->_set_error("Error removing acl");
        return;
    }
    $interface_acl = $interface_acl->[0];

    # make sure this user is authorized to edit this interface's acl
    my $authorized = $self->_authorize_interface_acl(
        interface_id => $interface_acl->{'interface_id'},
        user_id => $args{'user_id'}
    ) || return;

    $query = "delete from interface_acl where interface_acl_id = ?";
    my $count = $self->_execute_query($query, [$args{'interface_acl_id'}]);
    if (! defined $count){
        $self->_set_error("Unable to remove acl");
        return;
    }

    return $count;
}



=head2 _hash_used_eval_position

Returns true if the acl's eval position is already used

=cut
sub _has_used_eval_position {
    my $self = shift;
    my %args = @_;

    if(!defined($args{'interface_id'}) || !defined($args{'eval_position'})){
        $self->_set_error("Need to pass in an interface_id and an eval_position");
        return;
    }

    my $result = $self->_execute_query(
        "select 1 from interface_acl where interface_id = ? and eval_position = ?",
        [$args{'interface_id'}, $args{'eval_position'}]
    );
    if(!defined($result)){
        $self->_set_error("Could not query interface acl eval positions");
        return;
    }

    if (@$result > 0){
        $self->_set_error("There is already an acl at eval position $args{'eval_position'}");
        return 1;
    }else {
        return 0;
    }
}
=head2 _get_next_eval_position

Returns the max eval position plus ten

=cut
sub _get_next_eval_position {
    my $self = shift;
    my %args = @_;

    if(!defined($args{'interface_id'})){
        $self->_set_error("Must pass in interface_id");
        return;
    }

    my $result = $self->_execute_query(
        "select max(interface_acl.eval_position) as max_eval_position from interface_acl where interface_id = ?",
        [$args{'interface_id'}]
    );
    if(!defined($result)){
        $self->_set_error("Could not query max interface acl eval position");
        return;
    }

    if (@$result <= 0){
        return 10; # adding first rule
    }else {
        return ($result->[0]{'max_eval_position'} + 10);
    }

}

=head2 get_acls

Gets all the interface acls for a given workgroup

=cut

sub get_acls {

    my $self = shift;
    my %args = @_;

    my $acls = [];
    my $sql= "select acl.interface_acl_id, acl.workgroup_id, workgroup.name as workgroup_name, owner_workgroup.workgroup_id as owner_workgroup_id, owner_workgroup.name as owner_workgroup_name, acl.interface_id, interface.name as interface_name, acl.allow_deny, acl.eval_position, acl.vlan_start, acl.vlan_end, acl.notes ";
    $sql .= " from workgroup as owner_workgroup";
    $sql .= " join interface on owner_workgroup.workgroup_id = interface.workgroup_id ";
    $sql .= " join interface_acl as acl on acl.interface_id = interface.interface_id ";
    $sql .= " left join workgroup on acl.workgroup_id = workgroup.workgroup_id ";
    $sql .= " where 1=1 ";
    $sql .= " and owner_workgroup.workgroup_id = ? " if(defined($args{'owner_workgroup_id'}));
    $sql .= " and acl.interface_id = ? " if(defined($args{'interface_id'}));
    $sql .= " and acl.interface_acl_id = ? " if(defined($args{'interface_acl_id'}));
    $sql .= " order by acl.eval_position";

    my $args = [];
    push(@$args,$args{'owner_workgroup_id'}) if(defined($args{'owner_workgroup_id'}));
    push(@$args,$args{'interface_id'}) if(defined($args{'interface_id'}));
    push(@$args,$args{'interface_acl_id'}) if(defined($args{'interface_acl_id'}));

    my $results = $self->_execute_query($sql, $args);

    if (! defined $results){
    $self->_set_error("Internal error while fetching interface acls");
    return;
    }

    return $results;
}

=head2 _authorize_interface_acl

Checks if a user belongs to the workgroup that owns the interface and is allowd to edit it. Returns interface if true

=cut
sub _authorize_interface_acl {
    my $self = shift;
    my %args = @_;
    my $user_id = $args{'user_id'};
    my $interface_id = $args{'interface_id'};

    # first check if the user is an admin and if they are authorized
    my $authorization = $self->get_user_admin_status( 'user_id' => $user_id);
    if ( $authorization->[0]{'is_admin'} == 1 ) {
        # now make sure the interface exists and return it if so
        my $result = $self->_execute_query(
            "select * from interface where interface_id = ?",
	        [$interface_id],
	    );
        if(!defined($result)){
	        $self->_set_error("Could not retrieve interface information");
	        return;
        }
        if(@$result <= 0) {
	        $self->_set_error("There is no interface with id: $interface_id");
            return undef;
        }
        return $result->[0];;
    }

    my $workgroups = $self->get_workgroups( user_id => $user_id );
    if(!defined($workgroups)){
        return;
    }

    my $args = [$interface_id];
    foreach my $workgroup (@$workgroups) {
        push(@$args, $workgroup->{'workgroup_id'});
    }
    # need to dynamically generate placeholders since we don't know how many the
    # user belongs to before hand
    my $place_holders = join(",", ("?") x @$workgroups);
    my $result = $self->_execute_query(
        "select * from interface where interface_id = ? and workgroup_id in ($place_holders)",
	    $args
	);
    if(!defined($result)){
	    $self->_set_error("Could not query interface ownership");
	    return;
    }
    if (@$result > 0){
	    return $result->[0];
    }else {
	    $self->_set_error("Access Denied");
        return undef;
    }

}
=head2 _check_vlan_range

Checks to make sure vlan start is less than vlan end and they fall withing the interface's range
and that they are both numbers
=cut

sub _check_vlan_range {
    my $self = shift;
    my %args = @_;

    my $vlan_tag_range = $args{'vlan_tag_range'};

    # first make sure both range values are numbers
    if( !($args{'vlan_start'} =~ m/^-?\d+$/) ) {
	    $self->_set_error("vlan_start must be a numeric value");
	    return;
    }
    if( defined($args{'vlan_end'}) && 
        !($args{'vlan_end'} =~  m/^-?\d+$/) ){
	    $self->_set_error("vlan_end must be a numeric value or undefined");
	    return;
    }

    # create a string of the range passed in for error messages later
    my $vlan_range_string;
    if(defined($args{'vlan_end'})){
        $vlan_range_string = $args{'vlan_start'}."-".$args{'vlan_end'};
    }else {
        $vlan_range_string = $args{'vlan_start'};
    }

    my $vlan_start = $args{'vlan_start'};
    # if the start is untagged then check to see that it is
    # contained separately
    my $check_for_untagged = 0;
    if($vlan_start == UNTAGGED){
        $check_for_untagged = 1;
        # if vlan_end is defined set vlan_start to 1 so we skip over zero
        # otherqise $vlan_start and $vlan_end will both be set to -1
        if(defined($args{'vlan_end'})) {
            $vlan_start = 1;
        }
    }
    my $vlan_end = $args{'vlan_end'} || $vlan_start;

    if($vlan_end < $vlan_start) {
	    $self->_set_error("vlan_end can not be less than vlan_start");
	    return;
    }

    my @vlan_ranges = split(',', $vlan_tag_range);

    # need to check untagged value separately if it was passed in since
    # it will be the only unconsecutive value if it is defined
    my $untagged_contained = 0;
    if($check_for_untagged) {
        foreach my $vlan_range (@vlan_ranges) {
            if($vlan_range =~ /(\d+)-(\d+)/) {
                my $vlan_range_start = $1;
                my $vlan_range_end   = $2;
                # is our submitted range contained within this range
                if( (UNTAGGED >= $vlan_range_start) &&
                    (UNTAGGED <= $vlan_range_end) ) {
                    $untagged_contained = 1;
                }
            } else {
                if( (UNTAGGED == $vlan_range) ) {
                    $untagged_contained = 1;
                }
            }
        }
        if(!$untagged_contained){
	        $self->_set_error("$vlan_range_string does not fall within the vlan tag range defined for the interface, $vlan_tag_range");
            return 0;
        }else {
            # we only passed in $vlan_start as -1 and its contained so return true
            if( ($vlan_start == UNTAGGED) && ($vlan_end == UNTAGGED) ){
                return 1;
            }
        }
    }

    # now check that vlan_start and vlan_end can fit somewhere in the vlan_tag range
    foreach my $vlan_range (@vlan_ranges) {
        if($vlan_range =~ /(\d+)-(\d+)/) {
            my $vlan_range_start = $1;
            my $vlan_range_end   = $2;

            # is our submitted range contained within this range
            if( ($vlan_start >= $vlan_range_start) &&
                ($vlan_end   <= $vlan_range_end) ) {

                return 1;
            }
        } else {
            if( ($vlan_start == $vlan_range) && ($vlan_end == $vlan_range) ) {
                return 1;
            }
        }
    }

	$self->_set_error("$vlan_range_string does not fall within the vlan tag range defined for the interface, $vlan_tag_range");
    return 0;
}

=head2 _get_vlan_range_intersection

takes an array of vlan range strings and returns the intersection of each

=cut
sub _get_vlan_range_intersection {
    my ($self, %args) = @_;

    my $vlan_ranges   = $args{'vlan_ranges'};
    my $oscars_format = $args{'oscars_format'} || 0;

    # create an array of arrays from our range_strings
    my $vlan_arrays = [];
    foreach my $vlan_range (@$vlan_ranges){
        my $tags = $self->_process_tag_string( $vlan_range, $oscars_format );
        push(@$vlan_arrays, $tags);
    }

    # determine the intersection of the arrays of ranges
    my @intersection = @{$vlan_arrays->[0]};
    foreach my $vlan_array (@$vlan_arrays){
        my @vlan_array = @$vlan_array;
        @intersection = intersect(@intersection, @$vlan_array);
    }

    # create a hash from our array of ranges
    my $intersection_hash = {};
    foreach my $vlan (@intersection){
        $intersection_hash->{$vlan} = 1;
    }
    my $intersection_string = $self->_vlan_range_hash2str( vlan_range_hash => $intersection_hash, oscars_format => $oscars_format );

    return $intersection_string;
}

=head2 add_workgroup

Creates a new, empty workgroup with no permissions named $name.

=over

=item name

The name of this workgroup.

=back

=cut

sub add_workgroup {
    my $self = shift;
    my %args = @_;

    my $name = $args{'name'};
    my $external_id = $args{'external_id'};
    my $type = $args{'type'};
    $type = 'normal' if !defined($type);

    if($type ne 'admin' && $type ne 'normal' && $type ne 'demo'){
	$type = 'normal';
    }

    my $new_wg_id = $self->_execute_query("insert into workgroup (name,external_id,type) values (?,?,?)", [$name,$external_id,$type]);

    if (! defined $new_wg_id){
	$self->_set_error("Unable to add new workgroup");
	return;
    }

    return $new_wg_id;
}

=head2 get_users

Returns an array of hashes containing basic information for all the users.

=cut

sub get_users {
    my $self = shift;
    my %args = @_;

    my @users;

    my $results = $self->_execute_query("select * from user order by given_names");

    if (! defined $results){
	$self->_set_error("Internal error fetching users.");
	return;
    }

    foreach my $row (@$results){

	my $data = {'first_name'    => $row->{'given_names'},
		    'family_name'   => $row->{'family_name'},
		    'email_address' => $row->{'email'},
		    'user_id'       => $row->{'user_id'},
		    'type'          => $row->{'type'},
            'status'        => $row->{'status'},
		    'auth_name'     => []
	};

	my $auth_results = $self->_execute_query("select auth_name from remote_auth where user_id = ?", [$row->{'user_id'}]);

	if (! defined $auth_results){
	    $self->_set_error("Internal error fetching remote_auth");
	    return;
	}

	foreach my $auth_row (@$auth_results){
	    push(@{$data->{'auth_name'}}, $auth_row->{'auth_name'});
	}

	push(@users, $data);

    }

    return \@users;
}

=head2 get_users_in_workgroup

Returns an array of hashes containing basic information for all the users in a workgroup with id $workgroup_id.

=over

=item workgroup_id

The internal MySQL primary key int identifier for this workgroup.

=back

=cut

sub get_users_in_workgroup {
    my $self = shift;
    my %args = @_;

    my $workgroup_id = $args{'workgroup_id'};
    my $order_by     = $args{'order_by'};

    my $users;

    my $results = $self->_execute_query("select user.* from user" .
                                        " join user_workgroup_membership on user.user_id = user_workgroup_membership.user_id" .
                                        " where user_workgroup_membership.workgroup_id = ?" .
                                        " and user.status = 'active'" .
                                        " order by given_names",
                                        [$workgroup_id]
        );

    if (! defined $results){
	$self->_set_error("Internal error fetching users.");
	return;
    }

    foreach my $row (@$results){

        my $data = {
            'first_name'    => $row->{'given_names'},
            'family_name'   => $row->{'family_name'},
            'email_address' => $row->{'email'},
            'user_id'       => $row->{'user_id'},
            'status'        => $row->{'status'},
            'auth_name'     => []
        };

        my $auth_results = $self->_execute_query(
            "select auth_name from remote_auth where user_id = ? order by auth_name", 
            [$row->{'user_id'}]
        );
        if (! defined $auth_results){
            $self->_set_error("Internal error fetching remote_auth");
            return;
        }

        foreach my $auth_row (@$auth_results){
            push(@{$data->{'auth_name'}}, $auth_row->{'auth_name'});
        }

        push(@$users, $data);

    }

    if($order_by eq 'auth_name'){
        @$users = sort { join(',',@{$a->{'auth_name'}}) cmp join(',',@{$b->{'auth_name'}}) } @$users;
    }

    return $users;
}

=head2 is_user_in_workgroup

Returns a boolean indicated whether or not the user identified by $user_id belongs to the workgroup identified by $workgroup_id.

=over

=item user_id

The internal MySQL primary key int identifier for this user.

=item workgroup_id

The internal MySQL primary key int identifier for the workgroup.

=back

=cut

sub is_user_in_workgroup {
    my $self = shift;
    my %args = @_;

    my $workgroup_id = $args{'workgroup_id'};
    my $user_id      = $args{'user_id'};

    if(!defined($workgroup_id)){
	return;
    }

    if(!defined($user_id)){
	return;
    }

    my $result = $self->_execute_query("select 1 from user_workgroup_membership where workgroup_id = ? and user_id = ?",
	                               [$workgroup_id, $user_id]
	);
    
    if (@$result > 0){
	return 1;
    }

    return 0;
}

=head2 add_user_to_workgroup

Adds a user with user id $user_id to workgroup identified by $workgroup_id.

=over

=item user_id

The internal MySQL primary key int identifier for this user.

=item workgroup_id

The internal MySQL primary key int identifier for the workgroup.

=back

=cut

sub add_user_to_workgroup {
    my $self = shift;
    my %args = @_;

    my $user_id      = $args{'user_id'};
    my $workgroup_id = $args{'workgroup_id'};
    if(!defined($user_id)){
	return;
    }

    if(!defined($workgroup_id)){
	return;
    }

    if ($self->is_user_in_workgroup(user_id => $user_id, workgroup_id => $workgroup_id)){
	$self->_set_error("User is already a member of this workgroup.");
	return;
    }

    my $result = $self->_execute_query("insert into user_workgroup_membership (workgroup_id, user_id) values (?, ?)",
				       [$workgroup_id, $user_id]
	);

    if (! defined $result){
	$self->_set_error("Unable to create user workgroup membership.");
	return;
    }

    return 1;
}


=head2 remove_user_from_workgroup

Removes a user with user id $user_id from workgroup identified by $workgroup_id.

=over

=item user_id

The internal MySQL primary key int identifier for this user.

=item workgroup_id

The internal MySQL primary key int identifier for the workgroup.

=back

=cut

sub remove_user_from_workgroup {
    my $self = shift;
    my %args = @_;

    my $user_id      = $args{'user_id'};
    my $workgroup_id = $args{'workgroup_id'};


    my $result = $self->_execute_query("select 1 from user_workgroup_membership where workgroup_id = ? and user_id = ?",
				      [$workgroup_id, $user_id]
	);

    if (@$result < 1){
	$self->_set_error("User is not a member of this workgroup.");
	return;
    }


    $result = $self->_execute_query("delete from user_workgroup_membership where workgroup_id = ? and user_id = ?",
				    [$workgroup_id, $user_id]
	);

    if (! defined $result){
	$self->_set_error("Unable to delete user workgroup membership.");
	return;
    }

    return 1;
}


=head2 add_user

Adds a new user into the database. Returns the new user internal id if successful.

=over

=item given_name

The user's given name, or first name.

=item family_name

The user's family name, or last name.

=item email_address

The user's email address.

=item auth_names

An array of usernames that this user may validate under. This is typically only 1, but could be more if using some sort of federated authentication mechanism without requiring multiple user entries.

=back

=cut

sub add_user {
    my $self = shift;
    my %args = @_;

    my $given_name  = $args{'given_name'};
    my $family_name = $args{'family_name'};
    my $email       = $args{'email_address'};
    my $auth_names  = $args{'auth_names'};
    my $type        = $args{'type'};
    my $status      = $args{'status'};
    
    if (!defined ($type)){
        $type = "normal";
    }

    if(!defined($status)){
        $status = 'active';
    }

    if(!defined($given_name) || !defined($family_name) || !defined($email) || !defined($auth_names)){
	$self->_set_error("Invalid parameters to add user, please provide a given name, family name, email, and auth names");
	return;
    }

    if ($given_name =~ /^system$/ || $family_name =~ /^system$/){
	$self->_set_error("Cannot use 'system' as a username.");
	return;
    }

    $self->_start_transaction();

    my $query = "insert into user (email, given_names, family_name, type, status) values (?, ?, ?, ?, ?)";

    my $user_id = $self->_execute_query($query, [$email, $given_name, $family_name, $type, $status]);

    if (! defined $user_id){
	$self->_set_error("Unable to create new user.");
	$self->_rollback();
	return;
    }

    if(ref($auth_names) eq 'ARRAY'){

	foreach my $name (@$auth_names){
	    $query = "insert into remote_auth (auth_name, user_id) values (?, ?)";
	    $self->_execute_query($query, [$name, $user_id]);
	}
    }else{
	$query = "insert into remote_auth (auth_name, user_id) values (?,?)";
	$self->_execute_query($query, [$auth_names, $user_id]);
    }

    $self->_commit();

    return $user_id;
}

=head2 delete_user

Removes a pre-existing user's record from the database. Returns a boolean on success.

=over

=item user_id

The internal MySQL primary key int identifier for this user.

=back

=cut

sub delete_user {
    my $self = shift;
    my %args = @_;

    my $user_id = $args{'user_id'};

    # does this user even exist?
    my $info = $self->get_user_by_id(user_id => $user_id);

    if (! defined $info){
	$self->_set_error("Internal error identifying user with id: $user_id");
	return;
    }

    # first let's make sure we aren't deleting system
    if ($info->[0]->{'given_names'} =~ /^system$/i){
	$self->_set_error("Cannot delete the system user.");
	return;
    }

    # okay, looks good. Let's delete this user
    $self->_start_transaction();

    if (! defined $self->_execute_query("delete from user_workgroup_membership where user_id = ?", [$user_id])) {
	$self->_set_error("Internal error delete user.");
    $self->_rollback();
	return;
    }

    if (! defined $self->_execute_query("delete from remote_auth where user_id = ?", [$user_id])){
	$self->_set_error("Internal error delete user.");
	$self->_rollback();
    return;
    }

    if (! defined $self->_execute_query("delete from user where user_id = ?", [$user_id])){
	$self->_set_error("Internal error delete user.");
	$self->_rollback();
    return;
    }

    $self->_commit();

    return 1;
}


=head2 edit_user

Updates a pre-existing user's record in the database. Returns a boolean on success.

=over

=item user_id

The internal MySQL primary key int identifier for this user.

=item given_name

The user's given name, or first name.

=item family_name

The user's family name, or last name.

=item email_address

The user's email address.

=item auth_names

An array of usernames that this user may validate under. This is typically only 1, but could be more if using some sort of federated authentication mechanism without requiring multiple user entries.

=item status

The administrative status of the user (active|decom).

=back

=cut

sub edit_user {
    my $self = shift;
    my %args = @_;

    my $user_id     = $args{'user_id'};
    my $given_name  = $args{'given_name'};
    my $family_name = $args{'family_name'};
    my $email       = $args{'email_address'};
    my $auth_names  = $args{'auth_names'};
    my $type        = $args{'type'};
    my $status      = $args{'status'};


    if ($given_name =~ /^system$/ || $family_name =~ /^system$/){
        $self->_set_error("User 'system' is reserved.");
        return;
    }
    
    $self->_start_transaction();
    
    my $query = "update user set email = ?, given_names = ?, family_name = ?, type = ?, status = ?  where user_id = ?";
    
    my $result = $self->_execute_query($query, [$email, $given_name, $family_name, $type, $status,  $user_id]);
    
    if (! defined $user_id || $result == 0){
        $self->_set_error("Unable to edit user - does this user actually exist?");
        $self->_rollback();
        return;
    }
    
    $self->_execute_query("delete from remote_auth where user_id = ?", [$user_id]);
    
    foreach my $name (@$auth_names){
        $query = "insert into remote_auth (auth_name, user_id) values (?, ?)";
        
        $self->_execute_query($query, [$name, $user_id]);
    }
    
    $self->_commit();
    
    return 1;
}

=head2 get_current_circuits_by_interface

=cut

sub get_current_circuits_by_interface{
    my $self = shift;
    my %args = @_;

    my $interface = $args{'interface'};

    my $dbh = $self->{'dbh'};

    my $query = "select circuit.workgroup_id,circuit.external_identifier, circuit.name, circuit.description, circuit.circuit_id, circuit_instantiation.circuit_state from circuit join circuit_instantiation on circuit.circuit_id = circuit_instantiation.circuit_id join circuit_edge_interface_membership on circuit_edge_interface_membership.circuit_id = circuit.circuit_id and circuit_instantiation.end_epoch = -1 and circuit_instantiation.circuit_state != 'decom' and circuit_edge_interface_membership.end_epoch = -1 and circuit_edge_interface_membership.interface_id = ?";

    my $rows = $self->_execute_query($query, [$interface->{'interface_id'}]);

    if (! defined $rows){
        $self->_set_error("Internal error while getting circuits.");
        return;
    }

    my $results = [];
    my $circuits;
    foreach my $row (@$rows){

        my $circuit_id = $row->{'circuit_id'};
        # first time seeing this circuit, add basic info
        if (! exists $circuits->{$circuit_id}){
            $circuits->{$circuit_id} = {'circuit_id'  => $row->{'circuit_id'},
                                        'name'        => $row->{'name'},
                                        'description' => $row->{'description'},
                                        'bandwidth'   => $row->{'reserved_bandwidth_mbps'},
                                        'state'       => $row->{'circuit_state'},
                                        'external_identifier' => $row->{'external_identifier'},
                                        'endpoints'   => [],
                                        'workgroup_id' => $row->{'workgroup_id'}
            };

	}

	$circuits->{$circuit_id}->{'endpoints'}    = $self->get_circuit_endpoints(circuit_id => $circuit_id) || [];

    }


    foreach my $circuit_id (keys %$circuits){
        push (@$results, $circuits->{$circuit_id});
    }

    return $results;

}


=head2 get_current_circuits

Returns an array of hashes containing basic information for all the circuits that are currently active according
to the database. Assuming that all the other components of OESS are running, this should be all circuits that are active
on the network as well.

=over

=item workgroup_id (optional)

The internal MySQL identifier for this workgroup. If given, circuits returned will only be ones that belong to this workgroup. (not working currently)

=back

=cut

sub get_current_circuits {
    my $self = shift;
    my %args = @_;

    my $workgroup_id = $args{'workgroup_id'};
    my $endpoint_nodes = $args{'endpoint_nodes'} || [];
    my $path_nodes = $args{'path_nodes'} || [];
    my $circuit_id_filter= [];
    my $results = [];
    my $circuit_list;
    my @endpoint_circuit_ids;
    my @path_circuit_ids;

    my $workgroup;
    if(defined($workgroup_id)){
	$workgroup = $self->get_workgroup_by_id( workgroup_id => $args{'workgroup_id'});
    }

    my $dbh = $self->{'dbh'};

    my @to_pass;

    ## Get all circuit ids that have an endpoint on a node passed
    if ( @$endpoint_nodes) {
	my $endpoint_node_sql ="
	select distinct circuit_instantiation.circuit_id from circuit_instantiation
	    join circuit_edge_interface_membership on circuit_edge_interface_membership.circuit_id = circuit_instantiation.circuit_id
	    and circuit_instantiation.end_epoch = -1
	    and circuit_edge_interface_membership.end_epoch = -1
	    join interface on circuit_edge_interface_membership.interface_id = interface.interface_id
	    and interface.node_id in (  ";

	$endpoint_node_sql .= "?," x scalar(@$endpoint_nodes);
	chop($endpoint_node_sql);
	$endpoint_node_sql .= ")";

	my $endpoint_results = $self->_execute_query($endpoint_node_sql ,$endpoint_nodes);


	foreach my $row (@$endpoint_results){
	    push(@endpoint_circuit_ids,$row->{'circuit_id'});
	}

	$circuit_id_filter = \@endpoint_circuit_ids;

    }
    if (@$path_nodes) {

	my $placeholders = "?". ",?" x (scalar(@$path_nodes)-1);

	my $path_node_sql = "
	select distinct path.circuit_id from path join path_instantiation p
	    on (path.path_id = p.path_id)
		join link_path_membership m on m.path_id = p.path_id and p.end_epoch=-1
		join link_instantiation l on l.end_epoch = -1
		and m.link_id = l.link_id join interface i on i.interface_id = interface_a_id or i.interface_id = interface_z_id
		where i.node_id in ( $placeholders )";
        
	my $path_results = $self->_execute_query($path_node_sql, $path_nodes );

	foreach my $row(@$path_results){
	    push(@path_circuit_ids,$row->{'circuit_id'});
	}
	$circuit_id_filter = \@path_circuit_ids;
    }
    #if we're looking for something that has an endpoint on a node, and has an endpoint on a node, we'll need the intersection of the two arrays of circuit_ids.
    if (@$path_nodes && @$endpoint_nodes){
	my @intersection = intersect(@endpoint_circuit_ids,@path_circuit_ids);
	$circuit_id_filter = \@intersection;
    }


    my $query = "select circuit.circuit_id, circuit.external_identifier, circuit.workgroup_id, circuit.name, circuit.description, circuit.circuit_id, circuit_instantiation.circuit_state ";
    $query   .= "from circuit ";
    $query   .= "join circuit_instantiation on circuit.circuit_id = circuit_instantiation.circuit_id and circuit_instantiation.end_epoch = -1 and circuit_instantiation.circuit_state != 'decom' ";
 
    if (@$endpoint_nodes || @$path_nodes ) {
	if(@$circuit_id_filter ==0){
	    return $results;
	}
	$query .= " and circuit.circuit_id in ( ?".",?" x (scalar(@$circuit_id_filter)-1) . ") ";
	push(@to_pass, @$circuit_id_filter);
    }


    $query   .= "left join circuit_edge_interface_membership on circuit.circuit_id = circuit_edge_interface_membership.circuit_id and circuit_edge_interface_membership.end_epoch = -1 ";
    $query   .= "left join interface on circuit_edge_interface_membership.interface_id = interface.interface_id";

    if ($workgroup_id && $workgroup->{'type'} ne 'admin'){
		$query .= " where (circuit.workgroup_id = ? or interface.workgroup_id = ?)";
		push(@to_pass, $workgroup_id);
		push(@to_pass, $workgroup_id);
    }


    $query .= " group by circuit.circuit_id order by circuit.description";

    my $rows = $self->_execute_query($query, \@to_pass);

    if (! defined $rows){
	$self->_set_error("Internal error while getting circuits.");
	return;
    }

    my $circuits;
    my @circuit_ids;
    foreach my $row (@$rows){

        push( @{$results}, OESS::Circuit->new( circuit_id => $row->{'circuit_id'},
                                               db         => $self,
                                               topo => $self->{'topo'},
                                               just_display => 1,
                                               link_status => $args{'link_status'}
              ));
    }

    return $results;

}

=head2 get_circuit_details_by_name

Just like get_circuit_details, but instead of a circuit_id this method takes a circuit name.

=over

=item name

The name of the circuit.

=back

=cut

sub get_circuit_details_by_name {
    my $self = shift;
    my %args = @_;

    my $circuit_name = $args{'name'};

    my $result = $self->_execute_query("select circuit_id from circuit where name = ?", [$circuit_name]);

    if (! defined $result){
	return;
    }

    if (@$result > 0){
	my $circuit_id = @$result[0]->{'circuit_id'};

	return $self->get_circuit_details(circuit_id => $circuit_id);
    }

    return ;
}

=head2 get_circuit_paths
    returns the circuits paths include the links that they ride over and their status
=cut

sub get_circuit_paths{
    my $self = shift;
    my %args = @_;

    my $circuit_id = $args{'circuit_id'};

    if(!defined($circuit_id)){
	return;
    }

    my $query = "select * from path join path_instantiation on path.path_id = path_instantiation.path_id where path.circuit_id = ? and path_instantiation.end_epoch = -1";

    my $paths = $self->_execute_query($query, [$circuit_id]);


    foreach my $path (@$paths){
        $path->{'links'} = $self->get_path_links( path_id => $path->{'path_id'});
	$path->{'status'} = $self->{'topo'}->is_path_up( path_id => $path->{'path_id'},
                                                         link_status => $args{'link_status'},
                                                         links => $path->{'links'} );

    }


    return $paths;
}

=head2 get_circuit_details

Returns a hash of information such as id, name, bandwidth, which path is active, and more about the requested circuit. This information also includes endpoints, links, and backup links.

=over

=item circuit_id

The internal MySQL primary key int identifier for this circuit.

=back

=cut

sub get_circuit_details {
    my $self = shift;
    my %args = @_;

    my $circuit_id = $args{'circuit_id'};
    if(!defined($circuit_id)){
	return;
    }

    

    my @bind_params = ($circuit_id);

    my $details;

    # basic circuit info
    my $query = "select circuit.restore_to_primary, circuit.external_identifier, circuit.name, circuit.description, circuit.circuit_id, circuit.static_mac, circuit_instantiation.modified_by_user_id, circuit_instantiation.loop_node, circuit.workgroup_id, " .
        " circuit.remote_url, circuit.remote_requester, " . 
	" circuit_instantiation.reserved_bandwidth_mbps, circuit_instantiation.circuit_state, circuit_instantiation.start_epoch  , " .
	" if(bu_pi.path_state = 'active', 'backup', 'primary') as active_path " .
	"from circuit " .
	" join circuit_instantiation on circuit.circuit_id = circuit_instantiation.circuit_id " .
	"  and circuit_instantiation.end_epoch = -1 " .
	"left join path as pr_p on pr_p.circuit_id = circuit.circuit_id and pr_p.path_type = 'primary' " .
	"left join path_instantiation as pr_pi on pr_pi.path_id = pr_p.path_id and pr_pi.end_epoch = -1 ".
        " left join path as bu_p on bu_p.circuit_id = circuit.circuit_id and bu_p.path_type = 'backup' " .
        " left join path_instantiation as bu_pi on bu_pi.path_id = bu_p.path_id and bu_pi.end_epoch = -1 ".
	" where circuit.circuit_id = ?";

    my $sth = $self->_prepare_query($query) or return;

    $sth->execute(@bind_params);

    my $primary_path_id;
    my $backup_path_id;
    my $show_historical =0;
    if (my $row = $sth->fetchrow_hashref()){
        my $dt = DateTime->from_epoch( epoch => $row->{'start_epoch'} );
        $details = {'circuit_id'             => $circuit_id,
                    'name'                   => $row->{'name'},
                    'description'            => $row->{'description'},
                    'loop_node'              => $row->{'loop_node'},
                    'bandwidth'              => $row->{'reserved_bandwidth_mbps'},
                    'state'                  => $row->{'circuit_state'},
                    'active_path'            => $row->{'active_path'},
                    'user_id'                => $row->{'modified_by_user_id'},
                    'last_edited'            => $dt->strftime('%m/%d/%Y %H:%M:%S'),
                    'workgroup_id'           => $row->{'workgroup_id'},
		    'restore_to_primary'     => $row->{'restore_to_primary'},
		    'static_mac'             => $row->{'static_mac'},
                    'external_identifier'    => $row->{'external_identifier'},
                    'remote_requester'       => $row->{'remote_requester'},
                    'remote_url'             => $row->{'remote_url'}
                   };
        if ( $row->{'circuit_state'} eq 'decom' ){
            $show_historical = 1;
        }
    }

    $details->{'internal_ids'} = $self->get_circuit_internal_ids(circuit_id => $circuit_id) || {};

    $details->{'endpoints'}    = $self->get_circuit_endpoints(circuit_id => $circuit_id, show_historical=> $show_historical) || [];

    $details->{'links'}        = $self->get_circuit_links(circuit_id => $circuit_id, show_historical=> $show_historical) || [];

    $details->{'backup_links'} = $self->get_circuit_links(circuit_id => $circuit_id,
							  type       => 'backup',
                                                          show_historical => $show_historical
	                                                 ) || [];

    $details->{'workgroup'} = $self->get_workgroup_by_id( workgroup_id => $details->{'workgroup_id'} );
    $details->{'last_modified_by'} = $self->get_user_by_id( user_id => $details->{'user_id'} )->[0];

    $query = "select * from circuit_instantiation where circuit_id = ? and end_epoch = (select min(end_epoch) from circuit_instantiation where circuit_id = ? and end_epoch > 0)";

    my $first_instantiation = $self->_execute_query($query,[$circuit_id,$circuit_id])->[0];

    if(defined($first_instantiation)){
	$details->{'created_by'} = $self->get_user_by_id( user_id => $first_instantiation->{'modified_by_user_id'})->[0];
	my $dt_create = DateTime->from_epoch( epoch => $first_instantiation->{'start_epoch'} );
	$details->{'created_on'} = $dt_create->strftime('%m/%d/%Y %H:%M:%S');
    }

    my $paths = $self->get_circuit_paths( circuit_id => $circuit_id, 
                                          show_historical => $show_historical, 
                                          link_status => $args{'link_status'});

    foreach my $path (@$paths){
	if($path->{'path_state'} eq 'active'){
	    if($path->{'status'} == 1){
                $details->{'operational_state'} = 'up';
	    }
            elsif($path->{'status'} == 1){
                $details->{'operational_state'} = 'unknown';
            }
            else{
                $details->{'operational_state'} = 'down';
	    }
	}
    }
    
    if(!defined($details->{'operational_state'})){
	$details->{'operational_state'} = 'unknown';
    }

    return $details;

}

=head2 get_circuit_internal_ids

=cut

sub get_circuit_internal_ids {
    my $self = shift;
    my %args = @_;

    my $circuit_id = $args{'circuit_id'};

    my $query = "
select link_instantiation.interface_a_id,link_instantiation.interface_z_id, 
link_path_membership.interface_a_vlan_id, link_path_membership.interface_z_vlan_id, 
node_a.node_id as node_a_id, node_a.name as node_a_name,
node_z.node_id as node_z_id, node_z.name as node_z_name,
 path.path_type
from path
join link_path_membership on (link_path_membership.end_epoch =-1 and link_path_membership.path_id=path.path_id and path.circuit_id=? )
join link on link_path_membership.link_id = link.link_id
join link_instantiation 
on link_instantiation.link_id = link.link_id
and link_instantiation.end_epoch = -1
and link_instantiation.link_state = 'active'
join interface as int_a on link_instantiation.interface_a_id = int_a.interface_id
join interface as int_z on link_instantiation.interface_z_id = int_z.interface_id
join node as node_a on int_a.node_id=node_a.node_id
join node as node_z on int_z.node_id=node_z.node_id
";
    my $ids = $self->_execute_query($query, [$circuit_id]);
    if (!defined $ids){
	$self->_set_error("Internal error while fetching circuit internal vlan ids.");
	return;
    }

    my $results;

    foreach my $row (@$ids){
	my $path_type = $row->{'path_type'};
	my $interface_a       = $row->{'interface_a_id'};
        my $vlan_a = $row->{'interface_a_vlan_id'};
        my $interface_z       = $row->{'interface_z_id'};
        my $vlan_z = $row->{'interface_z_vlan_id'};
	my $node_a      = $row->{'node_a_name'};
	my $node_z      = $row->{'node_z_name'};
        
	$results->{$path_type}->{$node_a}->{$interface_a} = $vlan_a;
        $results->{$path_type}->{$node_z}->{$interface_z} = $vlan_z;
        
    }

    return $results;
}

=head2 get_circuit_endpoints

Returns an array of hashes containing information about the endpoints for the circuit.
##cviecco make no sense to return multiple urls, but we will!

=over

=item circuit_id

The internal MySQL primary key int identifier for this circuit.

=back

=cut

sub get_circuit_endpoints {
    my $self = shift;
    my %args = @_;

    #my $query = "select * from circuit_edge_interface_membership where circuit_edge_interface_membership.circuit_id = ? and circuit_edge_interface_membership.end_epoch = -1";
    my $query = "select distinct(interface.interface_id), circuit_edge_interface_membership.extern_vlan_id, circuit_edge_interface_membership.circuit_edge_id, interface.name as int_name,interface.description as interface_description, node.name as node_name, node.node_id as node_id, interface.port_number, interface.role, network.is_local from interface left join  interface_instantiation on interface.interface_id = interface_instantiation.interface_id and interface_instantiation.end_epoch = -1 join node on interface.node_id = node.node_id left join node_instantiation on node_instantiation.node_id = node.node_id and node_instantiation.end_epoch = -1 join network on node.network_id = network.network_id join circuit_edge_interface_membership on circuit_edge_interface_membership.interface_id = interface.interface_id where circuit_edge_interface_membership.circuit_id = ? and ";

    my @bind_values = ($args{'circuit_id'});

    if ($args{'show_historical'} ){
        #we set end_epoch in bulk, so it should be safe to get the set of edge_interfaces with the max end_epoch.
        $query .= "circuit_edge_interface_membership.end_epoch = (select max(end_epoch) from circuit_edge_interface_membership where circuit_id = ? )";
        push(@bind_values,$args{'circuit_id'});
    }else{
        $query .= "circuit_edge_interface_membership.end_epoch = -1";
    }


    my $res = $self->_execute_query($query, \@bind_values);
    my $results;
    
    foreach my $endpoint ( @$res ){
        
        my $urns = $self->_execute_query("select * from urn where interface_id = ?", [$endpoint->{'interface_id'}]);
        if(scalar(@$urns) == 1){
            $endpoint->{'urn'} = $urns->[0]->{'urn'};
        }elsif(scalar(@$urns) > 1){
            foreach my $urn (@$urns){
                
                my $tag_range = $self->_process_tag_string($urn->{'vlan_tag_range'});

                foreach my $tag (@$tag_range){
                    if($tag == $endpoint->{'extern_vlan_id'}){
                        $endpoint->{'urn'} = $urn->{'urn'};
                    }
                }
            }
            #couldn't find it, so just use the first one
            if(!defined($endpoint->{'urn'})){
                $endpoint->{'urn'} = $urns->[0]->{'urn'};
            }
        }

        my $mac_addrs = $self->_execute_query("select mac_address from circuit_edge_mac_address where circuit_edge_id = ?",[$endpoint->{'circuit_edge_id'}]);
        
        foreach my $mac_addr (@$mac_addrs){
            $mac_addr->{'mac_address'} = mac_num2hex($mac_addr->{'mac_address'});
        }
        
        
        push (@$results, {'node'      => $endpoint->{'node_name'},
                          'interface' => $endpoint->{'int_name'},
                          'tag'       => $endpoint->{'extern_vlan_id'},
                          'node_id'   => $endpoint->{'node_id'},
                          'port_no'   => $endpoint->{'port_number'},
                          'local'     => $endpoint->{'is_local'},
                          'role'      => $endpoint->{'role'},
                          'interface_description' => $endpoint->{'interface_description'},
                          'urn'       => $endpoint->{'urn'},
                          'mac_addrs' => $mac_addrs
              }
            );
    }
    
    return $results;

}

=head2 get_path_links

=cut

sub get_path_links{
    my $self = shift;
    my %args = @_;

    my $path_id = $args{'path_id'};

    if(!defined($path_id)){
	return;
    }

    my $query = "select link.link_id, link.name from link_path_membership, link where link.link_id = link_path_membership.link_id and link_path_membership.end_epoch = -1 and link_path_membership.path_id = ? ";

    my $results = $self->_execute_query($query,[$path_id]);

    return $results;

}

=head2 get_circuit_links

Returns an array of hashes containing information about the path links for the circuit. If no type is given, it assumes primary path links.

=over

=item circuit_id

The internal MySQL primary key int identifier for this circuit.

=item type (optional)

Determines which path to find links for. Valid options are 'primary' and 'backup'. If not given defauls to 'primary'.

=back

=cut


sub get_circuit_links {
    my $self = shift;
    my %args = @_;

    if (! $args{'type'}){
	$args{'type'} = 'primary';
    }

    my $dbh = $self->{'dbh'};

    my $query = "select link.name, node_a.name as node_a, if_a.name as interface_a, if_a.interface_id as interface_a_id, if_a.port_number as port_no_a, node_z.name as node_z, if_z.name as interface_z, if_z.interface_id as interface_z_id, if_z.port_number as port_no_z from link " .
	" join link_path_membership on link_path_membership.link_id = link.link_id " .
	"  and link_path_membership.end_epoch = -1 " .
        " join link_instantiation link_inst on link.link_id = link_inst.link_id and link_inst.end_epoch = -1".
	" join path on path.path_id = link_path_membership.path_id and path.circuit_id = ? " .
	"  and path.path_type = ? ".
	" join interface if_a on link_inst.interface_a_id = if_a.interface_id ".
 	" join interface if_z on link_inst.interface_z_id = if_z.interface_id ".
	" join node node_a on if_a.node_id = node_a.node_id ".
	" join node node_z on if_z.node_id = node_z.node_id ";

 if ($args{'show_historical'} == 1) { # For some reason this is evaluating to true
     $query = "select link.name, node_a.name as node_a, if_a.name as interface_a, if_a.port_number as port_no_a, node_z.name as node_z, if_z.name as interface_z, if_z.port_number as port_no_z ".
         "from path join link_path_membership on path.path_id = link_path_membership.path_id ".
         "and path.circuit_id = ? and path.path_type= ? and link_path_membership.end_epoch= (select max(end_epoch) from link_path_membership m where m.path_id = path.path_id) ".
         "join link on link_path_membership.link_id = link.link_id ".
         "join link_instantiation link_inst on link.link_id = link_inst.link_id and link_inst.end_epoch = -1 ".
         "join interface if_a on link_inst.interface_a_id = if_a.interface_id ".
         "join interface if_z on link_inst.interface_z_id = if_z.interface_id  join node node_a on if_a.node_id = node_a.node_id  join node node_z on if_z.node_id = node_z.node_id ";
    }
    my $sth = $self->_prepare_query($query) or return;

    $sth->execute($args{'circuit_id'},
		  $args{'type'}
	         );

    my @results;

    while (my $row = $sth->fetchrow_hashref()){
	push (@results, { name        => $row->{'name'},
			  node_a      => $row->{'node_a'},
			  port_no_a   => $row->{'port_no_a'},
			  interface_a => $row->{'interface_a'},
                          interface_a_id => $row->{'interface_a_id'},
			  node_z      => $row->{'node_z'},
			  port_no_z   => $row->{'port_no_z'},
			  interface_z => $row->{'interface_z'},
                          interface_z_id => $row->{'interface_z_id'}
	      });
    }

    return \@results;
}

=head2 get_interface_speed

=cut

sub get_interface_speed{
    my $self = shift;
    my %args = @_;

    my $interface_id = $args{'interface_id'};

    my $query = "select * from interface_instantiation where end_epoch = -1 and interface_id = ?";

    my $results = $self->_execute_query($query, [$interface_id]);
    if (! defined $results){
        $self->_set_error("Internal error getting interface information.");
        return;
    }

    return @$results[0]->{'capacity_mbps'};
}

=head2 get_interface

Returns a hash with information about an interface identified by $interface_id

=over

=item interface_id

The internal MySQL primary key int identifier for this interface.

=back

=cut

sub get_interface {
    my $self = shift;
    my %args = @_;

    my $interface_id = $args{'interface_id'};

    my $query = "select interface.interface_id, interface.name,interface_instantiation.capacity_mbps as speed, interface.port_number, interface.description, interface.operational_state, interface.role, interface.node_id, interface.vlan_tag_range, workgroup.workgroup_id, workgroup.name as workgroup_name, node.name as node_name ";
    $query   .= "from interface natural join interface_instantiation ";
    $query   .= "left join workgroup on interface.workgroup_id = workgroup.workgroup_id ";
    $query   .= "left join node on node.node_id = interface.node_id ";
    $query   .= "where interface_id = ?";

    my $results = $self->_execute_query($query, [$interface_id]);

    if (! defined $results){
	$self->_set_error("Internal error getting interface information.");
	return;
    }

    return @$results[0];
}

=head2 get_interface_by_dpid_and_port

=cut

sub get_interface_by_dpid_and_port{
    my $self = shift;
    my %args = @_;

    if(!defined($args{'port_number'})){
	$self->_set_error("Interface Port Number not specified");
	return;
    }

    if(!defined($args{'dpid'})){
	$self->_set_error("DPID not specified");
	return;
    }

    my $interface = $self->_execute_query("select interface.name,interface.port_number,interface.node_id,interface.interface_id from node,node_instantiation,interface where node.node_id = node_instantiation.node_id and interface.node_id = node.node_id  and node_instantiation.end_epoch = -1 and node_instantiation.dpid = ? and interface.port_number = ?",[$args{'dpid'},$args{'port_number'}])->[0];

    return $interface;

}

=head2 update_interface_operational_state

=cut

sub update_interface_operational_state{
    my $self = shift;
    my %args = @_;

    if(!defined($args{'interface_id'})){
	$self->_set_error("Interface ID was not specified");
	return;
    }

    if(!defined($args{'operational_state'})){
	$self->_set_error("Operational State not specified");
	return;
    }

    my $res = $self->_execute_query("update interface set operational_state = ? where interface.interface_id = ?",[$args{'operational_state'},$args{'interface_id'}]);
    if(!defined($res)){
	$self->_set_error("Unable to update interfaces operational state");
	return;
    }

    return 1;
}

=head2 update_interface_vlan_range

=cut

sub update_interface_vlan_range{
    my $self = shift;
    my %args = @_;

    if(!defined($args{'interface_id'})){
	$self->_set_error("Interface ID was not specified");
	return;
    }

    if(!defined($args{'vlan_tag_range'})){
	return;
    }

    my $parse_results = $self->_process_tag_string( $args{'vlan_tag_range'} );

    if(!defined($parse_results)){
	print STDERR "Args: " . $args{'vlan_tag_range'} . " not a valid Vlan tag string\n";
	return 0;
    }

    $self->_execute_query("update interface set vlan_tag_range = ? where interface.interface_id = ?",[$args{'vlan_tag_range'},$args{'interface_id'}]);

    return 1;

}

=head2 update_interface_description

Updates the description of a matching interface

=over

=item description

The description of the interface.

=item interface_id

The ID of the interface to update

=back

=cut

sub update_interface_description{
    my $self = shift;
    my %args = @_;
    if(!defined($args{'interface_id'})){
        $self->_set_error("Interface ID was not specified");
        return;
    }
    if(!defined($args{'description'})){
        $self->_set_error("description was not specified");
        return;
    }

    my $res = $self->_execute_query("update interface set description = ? where interface.interface_id = ?",[$args{'description'},$args{'interface_id'}]);
    if(!defined($res)){
        $self->_set_error("Unable to update interface description");
        return;
    }
    return 1;
}

=head2 get_interface_id_by_names

Returns the interface_id of the interface with name $interface on the node with name $node.

=over

=item node

The name of the node this interface is on.

=item interface

The name of the interface.

=back

=cut

sub get_interface_id_by_names{
    my $self = shift;
    my %args = @_;

    my $dbh = $self->{'dbh'};

    my $node_name      = $args{'node'};
    my $interface_name = $args{'interface'};

    my $select_interface_query = "select interface_id from interface where name=? and node_id=(select node_id from node where name=?)";
    my $select_interface_sth   = $self->_prepare_query($select_interface_query) or return;

    $select_interface_sth->execute($interface_name,$node_name);

    if(my $row = $select_interface_sth->fetchrow_hashref()){
	return $row->{'interface_id'};
    }

    $self->_set_error("Unable to find interface $interface_name on $node_name");

    return;
}

=head2 confirm_node

Sets a node from available state to active state and sets the node's name, latitude, and longitude for visualization.

=over

=item node_id

The internal MySQL primary key int identifier for this node.

=item name

The name to set for this node.

=item latitude

The latitude of this node as it should appear on the map.

=item longitude

The longitude of this node as it should appear on the map.

=back

=cut

sub confirm_node {
    my $self = shift;
    my %args = @_;

    my $node_id    = $args{'node_id'};
    my $name       = $args{'name'};
    my $lat        = $args{'latitude'};
    my $long       = $args{'longitude'};
    my $vlan_range = $args{'vlan_range'};
    my $default_drop = $args{'default_drop'};
    my $default_forward = $args{'default_forward'};
    my $max_flows = $args{'max_flows'};
    my $tx_delay_ms = $args{'tx_delay_ms'};
    my $bulk_barrier = $args{'bulk_barrier'};
    if(!defined($default_drop)){
	$default_drop = 1;
    }
    if(!defined($default_forward)){
	$default_forward = 1;
    }
    if(!defined($bulk_barrier)){
	$bulk_barrier = 0;
    }

    $self->_start_transaction();

    my $result = $self->_execute_query("update node_instantiation set admin_state = 'active' where node_id = ? and admin_state = 'available'", [$node_id]);

    if ($result != 1){
	$self->_set_error("Error updating node instantiation.");
	$self->_rollback();
    return;
    }

    $result = $self->_execute_query("update node set name = ?, longitude = ?, latitude = ?, vlan_tag_range = ?, default_drop = ?, default_forward = ?, max_flows = ?, tx_delay_ms = ?, send_barrier_bulk = ?  where node_id = ?",
	                            [$name, $long, $lat, $vlan_range,$default_drop, $default_forward,$max_flows,$tx_delay_ms,$bulk_barrier,$node_id]
	                           );

    if ($result != 1){
	$self->_set_error("Error updating node.");
	$self->_rollback();
    return;
    }

    $self->_commit();

    return 1;
}

=head2 update_node

=cut
sub update_node {
    my $self = shift;
    my %args = @_;

    my $node_id    = $args{'node_id'};
    my $name       = $args{'name'};
    my $lat        = $args{'latitude'};
    my $long       = $args{'longitude'};
    my $vlan_range = $args{'vlan_range'};
    my $default_drop = $args{'default_drop'};
    my $default_forward= $args{'default_forward'};
    my $max_flows = $args{'max_flows'} || 0;
    my $tx_delay_ms = $args{'tx_delay_ms'} || 0;
    my $barrier_bulk = $args{'bulk_barrier'} || 0;
    my $max_static_mac_flows = $args{'max_static_mac_flows'} || 0;

    if(!defined($default_drop)){
	$default_drop =1;
    }
    if(!defined($default_forward)){
        $default_forward = 1;
    }

    if(!defined($barrier_bulk)){
	$barrier_bulk = 0;
    }


    $self->_start_transaction();

    my $result = $self->_execute_query("update node set name = ?, longitude = ?, latitude = ?, vlan_tag_range = ?,default_drop = ?, default_forward = ?, tx_delay_ms = ?, max_flows = ?, send_barrier_bulk = ?, max_static_mac_flows = ? where node_id = ?",
				       [$name, $long, $lat, $vlan_range,$default_drop,$default_forward,$tx_delay_ms, $max_flows, $barrier_bulk, $max_static_mac_flows, $node_id]
	                              );

    if ($result != 1){
	$self->_set_error("Error updating node.");
	$self->_rollback();
	return;
    }

    $self->_commit();

    return 1;
}

=head2 decom_node

=cut
sub decom_node {
    my $self = shift;
    my %args = @_;

    my $node_id = $args{'node_id'};

    $self->_start_transaction();

    my $result = $self->_execute_query("update node set operational_state = 'down', name = concat(name, '-', node_id, '-decomed') where node_id = ?",
				       [$node_id]
	                              );

    if ($result != 1){
	$self->_set_error("Error updating node.");
	$self->_rollback();
	return;
    }

    $result = $self->_execute_query("update node_instantiation set end_epoch = unix_timestamp(NOW()) where end_epoch = -1 and node_id = ?",
				    [$node_id]);

    if ($result != 1){
	$self->_set_error("Error updating node instantiation.");
	$self->_rollback();
	return;
    }

    $result = $self->_execute_query("update interface_instantiation join interface on interface.interface_id = interface_instantiation.interface_id set end_epoch = unix_timestamp(NOW()) where end_epoch = -1 and node_id = ?",
				    [$node_id]);

    if (! defined $result){
	$self->_set_error("Error updating interface instantiations.");
	$self->_rollback();
	return;
    }

    $result = $self->_execute_query("update link_instantiation set end_epoch = unix_timestamp(NOW()) where end_epoch = -1 and (interface_a_id in (select interface_id from interface where node_id = ?) or interface_z_id in (select interface_id from interface where node_id = ?))",
				    [$node_id, $node_id]);

    if (! defined $result){
	$self->_set_error("Error updating link instantiations.");
	$self->_rollback();
	return;
    }

    $self->_commit();

    return 1;
}



=head2 confirm_link

Sets a link from available state to active state and sets the link's name. Also updates the link's
endpoint interfaces to be trunk interfaces.

=over

=item link_id

The internal MySQL primary key int identifier for this link.

=item name

The name to set for this link.

=back

=cut

sub confirm_link {
    my $self = shift;
    my %args = @_;

    my $link_id = $args{'link_id'};
    my $name    = $args{'name'};

    $self->_start_transaction();

    my $result = $self->_execute_query("update link_instantiation set link_state = 'active' where link_id = ? and link_state = 'available' and end_epoch = -1", [$link_id]);

    if ($result != 1){
	$self->_set_error("Error updating link instantiation.");
	$self->_rollback();
    return;
    }

    $result = $self->_execute_query("update link set name = ? where link_id = ?", [$name, $link_id]);

    if ($result != 1){
	$self->_set_error("Error updating link name.");
	$self->_rollback();
    return;
    }

    $result = $self->_execute_query("update interface " .
				    " join link_instantiation on interface.interface_id in (link_instantiation.interface_a_id, link_instantiation.interface_z_id) " .
				    " set role = 'trunk' " .
				    " where link_instantiation.link_id = ?",
				    [$link_id]);

    if (! $result){
	$self->_set_error("Error updating link endpoints to trunks.");
	$self->_rollback();
    return;
    }

    $self->_commit();

    return 1;
}

=head2 update_link_state

=cut
sub update_link_state{
    my $self = shift;
    my %args = @_;

    my $link_id = $args{'link_id'};
    my $state = $args{'state'};

    if(!defined($link_id)){
	$self->_set_error("No Link ID specified");
    return;
    }

    if(!defined($state)){
	$state = 'down';
    }

    my $result = $self->_execute_query("update link set status = ? where link_id = ?",[$state,$link_id]);
    if($result != 1){
	$self->_set_error("Error updating link state");
    return;
    }

    return 1;
}

=head2 update_link_fv_state

=cut

sub update_link_fv_state{
    my $self = shift;
    my %args = @_;

    my $link_id = $args{'link_id'};
    my $state = $args{'state'};

    if(!defined($link_id)){
        $self->_set_error("No Link ID specified");
	return;
    }

    if(!defined($state)){
        $state = 'down';
    }

    my $result = $self->_execute_query("update link set fv_status = ? where link_id = ?",[$state,$link_id]);
    if($result != 1){
        $self->_set_error("Error updating link state");
	return;
    }

    return 1;
}

=head2 update_link

=cut

sub update_link {
    my $self = shift;
    my %args = @_;

    my $link_id = $args{'link_id'};
    my $name    = $args{'name'};
    my $metric  = $args{'metric'};

    $self->_start_transaction();

    my $sql  = "UPDATE link SET";
       $sql .= " name = ?,";
       $sql .= " metric = ?";
       $sql .= " WHERE link_id = ?";
    my $result = $self->_execute_query($sql, [$name, $metric, $link_id]);

    if ($result != 1){
	$self->_set_error("Error updating link.");
	$self->_rollback();
    return;
    }

    $self->_commit();

    return 1;
}

=head2 is_new_node_in_path

=cut

sub is_new_node_in_path{
    my $self = shift;
    my %args = @_;

    my $link_details = $args{'link'};
    if(!defined($link_details)){
	return {error => "No Link specified", results =>[]};
    }

    #find the 2 links that now make up this path
    my ($new_path,$node_id) = $self->_find_new_path( link => $link_details);

    if(!defined($new_path)){
	return 0;
    }else{
	return 1;
    }
}

sub _find_new_path{
    my $self = shift;
    my %args = @_;

    my $link = $args{'link'};

    #ok so the link is down
    #need to check and see if a new link exists
    my $endpoints = $self->get_link_endpoints( link_id => $link->{'link_id'});
    my $a_links = $self->get_link_by_interface_id( interface_id => $endpoints->[0]->{'interface_id'});
    my $z_links = $self->get_link_by_interface_id( interface_id => $endpoints->[1]->{'interface_id'});

    my $a_link;
    my $z_link;
    #ok we need to have 2 links for each of the interfaces
    if($#{$a_links} >= 1){
	foreach my $test_link (@{$a_links}){
	    next if($test_link->{'link_id'} == $link->{'link_id'});
	    if($test_link->{'status'} eq 'up'){
		$a_link = $test_link;
	    }
	}
    }else{
	#no second link... not capable of creating a new path
	return;
    }

    if($#{$z_links} >= 1){
	foreach my $test_link (@{$z_links}){
	    next if($test_link->{'link_id'} == $link->{'link_id'});
	    if($test_link->{'status'} eq 'up'){
                $z_link= $test_link;
            }
	}
    }else{
	#no second link... not capable of creating a new path
	return;
    }

    if(defined($z_link) && defined($a_link)){
	my $z_endpoints = $self->get_link_endpoints(link_id => $z_link->{'link_id'});
	my $a_endpoints = $self->get_link_endpoints(link_id => $a_link->{'link_id'});

	my $new_a_int;
	my $new_z_int;

	foreach my $ep (@$a_endpoints){
	    next if($ep->{'interface_id'} == $endpoints->[0]->{'interface_id'});
	    $new_a_int = $ep;
	}

	foreach my $ep (@$z_endpoints){
	    next if($ep->{'interface_id'} == $endpoints->[1]->{'interface_id'});
	    $new_z_int = $ep;
	}

	if($new_z_int->{'node_id'} == $new_a_int->{'node_id'}){
	    return ([$a_link->{'link_id'},$z_link->{'link_id'}],$new_z_int->{'node_id'},$new_a_int,$new_z_int);
	}

    }else{
	return;
    }
}

=head2 insert_node_in_path

=cut

sub insert_node_in_path{
    my $self = shift;
    my %args = @_;

    my $link = $args{'link'};
    if(!defined($link)){
	return {error => 'no link specified to insert node'};
    }

    my $link_details = $self->get_link( link_id => $link);


    #find the 2 links that now make up this path
    my ($new_path,$node_id,$new_a_int,$new_z_int) = $self->_find_new_path( link => $link_details);

    if(!defined($new_path)){
	return {error => "no new paths found"};
    }

    #ok first decom the old
    my $circuits = $self->get_circuits_on_link( link_id => $link_details->{'link_id'});

    $self->decom_link(link_id => $link_details->{'link_id'});

    $self->confirm_link(link_id => $new_path->[0], name => $link_details->{'name'} . "-1");
    $self->confirm_link(link_id => $new_path->[1], name => $link_details->{'name'} . "-2");
    my $new_link_a_endpoints = $self->get_link_endpoints(link_id => $new_path->[0]); 
    my $new_link_z_endpoints = $self->get_link_endpoints(link_id => $new_path->[1]); 
    my $service;
    my $client;

    my $bus = Net::DBus->system;

    eval {
	$service = $bus->get_service("org.nddi.fwdctl");
	$client  = $service->get_object("/controller1");
    };

    if ($@) {
	warn "Error in _connect_to_fwdctl: $@";
	return;
    }


    if ( !defined $client ) {
	return;
    }

    my @events;

    foreach my $circuit (@$circuits){
	#first we need to connect to DBus and remove the circuit from the switch...
	my ($result,$event_id) = $client->deleteVlan($circuit->{'circuit_id'});
        push(@events,$event_id);

	#ok now update the links
	my $links = $self->_execute_query("select * from link_path_membership, path, path_instantiation where path.path_id = path_instantiation.path_id and path_instantiation.end_epoch = -1 and link_path_membership.path_id = path.path_id and path.circuit_id = ? and link_path_membership.end_epoch = -1",[$circuit->{'circuit_id'}]);


	foreach my $link (@$links){

	    if($link->{'link_id'} == $link_details->{'link_id'}){
		#remove it and add 2 more
                my $original_a_vlan_id = $link->{'interface_a_vlan_id'};
                my $original_z_vlan_id = $link->{'interface_z_vlan_id'};
		$self->_execute_query("update link_path_membership set end_epoch = unix_timestamp(NOW()) where link_id = ? and path_id = ? and end_epoch = -1",[$link->{'link_id'},$link->{'path_id'}]);


                
		#add the new links to the path #TODO 
		my $new_internal_vlan_a = $self->_get_available_internal_vlan_id(node_id => $node_id,interface_id => $new_a_int->{'interface_id'});
                my $new_internal_vlan_z = $self->_get_available_internal_vlan_id(node_id => $node_id,interface_id => $new_z_int->{'interface_id'});
                
                if(!defined($new_internal_vlan_a) || !defined($new_internal_vlan_z) ){
		    return {success => 0, error => "Internal Error finding available internal vlan"};
		}
                                #figure out the correct insertion order for the new link_path_memberships (there is no requirement that the new endpoint be the z end of either link.
                my $bindparams_a= [$new_path->[0],$link->{'path_id'}];
                my $bindparams_z= [$new_path->[1],$link->{'path_id'}];

                #$int_a is the new interface on the inserted node for link a, $int_z the same for new_link z

                if($new_a_int->{'interface_id'} == $new_link_a_endpoints->[0]->{'interface_a_id'})
                {
                    #new added interface is a end
                    push (@$bindparams_a , $new_internal_vlan_a,$original_a_vlan_id);
                }
                else{
                    push (@$bindparams_a , $original_a_vlan_id, $new_internal_vlan_a);
                }

                if($new_z_int->{'interface_id'} == $new_link_z_endpoints->[0]->{'interface_a_id'})
                {
                    #new added interface is a end
                    push (@$bindparams_z , $new_internal_vlan_z, $original_z_vlan_id);
                }
                else{
                    push (@$bindparams_z , $original_z_vlan_id, $new_internal_vlan_z);
                }
                $self->_execute_query("insert into link_path_membership (end_epoch,link_id,path_id,start_epoch,interface_a_vlan_id,interface_z_vlan_id) VALUES (-1,?,?,unix_timestamp(NOW()),?,?)",$bindparams_a);
                $self->_execute_query("insert into link_path_membership (end_epoch,link_id,path_id,start_epoch,interface_a_vlan_id,interface_z_vlan_id) VALUES (-1,?,?,unix_timestamp(NOW()),?,?)",$bindparams_z);
	    }
	}

	#re-add circuit
	($result,$event_id) = $client->addVlan($circuit->{'circuit_id'});
        push(@events,$event_id);
    }

    while(scalar(@events) > 0){
        for(my $i=0;$i <= $#events;$i++){
            my $res = $client->get_event_status($events[$i]);
            if($res != FWDCTL_WAITING){
                delete $events[$i];
            }
        }
    }

    return {success => 1};

}

=head2 decom_link

=cut
sub decom_link {
    my $self = shift;
    my %args = @_;

    my $link_id = $args{'link_id'};

    if(!defined($link_id)){
	$self->_set_error("Link ID not specified");
	return;
    }

    $self->_start_transaction();

    my $link_details = $self->get_link( link_id => $link_id );

    my $result = $self->_execute_query("update link_instantiation set end_epoch = unix_timestamp(NOW()) where end_epoch = -1 and link_id = ?", [$link_id]);

    if ($result != 1){
	$self->_set_error("Error updating link instantiation.");
	$self->_rollback();
    return;
    }

    $self->_execute_query("insert into link_instantiation (end_epoch,start_epoch,link_state,link_id,interface_a_id,interface_z_id) VALUES (-1,unix_timestamp(NOW()),'decom',?,?,?)",[$link_details->{'link_id'},$link_details->{'interface_a_id'},$link_details->{'interface_z_id'}]);

    if($link_details->{'status'} eq 'down'){
	#link does not appear to be connected... set the interfaces back to "unknown" state

	my $update_interface_role = "update interface set role = 'unknown' where interface_id = ?";
	my $res = $self->_execute_query($update_interface_role,[$link_details->{'interface_a_id'}]);
	$res = $self->_execute_query($update_interface_role,[$link_details->{'interface_z_id'}]);
    }else{
	#link is still up so its connected create a new instantiation waiting for approval
	$self->_execute_query("update link_instantiation set end_epoch = unix_timestamp(NOW()) where end_epoch = -1 and link_id = ?", [$link_id]);
	$self->_execute_query("insert into link_instantiation (end_epoch, start_epoch, link_state, link_id, interface_a_id, interface_z_id) VALUES (-1,unix_timestamp(NOW()),'available',?,?,?)",[$link_id,$link_details->{'interface_a_id'},$link_details->{'interface_z_id'}]);

    }

    $self->_commit();

    return 1;
}

=head2 delete_link

Deletes the link specified by link_id. This removes any instantiations it might have had as well. This operation should only be performed on links with remote_urns since circuits will not, in this database,
traverse those links.

=cut

sub delete_link {
    my $self = shift;
    my %args = @_;

    my $link_id = $args{'link_id'};

    $self->_start_transaction();

    my $result = $self->_execute_query("delete from link_instantiation where link_id = ?", [$link_id]);

    $result = $self->_execute_query("delete from link where link_id = ?", [$link_id]);

    if (! defined $result){
	$self->set_error("Unable to delete link: " . $self->get_error());
	$self->_rollback();
    return;
    }

    $self->_commit();

    return 1;
}


=head2 get_pending_nodes

Returns an array of hashes containing data about all of the discovered nodes that are currently sitting in the 'available' state and thus are pending confirmation.

=cut

sub get_pending_nodes {
    my $self = shift;
    my %args = @_;

    my $sth = $self->_prepare_query("select node.node_id, node_instantiation.dpid, inet_ntoa(node_instantiation.management_addr_ipv4) as address, " .
				    " node.name, node.longitude, node.latitude, node.vlan_tag_range, node.send_barrier_bulk " .
				    " from node join node_instantiation on node.node_id = node_instantiation.node_id " .
				    " where node_instantiation.admin_state = 'available' and node_instantiation.end_epoch = -1"
	                           ) or return;

    $sth->execute();

    my $results = [];

    while (my $row = $sth->fetchrow_hashref()){
	push (@$results, {"node_id"    => $row->{'node_id'},
			  "dpid"       => sprintf("%x",$row->{'dpid'}),
			  "ip_address" => $row->{'address'},
			  "name"       => $row->{'name'},
			  "longitude"  => $row->{'longitude'},
			  "latitude"   => $row->{'latitude'},
			  "vlan_range" => $row->{'vlan_tag_range'}
	                 }
	    );
    }

    return $results;
}

=head2 get_pending_links

Returns an array of hashes containing data about all of the discovered links that are currently sitting in the 'available' state and thus are pending confirmation.

=cut

sub get_pending_links {
    my $self = shift;
    my %args = @_;

    my $sth = $self->_prepare_query("select link.link_id, link.name as link_name, nodeA.name as nodeA, nodeB.name as nodeB, intA.name as intA, intB.name as intB, intA.interface_id as int_a_id, intB.interface_id as int_b_id " .
				    " from link join link_instantiation on link.link_id = link_instantiation.link_id " .
				    " join interface intA on intA.interface_id = link_instantiation.interface_a_id " .
				    "  join interface_instantiation iiA on intA.interface_id = iiA.interface_id " .
				    "   and iiA.end_epoch = -1 " .
				    " join interface intB on intB.interface_id = link_instantiation.interface_z_id " .
				    "  join interface_instantiation iiB on intB.interface_id = iiB.interface_id " .
				    "   and iiB.end_epoch = -1 " .
				    " join node nodeA on nodeA.node_id = intA.node_id " .
				    "  join node_instantiation niA on nodeA.node_id = niA.node_id and niA.end_epoch = -1 " .
				    "   and niA.admin_state = 'active' " .
				    " join node nodeB on nodeB.node_id = intB.node_id " .
				    "  join node_instantiation niB on nodeB.node_id = niB.node_id and niB.end_epoch = -1 " .
				    "   and niB.admin_state = 'active' " .
				    " where link_instantiation.link_state = 'available' and link_instantiation.end_epoch = -1"
	                           ) or return;

    $sth->execute();

    my $links = [];

    while (my $row = $sth->fetchrow_hashref()){

	push(@$links, {'link_id'   => $row->{'link_id'},
		       'name'      => $row->{'link_name'},
		       'endpoints' => [{'node'      => $row->{'nodeA'},
					'interface' => $row->{'intA'},
                    'interface_id' => $row->{'int_a_id'}
				       },
				       {'node'      => $row->{'nodeB'},
					'interface' => $row->{'intB'},
                    'interface_id' => $row->{'int_b_id'}
				       }
			              ]
	             }
	    );
    }

    return $links;
}

=head2 get_link_ints_on_node

=cut

sub get_link_ints_on_node{
    my $self = shift;
    my %args = @_;

    my $str = "select interface.* from link, link_instantiation, interface where link.link_id = link_instantiation.link_id and link_instantiation.end_epoch = -1 and link_instantiation.interface_a_id = interface.interface_id and interface.node_id = ?";

    my $ints = $self->_execute_query($str,[$args{'node_id'}]);

    $str = "select interface.* from link, link_instantiation, interface where link.link_id = link_instantiation.link_id and link_instantiation.end_epoch = -1 and link_instantiation.interface_z_id = interface.interface_id and interface.node_id = ?";

    my $ints2 = $self->_execute_query($str,[$args{'node_id'}]);

    foreach my $int (@$ints2){
	push(@$ints,$int);
    }
    return $ints;
}

=head2 get_link

should use this everywhere

=cut

sub get_link{
    my $self = shift;
    my %args = @_;



    if(!defined($args{'link_id'}) && !defined($args{'link_name'})){
	$self->_set_error("No Link_id or link_name specified");
	return;
    }

    if(defined($args{'link_id'})){
	my $link = $self->_execute_query("select * from link natural join link_instantiation where link_id = ? and link_instantiation.end_epoch = -1",[$args{'link_id'}])->[0];
	return $link;
    }else{
	my $link = $self->_execute_query("select * from link natural join link_instantiation where name = ? and link_instantiation.end_epoch = -1",[$args{'link_name'}])->[0];
	return $link;
    }

    #uh... not possible?
    return;

}

=head2 get_link_by_name

=cut

sub get_link_by_name{
    my $self = shift;
    my %args = @_;

    if(!defined($args{'name'})){
	$self->_set_error("Link name was not specified");
	return;
    }

    my $link = $self->_execute_query("select * from link where name = ?",[$args{'name'}])->[0];
    return $link;

}

=head2 get_links_details_by_name

=cut

sub get_links_details_by_name {
    my $self = shift;
    my %args = @_;

    my $links = [];
    foreach my $name (@{$args{'names'}}){
        my $link = $self->get_link_details( name => $name );
        if(!$link){
            $self->_set_error("Error getting link, ".$name);
            return;
        }
        push(@$links, $link); 
    }

    return $links;
}

=head2 get_link_details

=cut

sub get_link_details {
    my ($self, %args) = @_;

    my $query = "select link.name, node_a.name as node_a, if_a.name as interface_a, if_a.interface_id as interface_a_id, if_a.port_number as port_no_a, node_z.name as node_z, if_z.name as interface_z, if_z.interface_id as interface_z_id, if_z.port_number as port_no_z from link " .
    " join link_instantiation link_inst on link.link_id = link_inst.link_id and link_inst.end_epoch = -1".
	" join interface if_a on link_inst.interface_a_id = if_a.interface_id ".
 	" join interface if_z on link_inst.interface_z_id = if_z.interface_id ".
	" join node node_a on if_a.node_id = node_a.node_id ".
	" join node node_z on if_z.node_id = node_z.node_id ".
    " where link.name = ?";
    
    my $link = $self->_execute_query($query,[$args{'name'}])->[0];

    return $link;
}


=head2 get_link_by_dpid_and_port

Returns a hash with link information for a link identified on the node with $dpid and the specified port number.

=over

=item dpid

The dpid of the node. This is whatever the switch uses to identify itself in Openflow.

=item port

The number of the port the link(s) are on.

=back

=cut

sub get_link_by_dpid_and_port {
    my $self = shift;
    my %args = @_;

    my $dpid = $args{'dpid'};
    my $port = $args{'port'};

    my $query = "select link.name, link.link_id from link " .
	        " join link_instantiation on link.link_id = link_instantiation.link_id " .
		"  and link_instantiation.end_epoch = -1 " .
		" join interface on interface.interface_id in (link_instantiation.interface_a_id, link_instantiation.interface_z_id) " .
		" join interface_instantiation on interface.interface_id = interface_instantiation.interface_id " .
		"  and interface_instantiation.end_epoch = -1 " .
		" join node on node.node_id = interface.node_id " .
		" join node_instantiation on node.node_id = node_instantiation.node_id " .
		"  and node_instantiation.end_epoch = -1 " .
		" where node_instantiation.dpid = ? and interface.port_number = ? and link_instantiation.link_state != 'decom'";

    my $result = $self->_execute_query($query, [$dpid, $port]);

    return $result;
}

=head2 get_link_endpoints

=cut

sub get_link_endpoints {
    my $self = shift;
    my %args = @_;

    my $link_id = $args{'link_id'};

    my $query = "select node.node_id, node.name as node_name, interface.interface_id, interface.name as interface_name, interface.port_number as port_number, interface.description, interface.operational_state, interface.role,link_instantiation.interface_a_id,link_instantiation.interface_z_id from node ";
    $query   .= " join interface on interface.node_id = node.node_id " ;
    $query   .= " join link_instantiation on interface.interface_id in (link_instantiation.interface_a_id, link_instantiation.interface_z_id) ";
    $query   .= "  and link_instantiation.end_epoch = -1 ";
    $query   .= " where link_instantiation.link_id = ?";

    my $results = $self->_execute_query($query, [$link_id]);

    if (! defined $results){
	$self->_set_error("Internal error getting link endpoints.");
	return;
    }

    return $results;
}

=head2 get_link_id_by_name

Returns the internal identifier for a link with name $link.

=over

=item link

The name of the link to get the id for.

=back

=cut

sub get_link_id_by_name{
    my $self = shift;
    my %args = @_;

    my $dbh       = $self->{'dbh'};
    my $link_name = $args{'link'};

    my $select_link_query = "select link_id from link where name=? ";
    my $select_link_sth   = $self->_prepare_query($select_link_query) or return;

    $select_link_sth->execute($link_name);

    if(my $row = $select_link_sth->fetchrow_hashref()){
	return $row->{'link_id'};
    }

    $self->_set_error("Unable to find link $link_name");

    return;
}

=head2 get_link_by_a_or_z_end

=cut

sub get_link_by_a_or_z_end{
    my $self = shift;
    my %args = @_;

    if(!defined($args{'interface_a_id'})){
	$self->_set_error("Interface A ID not specified");
	return;
    }

    if(!defined($args{'interface_z_id'})){
	$self->_set_error("Interface Z ID Not specified");
	return;
    }

    my $links = $self->_execute_query("select * from link_instantiation where end_epoch = -1 and ((interface_a_id = ? and interface_z_id = ?) or (interface_a_id = ? and interface_z_id = ?))",[$args{'interface_a_id'},$args{'interface_z_id'},$args{'interface_z_id'},$args{'interface_a_id'}]);
    return $links;
}

=head2 get_links_by_node

Returns an array of hashes with information about all links for this node.

=over

=item node_id

The internal MySQL identifier for this node.

=back

=cut

sub get_links_by_node {
    my $self = shift;
    my %args = @_;

    my $node_id = $args{'node_id'};

    my $query = "select link.link_id, link.name as link_name, interface.* from link ";
    $query   .= " join link_instantiation on link.link_id = link_instantiation.link_id ";
    $query   .= " join interface on interface.interface_id in (link_instantiation.interface_a_id, link_instantiation.interface_z_id) ";
    $query   .= " join node on node.node_id = interface.node_id ";
    $query   .= " where node.node_id = ?";

    my $results = $self->_execute_query($query, [$node_id]);

    if (! defined $results){
	$self->_set_error("Internal error getting links for node");
	return;
    }

    return $results;
}

=head2 print_db_schema_file

A debug method to show what schema file the tests (and presumably the real database) are using.

=cut

sub print_db_schema_file{
    my $self = shift;

    warn "file_path=" . SHARE_DIR . "/share/nddi.sql";
}

=head2 reset_database

Resets the database back to being empty based on the default provided schema file.
This action is not reversible, so make any backups beforehand if desired.

This method will refuse to run unless the module level variable $ENABLE_DEVEL is set to a true value.

=cut

sub reset_database{

    my $self = shift;

    if(! $ENABLE_DEVEL){
        $self->_set_error("will not reset the db unless devel has been enabled");
        return;
    }

    my $dbh      = $self->{'dbh'};

    my $xml = XML::Simple::XMLin($self->{'config'});

    my $username = $xml->{'credentials'}->{'username'};
    my $password = $xml->{'credentials'}->{'password'};
    my $database = $xml->{'credentials'}->{'database'};

    #my $import_filename = File::ShareDir::dist_file('OESS-Database','nddi.sql');
    my $import_filename = SHARE_DIR . "/share/nddi.sql";
    warn "reset the database to $import_filename\n";
    $dbh->do("drop database $database");
    $dbh->do("create database $database");

    # satisfy taint mode
    $ENV{PATH} = "/usr/bin";

    my $success = (! system("/usr/bin/mysql -u$username -p$password $database < $import_filename"));

    # reconnect to the database
    $self->{'dbh'} = DBI->connect("DBI:mysql:$database", $username, $password);

    return $success;
}

=head2 add_into

Loads an XML schema file into the database. The schema should match that specified in share/xml/import.rnc

This method will refuse to run unless the module level variable $ENABLE_DEVEL is set to a true value.

=cut

sub add_into{

    my $self = shift;
    my %args = @_;

    if(! $ENABLE_DEVEL){
        $self->_set_error("will not reset the db unless devel has been enabled");
        return;
    }

    my $filename = $args{'xml_dump'};
    my $dbh      = $self->{'dbh'};

    my $xs = XML::Simple->new(ForceArray=>['user','workgroup','user_member','network','node','interface','link','circuit','path','member_link'],
			      KeyAttr => {user      => 'email',
					  workgroup => 'name',
					  network   => 'name',
					  node      => 'name',
					  interface => 'name',
					  link      => 'name',
					  circuit   => 'name',
			      });

    my $db_dump = $xs->XMLin($filename) or die;


    #users->
    my $users      = $db_dump->{'user'};
    my $user_query = "insert ignore into user (email,given_names,family_name) VALUES (?,?,?)";
    my $user_sth   = $self->_prepare_query($user_query) or return;

    foreach my $user_name (keys %$users){
	$user_sth->execute($user_name,
			   $users->{$user_name}->{'given_names'},
			   $users->{$user_name}->{'last_name'}
	    ) or return;
    }

    #do workgroups
    my $workgroups      = $db_dump->{'workgroup'};

    my $workgroup_query = "insert ignore into workgroup (name,description) VALUES (?,?)";
    my $workgroup_sth   = $self->_prepare_query($workgroup_query) or return;

    my $workgroup_select_query = "select workgroup_id from workgroup where name=?";
    my $workgroup_select_sth   = $self->_prepare_query($workgroup_select_query) or return;

    my $user_workgroup_insert  = 'insert into user_workgroup_membership (workgroup_id,user_id) VALUES (?,(select user_id from user where email=?))';
    my $user_workgroup_insert_sth = $self->_prepare_query($user_workgroup_insert) or return;

    foreach my $workgroup_name (keys %$workgroups){

	$workgroup_sth->execute($workgroup_name,
				$workgroups->{$workgroup_name}->{'description'}) or return;

	$workgroup_select_sth->execute($workgroup_name) or return;

	my $workgroup_db_id;
	my $row;

	if($row = $workgroup_select_sth->fetchrow_hashref()){
	    $workgroup_db_id = $row->{'workgroup_id'};
	}

	return undef unless $workgroup_db_id;

	my $users_in_workgroup = $workgroups->{$workgroup_name}->{'user_member'};

	foreach my $user (@$users_in_workgroup){
            $user_workgroup_insert_sth->execute($workgroup_db_id,
						$user) or return;
	}
    }

    #now networks
    my $network_insert_query = "insert into network (name,longitude, latitude) VALUES (?,?,?)" ;
    my $network_insert_sth   = $self->_prepare_query($network_insert_query) or return;

    my $insert_node_query = "insert into node (name,longitude,latitude, network_id) VALUES (?,?,?,(select network_id from network where name=?))";
    my $insert_node_sth   = $self->_prepare_query($insert_node_query) or return;

    my $insert_node_instantiaiton_query = "insert into node_instantiation (node_id,end_epoch,start_epoch,management_addr_ipv4,dpid,admin_state) VALUES ((select node_id from node where name=?),-1,unix_timestamp(now()),inet_aton(?),?,?)";
    my $insert_node_instantiaiton_sth   = $self->_prepare_query($insert_node_instantiaiton_query) or return;

    my $insert_interface_query = "insert into interface (name,description,node_id,operational_state) VALUES(?,?,(select node_id from node where name=?),?) ";
    my $insert_interface_sth   = $self->_prepare_query($insert_interface_query);

    my $select_interface_query = "select interface_id from interface where name=? and node_id=(select node_id from node where name=?)";
    my $select_interface_sth   = $self->_prepare_query($select_interface_query) or return;

    my $insert_interface_instantiaiton_query = "insert into interface_instantiation (interface_id,end_epoch,start_epoch,capacity_mbps,mtu_bytes) VALUES (?,-1,unix_timestamp(now()),10000,9000)";
    my $insert_interface_instantiaiton_sth   = $self->_prepare_query($insert_interface_instantiaiton_query) or return;

    my $networks = $db_dump->{'network'};

    foreach my $network_name (keys %$networks){
	$network_insert_sth->execute($network_name,
				     $networks->{$network_name}->{'longitude'},
				     $networks->{$network_name}->{'latitude'}) or return;

	my $nodes = $networks->{$network_name}->{'node'};

	foreach my $node_name (keys %$nodes){
	    my $node = $nodes->{$node_name};

	    $insert_node_sth->execute($node_name,
				      $node->{'longitude'},
				      $node->{'latitude'},
				      $network_name
		                     );

	    $insert_node_instantiaiton_sth->execute($node_name,
						    $node->{'managemnt_addr'},
						    $node->{'dpid'},
						    $node->{'admin_state'} || "planned"
		                                   );

	    my $interfaces = $node->{'interface'};

	    foreach my $interface_name (keys %$interfaces){
		my $interface = $interfaces->{$interface_name};

		my $interface_db_id;

		$insert_interface_sth->execute($interface_name,
					       $interface->{'description'},
					       $node_name,
					       $interface->{'operational_state'} || "unknown"
		                              );

		$select_interface_sth->execute($interface_name,
					       $node_name
		                              );

		if(my $row=$select_interface_sth->fetchrow_hashref()){
		    $interface_db_id = $row->{'interface_id'};
		}

		return undef unless $interface_db_id;

		$insert_interface_instantiaiton_sth->execute($interface_db_id) or return;

	    }
	}

	#now links
	my $links = $networks->{$network_name}->{'link'};

	my $insert_new_link_query = "insert into link (name) VALUES (?)";
	my $insert_new_link_sth   = $self->_prepare_query($insert_new_link_query) or return;

	my $insert_new_link_instantiation     = "insert into link_instantiation (link_id,end_epoch,start_epoch,interface_a_id,interface_z_id,link_state) VALUES ( (select link_id from link where name=?),-1,unix_timestamp(now()),?,?,?)";
	my $insert_new_link_instantiation_sth = $self->_prepare_query($insert_new_link_instantiation) or return;

	foreach my $link_name (keys %$links){
	    my $link = $links->{$link_name};

	    $insert_new_link_sth->execute($link_name) or return;

	    my ($node_a_name,$node_a_interface_name) = split(/:/,$link->{'interface_a'}) ;
	    my ($node_b_name,$node_b_interface_name) = split(/:/,$link->{'interface_b'}) ;

	    my $interface_a_db_id = $self->get_interface_id_by_names(node      => $node_a_name,
								     interface => $node_a_interface_name
		);

	    my $interface_b_db_id = $self->get_interface_id_by_names(node      => $node_b_name,
								     interface => $node_b_interface_name
		);

	    $insert_new_link_instantiation_sth->execute($link_name,
							$interface_a_db_id,
							$interface_b_db_id,
							$link->{'link_state'} || "planned"
		                                       );
	}
    }

    #now circuits!
    my $insert_circuit_query = "insert into circuit (name,description) VALUES (?,?)";
    my $insert_circuit_sth   = $self->_prepare_query($insert_circuit_query) or return;

    my $insert_circuit_instantiation_query = "insert into circuit_instantiation (circuit_id,end_epoch,start_epoch,reserved_bandwidth_mbps,circuit_state,modified_by_user_id) VALUES ((select circuit_id from circuit where name=?),-1,unix_timestamp(now()),?,?,?)";
    my $insert_circuit_instantiation_sth   = $self->_prepare_query($insert_circuit_instantiation_query) or return;

    my $insert_path_query = "insert into path (path_type,circuit_id) VALUES (?,(select circuit_id from circuit where name=?))";
    my $insert_path_sth   = $self->_prepare_query($insert_path_query) or return;

    my $insert_path_inst_query = "insert into path_instantiation ( path_id,end_epoch,start_epoch,internal_vlan_id,path_state) VALUES ((select path_id from path where path_type=? and circuit_id=(select circuit_id from circuit where name=?)),-1,unix_timestamp(now()),?,?)";
    my $insert_path_inst_sth   = $self->_prepare_query( $insert_path_inst_query) or return;

    my $insert_link_path_membership_query = "insert into link_path_membership (path_id,link_id,end_epoch,start_epoch) VALUES ((select path_id from path where path_type=? and circuit_id=(select circuit_id from circuit where name=?)),?,-1, unix_timestamp(now()) )";
    my $insert_link_path_membership_sth   = $self->_prepare_query($insert_link_path_membership_query) or return;

    my $insert_circuit_edge_interface_membership_query = "insert into circuit_edge_interface_membership (circuit_id,interface_id,extern_vlan_id,end_epoch,start_epoch) VALUES ((select circuit_id from circuit where name=?),?,?,-1,unix_timestamp(now()))";
    my $insert_circuit_edge_interface_membership_sth   = $self->_prepare_query($insert_circuit_edge_interface_membership_query) or return;

    my $circuits = $db_dump->{'circuit'};
    my $i = 100;
    foreach my $circuit_name (keys %$circuits){

	my $circuit = $circuits->{$circuit_name};

	$insert_circuit_sth->execute($circuit_name,
				     $circuit->{'description'}) or return;

	$insert_circuit_instantiation_sth->execute($circuit_name,
						   $circuit->{'reserved_bw'},
						   'active',
						   1) or return;

	#now paths
	my $paths = $circuit->{'path'};

	foreach my $path (@$paths){

	    my $path_type     = $path->{'type'};
	    my $internal_vlan = $path->{'vlan'} || $i++;

	    $insert_path_sth->execute($path_type,
				      $circuit_name) or return;

	    $insert_path_inst_sth->execute($path_type,
					   $circuit_name,
					   $internal_vlan,
					   'active');


	    my $path_links = $path->{'member_link'};
	    foreach my $link_name (@$path_links){
		my $link_db_id = $self->get_link_id_by_name(link => $link_name);

		$insert_link_path_membership_sth->execute($path_type,
							  $circuit_name,
							  $link_db_id) or return;
	    }
	}

	#now terminations
	my $end_points=$circuit->{'endpoint'};

	foreach my $end_point (@{$circuit->{'endpoint'}}){

	    my $node_name = $end_point->{'node'};

	    my $interface_name = $end_point->{'interface'};

	    my $interface_db_id = $self->get_interface_id_by_names(node      => $node_name,
								   interface => $interface_name);

	    $insert_circuit_edge_interface_membership_sth->execute($circuit_name,
								   $interface_db_id,
								   $end_point->{'vlan'}
		                                                  ) or return;
	}

    }

    return 1;
}

=head2 get_remote_links

=cut

sub get_remote_links {
    my $self = shift;
    my %args = @_;

    my $query = "select link.link_id, link.name as link_name, link.remote_urn, link.vlan_tag_range, node.name as node_name, interface.name as int_name, interface.interface_id as int_id from link " .
	" join link_instantiation on link.link_id = link_instantiation.link_id " .
	" join interface on interface.interface_id in (link_instantiation.interface_a_id, link_instantiation.interface_z_id) " .
	" join interface_instantiation on interface.interface_id = interface_instantiation.interface_id " .
	"  and interface_instantiation.end_epoch = -1 and interface_instantiation.admin_state != 'down' " .
	" join node on node.node_id = interface.node_id " .
	" join network on network.network_id = node.network_id and network.is_local = 1" .
	" where link.remote_urn is not null ".
    " order by link.remote_urn ";

    my $rows = $self->_execute_query($query, []);

    if (! defined $rows){
	$self->_set_error("Internal error getting remote links.");
	return;
    }

    my @results;

    foreach my $row (@$rows){
        push (@results, {
            "link_id"        => $row->{'link_id'},
            "link_name"      => $row->{'link_name'},
            "node"           => $row->{'node_name'},
            "interface"      => $row->{'int_name'},
            "interface_id"   => $row->{'int_id'},
            "urn"            => $row->{'remote_urn'},
            "vlan_tag_range" => $row->{'vlan_tag_range'}
        });
    }

    return \@results;
}

=head2 add_remote_link

=cut

sub add_remote_link {
    my $self = shift;
    my %args = @_;

    my $urn                 = $args{'urn'};
    my $name                = $args{'name'};
    my $vlan_tag_range      = $args{'vlan_tag_range'};
    my $local_interface_id  = $args{'local_interface_id'};

    if ($urn !~ /domain=(.+):node=(.+):port=(.+):link=(.+)$/){
	$self->_set_error("Unable to deconstruct URN to determine elements. Expected format was urn:ogf:network:domain=foo:node=bar:port=biz:link=bam");
	return;
    }

    $urn =~ /domain=(.+):node=(.+):port=(.+):link=(.+)$/;

    my $remote_domain = $1;
    my $remote_node   = $2;
    my $remote_port   = $3;
    my $remote_link   = $4;

    $self->_start_transaction();

    my $remote_network_id = $self->get_network_by_name(network => $remote_domain);

    if (! $remote_network_id){
	$remote_network_id = $self->add_network(name      => $remote_domain,
						longitude => 0,
						latitude  => 0,
						is_local  => 0
	                                       );
    }

    if (! defined $remote_network_id){
	$self->_set_error("Unable to determine network id: " . $self->get_error());
	$self->_rollback();
    return;
    }

    # remote are stored internally as $domain-$node
    $remote_node = $remote_domain . "-" . $remote_node;

    my $node_info = $self->get_node_by_name(name              => $remote_node,
					    no_instantiation  => 1
	                                    );


    my $remote_node_id;

    # couldn't find this remote node, let's add it
    if (! $node_info){
	$remote_node_id = $self->add_node(name              => $remote_node,
					  operational_state => "up",
					  network_id        => $remote_network_id
	                                  );
    }
    else {
	$remote_node_id = $node_info->{'node_id'};
    }

    if (! defined $remote_node_id){
	$self->_set_error("Unable to determine node id: " . $self->get_error());
	$self->_rollback();
    return;
    }

    my $remote_interface_id = $self->add_or_update_interface(node_id          => $remote_node_id,
							     name             => $remote_port,
							     no_instantiation => 1
	                                                    );

    if (! defined $remote_interface_id){
	$self->_set_error("Unable to determine interface id: " . $self->get_error());
	$self->_rollback();
    return;
    }

    my $link_id = $self->add_link(
        name           => $name,
		remote_urn     => $urn,
        vlan_tag_range => $vlan_tag_range
    );

    if (! defined $link_id){
	$self->_set_error("Unable to create link $name: " . $self->get_error());
	$self->_rollback();
    return;
    }

    my $result = $self->create_link_instantiation(link_id         => $link_id,
						  state           => 'active',
						  interface_a_id  => $local_interface_id,
						  interface_z_id  => $remote_interface_id
	                                          );

    if (! defined $result){
	$self->_set_error("Unable to create link instantiation: " . $self->get_error());
	$self->_rollback();
    return;
    }

    $self->_commit();

    return 1;
}

=head2 edit_remote_link

=cut

sub edit_remote_link {
    my $self = shift;
    my %args = @_;

    my $urn                 = $args{'urn'};
    my $name                = $args{'name'};
    my $vlan_tag_range      = $args{'vlan_tag_range'};
    my $link_id             = $args{'link_id'}; 

    if ($urn !~ /domain=(.+):node=(.+):port=(.+):link=(.+)$/){
	$self->_set_error("Unable to deconstruct URN to determine elements. Expected format was urn:ogf:network:domain=foo:node=bar:port=biz:link=bam");
	return;
    }

    $urn =~ /domain=(.+):node=(.+):port=(.+):link=(.+)$/;

    my $remote_domain = $1;
    my $remote_node   = $2;
    my $remote_port   = $3;
    my $remote_link   = $4;

    $self->_start_transaction();

    my $remote_network_id = $self->get_network_by_name(network => $remote_domain);

    if (! $remote_network_id){
	$remote_network_id = $self->add_network(name      => $remote_domain,
						longitude => 0,
						latitude  => 0,
						is_local  => 0
	                                       );
    }

    if (! defined $remote_network_id){
	$self->_set_error("Unable to determine network id: " . $self->get_error());
	$self->_rollback();
    return;
    }

    # remote are stored internally as $domain-$node
    $remote_node = $remote_domain . "-" . $remote_node;

    my $node_info = $self->get_node_by_name(name              => $remote_node,
					    no_instantiation  => 1
	                                    );


    my $remote_node_id;

    # couldn't find this remote node, let's add it
    if (! $node_info){
	$remote_node_id = $self->add_node(name              => $remote_node,
					  operational_state => "up",
					  network_id        => $remote_network_id
	                                  );
    }
    else {
	$remote_node_id = $node_info->{'node_id'};
    }

    if (! defined $remote_node_id){
	$self->_set_error("Unable to determine node id: " . $self->get_error());
	$self->_rollback();
    return;
    }

    my $remote_interface_id = $self->add_or_update_interface(node_id          => $remote_node_id,
							     name             => $remote_port,
							     no_instantiation => 1
	                                                    );

    if (! defined $remote_interface_id){
	$self->_set_error("Unable to determine interface id: " . $self->get_error());
	$self->_rollback();
    return;
    }

    my $update_link = $self->edit_link(
            link_id => $link_id,
            name => $name,
            remote_urn => $urn,
            vlan_tag_range => $vlan_tag_range,
            status          => 'up'
    );

    if (!defined($update_link)) {
        $self->_set_error("Unable to update link.");
        $self->_rollback();
        return;
    }

    $self->_commit();
    return 1;
}

=head2 get_network_by_name

Returns the internal identifier of the network with name $network or undef if no such network exists.

=over

=item network

The name of the network to get the identifier of.

=back

=cut

sub get_network_by_name{
    my $self = shift;
    my %args = @_;

    my $dbh = $self->{'dbh'};

    my $network_name = $args{'network'};

    my $select_network = "select network_id from network where name = ?";
    my $select_network_sth = $self->_prepare_query($select_network) or return;

    $select_network_sth->execute($network_name) or return;

    if(my $row = $select_network_sth->fetchrow_hashref()){
	return $row->{'network_id'};
    }
    $self->_set_error("Unable to find network named " . $network_name);
    return;

}

=head2 add_network

=cut

sub add_network {
    my $self = shift;
    my %args = @_;

    my $name       = $args{'name'};
    my $longitude  = $args{'longitude'};
    my $latitude   = $args{'latitude'};
    my $is_local   = $args{'is_local'};

    my $id = $self->_execute_query("insert into network (name, longitude, latitude, is_local) values (?, ?, ?, ?)",
				   [$name, $longitude, $latitude, $is_local]);

    if (! defined $id){
	$self->_set_error("Internal error adding new network.");
	return;
    }

    return $id;
}

=head2 get_network_by_id

=cut

sub get_network_by_id{
    my $self = shift;
    my %args = @_;


    my $dbh = $self->{'dbh'};
    my $network_id = $args{'network'};

    my $str = "select * from network where network_id = ?";
    my $sth = $self->_prepare_query($str) or return;
    $sth->execute($network_id) or return;

    if(my $row = $sth->fetchrow_hashref()){
	return $row;
    }

    $self->_set_error("unable to find network id " . $network_id . "\n");
    return;
}

=head2 get_nodes_by_admin_state

Returns an array of hashes containing information about the nodes that are currently in state $admin_state.

=over

=item admin_state

The state this node should be in. Valid choices are 'planned', 'available', 'active', 'maintenance', and 'decom'.

=back

=cut

sub get_nodes_by_admin_state{
    my $self = shift;
    my %args = @_;

    my $dbh = $self->{'dbh'};

    my $admin_state       = $args{'admin_state'};

    my $select_nodes = "select node.vlan_tag_range,node.node_id,node.name,max_flows,tx_delay_ms,inet_ntoa(node_instantiation.management_addr_ipv4) as management_addr_ipv4 from node,node_instantiation where node.node_id = node_instantiation.node_id and node_instantiation.admin_state = ? and end_epoch = -1";

    my $select_nodes_sth = $self->_prepare_query($select_nodes);
    $select_nodes_sth->execute($admin_state);

    my @results;

    while(my $row = $select_nodes_sth->fetchrow_hashref()){
	push(@results,$row);
    }

    return \@results;
}

=head2 get_interfaces_by_node_and_state

Returns an array of hashes containing information about the interfaces on node with internal identifier $node_id that are presently in state $state.

=over

=item node_id

The internal MySQL primary key int identifier for this node.

=item state

The state this interface is currently in. Valid choices are 'up', 'down', and 'unknown'.

=back

=cut

sub get_interfaces_by_node_and_state{
    my $self = shift;
    my %args = @_;

    my $node_id = $args{'node_id'};
    my $state = $args{'state'};

    my $select_interfaces = "select interface.interface_id, interface.port_number, interface.name, interface.description, interface.role, interface_instantiation.capacity_mbps, interface_instantiation.mtu_bytes from interface,interface_instantiation where interface.interface_id = interface_instantiation.interface_id and interface_instantiation.end_epoch = -1 and interface.node_id = ? and interface_instantiation.admin_state = ?";

    my $select_interfaces_sth = $self->_prepare_query($select_interfaces);
    $select_interfaces_sth->execute($node_id, $state);
    my @results;

    while(my $row = $select_interfaces_sth->fetchrow_hashref()){
	push(@results,$row);
    }

    if($#results > -1){
	return \@results;
    }else{
	$self->_set_error("Unable to find interface for node $node_id that are in state $state");
	return;
    }
}


=head2 get_link_by_interface_id

Returns an array of names for the links that terminate on the interface identified by $interface_id.

=over

=item interface_id

The internal MySQL primary key int identifier for this interface.

=back

=cut

sub get_link_by_interface_id{
    my $self = shift;
    my %args = @_;

    my $interface_id = $args{'interface_id'};

    if(!defined($interface_id)){
        $self->_set_error("No interface_id specified to get_link_by_interface_id");
        return;
    }
    my $show_decom = 1;
    if(defined($args{'show_decom'}) && $args{'show_decom'} == 0){
        $show_decom = 0;
    }
    my $force_active = 0;
    if(defined($args{'force_active'}) && $args{'force_active'} == 1){
        $force_active = 1;
    }


    my $select_link_by_interface = "select link.name as link_name, ".
    " link.status, ". 
    " link.link_id, ".
    " link.remote_urn, ".
    " link.vlan_tag_range, ".
    " link_instantiation.interface_a_id, ".
    " link_instantiation.interface_z_id, ".
    " link_instantiation.link_state as state ".
    " from link,link_instantiation ".
    " where link.link_id = link_instantiation.link_id ".
    " and link_instantiation.end_epoch = -1 ".
    " and (link_instantiation.interface_a_id = ? or link_instantiation.interface_z_id = ?)";
    
    if($force_active){
	    $select_link_by_interface .= " and link_instantiation.link_state = 'active'"
    }
    if(!$show_decom){
	    $select_link_by_interface .= " and link_instantiation.link_state != 'decom'"
    }


    my $select_link_sth = $self->_prepare_query($select_link_by_interface);

    $select_link_sth->execute($interface_id,$interface_id);
    my @results;
    while(my $row = $select_link_sth->fetchrow_hashref()){
	push(@results,$row);
    }

    if($#results >= 0){
	return \@results;
    }else{
	return;
    }

}

=head2 get_circuit_by_id

  given a circuit_id returns the details about the circuit

=cut

sub get_circuit_by_id{
    my $self = shift;
    my %args = @_;

    my $circuit_id = $args{'circuit_id'};
    if(!defined($circuit_id)){
	warn "No Circuit ID defined";
	return;
    }

    my $query = "select * from circuit,circuit_instantiation where circuit.circuit_id = circuit_instantiation.circuit_id and circuit_instantiation.end_epoch = -1 and circuit.circuit_id = ?";
    return $self->_execute_query($query,[$circuit_id]);
}

=head2 get_circuit_by_external_identifier

Returns circuit details for a circuit with the given external identifier;

=over

=item external_identifier

The external identifier of this circuit.

=back

=cut

sub get_circuit_by_external_identifier {
    my $self = shift;
    my %args = @_;

    my $id = $args{'external_identifier'};

    my $query = "select * from circuit join circuit_instantiation on circuit.circuit_id = circuit_instantiation.circuit_id ";
    $query   .= " and circuit_instantiation.end_epoch = -1 ";
    $query   .= " where circuit.external_identifier = ?";

    my $results = $self->_execute_query($query, [$id]);

    if (! defined $results){
	$self->_set_error("Internal error getting circuit by external identifier.");
	return;
    }

    return @$results[0];
}


=head2 get_circuits_by_interface_id

Returns an array of hashes containing circuit information of all active circuits that have the interface identified by $interface_id as an endpoint.

=over

=item interface_id

The internal MySQL primary key int identifier for this interface.

=back

=cut

sub get_circuits_by_interface_id {
    my $self = shift;
    my %args = @_;

    my $interface_id = $args{'interface_id'};

    my $query = "SELECT ".
                "  circuit.circuit_id, ".
                "  circuit.name, ".
                "  circuit.description ".
                "FROM circuit_edge_interface_membership AS ce ".
                "JOIN circuit ON circuit.circuit_id = ce.circuit_id ".
                "JOIN circuit_instantiation AS ci ON circuit.circuit_id = ci.circuit_id ".
                "WHERE ci.circuit_state = 'active' ".
                "AND ci.end_epoch = -1 ".
                "AND ce.end_epoch = -1 ".
                "AND ce.interface_id = ?";

    my $circuits = $self->_execute_query($query, [$interface_id]) || return;

	return $circuits;
}

=head2 schedule_path_change

=cut

sub schedule_path_change{
    my $self = shift;
    my %params = @_;

    if(!defined($params{'circuit_id'}) || !defined($params{'when'}) || !defined($params{'path'}) || !defined($params{'user_id'})){
	return;
    }

    my $tmp;
    $tmp->{'path'}         = $params{'path'};
    $tmp->{'version'}      = "1.0";
    $tmp->{'action'}       = "change_path";
    $tmp->{'reason'}       = $params{'reason'};
    my $circuit_layout = XMLout($tmp);


    my $query = "insert into scheduled_action (user_id, workgroup_id, circuit_id, registration_epoch, activation_epoch, circuit_layout, completion_epoch) VALUES (?,?,?,UNIX_TIMESTAMP(NOW()),?,?,-1)";
    my $res = $self->_execute_query($query, [$params{'user_id'},$params{'workgroup_id'},$params{'circuit_id'},$params{'when'},$circuit_layout]);

    return $res;
}


=head2 provision_circuit

Creates a new circuit record and its path information.

I<This does not actually create a circuit on the network - that is the forwarding control's job. This is just the database records.>

=over

=item description

The description of this new circuit.

=item bandwidth

The number of Mbps that this circuit should have reserved.

=item provision_time

When to provision this circuit in epoch seconds.

=item remove_time

When to remove this circuit in epoch seconds.

=item links

An array of names of links that this circuit should use as a primary path.

=item backup_links

An array of names of links that this circuit should use as a backup path.

=item nodes

An array of names of endpoint nodes that this circuit should use. The order of this should match interfaces and tags such that a given nodes[i]-interfaces[i]-tags[i] combination is accurate.

=item interfaces

An array of names of interfaces that this circuit should use. The order of this should match nodes and tags such that a given nodes[i]-interfaces[i]-tags[i] combination is accurate.

=item tags

An array of vlan tags that this circuit should use. The order of this should match nodes and interfaces such that a given nodes[i]-interfaces[i]-tags[i] combination is accurate.

=back

=cut

sub provision_circuit {
    my $self = shift;
    my %args = @_;

    my $description      = $args{'description'};
    my $bandwidth        = $args{'bandwidth'};
    my $provision_time   = $args{'provision_time'};
    my $remove_time      = $args{'remove_time'};
    my $links            = $args{'links'};
    my $backup_links     = $args{'backup_links'};
    my $nodes            = $args{'nodes'};
    my $interfaces       = $args{'interfaces'};
    my $tags             = $args{'tags'};
    my $mac_addresses    = $args{'mac_addresses'};
    my $endpoint_mac_address_nums = $args{'endpoint_mac_address_nums'};
    my $user_name        = $args{'user_name'};
    my $workgroup_id     = $args{'workgroup_id'};
    my $external_id      = $args{'external_id'};
    my $remote_endpoints = $args{'remote_endpoints'} || [];
    my $remote_tags      = $args{'remote_tags'} || [];
    my $restore_to_primary = $args{'restore_to_primary'} || 0;
    my $static_mac       = $args{'static_mac'} || 0;
    my $state            = $args{'state'} || 'active';
    my $remote_url       = $args{'remote_url'};
    my $remote_requester = $args{'remote_requester'};


    if($#{$interfaces} < 1){
        $self->_set_error("Need at least 2 endpoints");
        return;
    }

    my $user_id        = $self->get_user_id_by_auth_name(auth_name => $user_name);

    if(!$user_id) {
	$self->_set_error("Unknown user '$user_name'");
	return;
    }

    my $workgroup_details = $self->get_workgroup_details(workgroup_id => $workgroup_id);

    if (! defined $workgroup_details){
	$self->_set_error("Unknown workgroup.");
	return;
    }

    my $is_admin = $self->get_user_admin_status( 'user_id' => $user_id)->[0]{'is_admin'};
    if (!$is_admin && !$self->is_user_in_workgroup(user_id => $user_id, workgroup_id => $workgroup_id)){
        $self->_set_error("Permission denied: user is not a part of the requested workgroup.");
        return;
    }

    # make sure this workgroup hasn't gone over their circuit limit
    my $within_limit = $self->is_within_circuit_limit( workgroup_id => $workgroup_id );
    if(!$within_limit){
        $self->_set_error("Permission denied: workgroup is already at circuit limit.");
        return;
    }

    # makes sure this workgroup hasn't gone over their endpoint limit
    my $endpoint_num = @$nodes;
    $within_limit = $self->is_within_circuit_endpoint_limit( 
        workgroup_id => $workgroup_id,
        endpoint_num => $endpoint_num
    );
    if(!$within_limit){
        $self->_set_error("Permission denied: $endpoint_num endpoints exceeds the limit of endpoints per circuit placed on this workgroup.");
        return;
    }
    

    my $query;

    $self->_start_transaction();

    my $uuid = $self->_get_uuid();

    if (! defined $uuid){
        return;
    }

    my $name = $workgroup_details->{'name'} . "-" . $uuid;

    if(!defined($state)){
	if($provision_time > time()){
	    $state = "scheduled";
	}else{
	    $state = "deploying";
	}
    }

    # create circuit record
    my $circuit_id = $self->_execute_query("insert into circuit (name, description, workgroup_id, external_identifier, restore_to_primary, static_mac,circuit_state, remote_url, remote_requester) values (?, ?, ?, ?, ?, ?,?,?,?)",
					   [$name, $description, $workgroup_id, $external_id, $restore_to_primary, $static_mac,$state, $remote_url, $remote_requester]);

    if (! defined $circuit_id ){
        $self->_set_error("Unable to create circuit record.");
        $self->_rollback();
        return;
    }



    #instantiate circuit
    $query = "insert into circuit_instantiation (circuit_id, reserved_bandwidth_mbps, circuit_state, modified_by_user_id, end_epoch, start_epoch) values (?, ?, ?, ?, -1, unix_timestamp(now()))";
    $self->_execute_query($query, [$circuit_id, $bandwidth, $state, $user_id]);

    if($state eq 'scheduled' || $state eq 'reserved'){

        $args{'user_id'}    = $user_id;
        $args{'circuit_id'} = $circuit_id;

        my $success = $self->_add_event(\%args);

        if (! defined $success){
            $self->_rollback();
            return;
        }

#        $self->_commit();

#        return {"success" => 1, "circuit_id" => $circuit_id};
    }
    #handle when an event isn't scheduled to be built, but does have a scheduled removal date.
    if($remove_time != -1){

        $args{'user_id'}    = $user_id;
        $args{'circuit_id'} = $circuit_id;
        my $result = $self->_add_remove_event(\%args);

        if (! defined $result) {
            $self->_rollback();
            return;
        }
    }

    #not a scheduled event ie.. do it now

    # first set up endpoints
    for (my $i = 0; $i < @$nodes; $i++){

	my $node      = @$nodes[$i];
	my $interface = @$interfaces[$i];
	my $vlan      = @$tags[$i];
        my $endpoint_mac_address_num = @$endpoint_mac_address_nums[$i];
        my $circuit_edge_id;
        
	$query = "select interface_id from interface " .
	    " join node on node.node_id = interface.node_id " .
	    " where node.name = ? and interface.name = ? ";

	my $interface_id = $self->_execute_query($query, [$node, $interface])->[0]->{'interface_id'};

	if (! $interface_id ){
	    $self->_set_error("Unable to find interface '$interface' on node '$node'");
            $self->_rollback();
	    return;
	}

	if (! $self->_validate_endpoint(interface_id => $interface_id, workgroup_id => $workgroup_id, vlan => $vlan)){
	    $self->_set_error("Interface \"$interface\" on endpoint \"$node\" with VLAN tag \"$vlan\" is not allowed for this workgroup.");
            $self->_rollback();
	    return;
	}

	# need to check to see if this external vlan is open on this interface first
	if (! $self->is_external_vlan_available_on_interface(vlan => $vlan, interface_id => $interface_id) ){
	    $self->_set_error("Vlan '$vlan' is currently in use by another circuit on interface '$interface' on endpoint '$node'");
            $self->_rollback();
	    return;
	}

	$query = "insert into circuit_edge_interface_membership (interface_id, circuit_id, extern_vlan_id, end_epoch, start_epoch) values (?, ?, ?, -1, unix_timestamp(NOW()))";

	$circuit_edge_id = $self->_execute_query($query, [$interface_id, $circuit_id, $vlan]);
	if (! defined($circuit_edge_id) ){
            #if (! defined $self->_execute_query($query, [$interface_id, $circuit_id, $vlan])){
	    $self->_set_error("Unable to create circuit edge to interface '$interface' on endpoint '$node'");
            $self->_rollback();
	    return;
	}
        
        # now add any static mac addresses if the static mac address flag was sent
        if($static_mac){
            
            # create an array of all the mac addresses for this endpoint
            my @endpoint_mac_addresses;
            for (my $j = 0; $j < $endpoint_mac_address_num; $j++){
                my $mac_address = shift(@$mac_addresses);
                push(@endpoint_mac_addresses, $mac_address);
            }
            
            # check that the mac_addresses fall within the limits
            my $result = $self->is_within_mac_limit(
                mac_address  => \@endpoint_mac_addresses,
                interface    => $interface,
                node         => $node,
                workgroup_id => $workgroup_id
                );
            if(!$result->{'verified'}){
                $self->_set_error($result->{'explanation'});
                $self->_rollback();
                return;
            }
            
            # now add the mac addresses to the endpoint
            $query = "insert into circuit_edge_mac_address values (?,?)";
            foreach my $mac_address (@endpoint_mac_addresses){
                if( ! mac_validate( $mac_address ) ){
                    $self->_set_error("$mac_address is not a valid mac address.");
                    $self->_rollback();
                    return;
                }
                $mac_address = mac_hex2num( $mac_address );
                if( ! defined $self->_execute_query($query, [$circuit_edge_id, $mac_address]) ){
                    $self->_set_error("Unable to create mac address edge to interface '$interface' on endpoint '$node'");
                    $self->_rollback();
                    return;
                }
            }
            
        }
        
    }
    
    # set up any remote_endpoints if we have them
    for (my $i = 0; $i < @$remote_endpoints; $i++){

        my $urn = @$remote_endpoints[$i];
        my $tag = @$remote_tags[$i];

        $query = "select interface.interface_id from interface join urn on interface.interface_id=urn.interface_id where urn.urn = ?";
        my $interface_id = $self->_execute_query($query, [$urn])->[0]->{'interface_id'};

        if (! $interface_id){
            $self->_set_error("Unable to find interface associated with URN: $urn");
            $self->_rollback();
            return;
        }


        $query = "insert into circuit_edge_interface_membership (interface_id, circuit_id, extern_vlan_id, end_epoch, start_epoch) values (?, ?, ?, -1, unix_timestamp(NOW()))";

        if (! defined $self->_execute_query($query, [$interface_id, $circuit_id, $tag])){
            $self->_set_error("Unable to create circuit edge to interface \"$urn\" with tag $tag.");
            $self->_rollback();
            return;
        }

    }


    # now set up links
    my $link_lookup = {
        'primary' => $links,
        'backup'  => $backup_links
    };

    foreach my $path_type (qw(primary backup)){

        my $relevant_links = $link_lookup->{$path_type};

        next if(!defined(@$relevant_links) || !defined($relevant_links->[0]));

        # create the primary path object
        $query = "insert into path (path_type, circuit_id, path_state) values (?, ?, ?)";

        my $path_state = "deploying";

        if ($path_type eq "backup"){
            $path_state = "available";
        }

        my $path_id = $self->_execute_query($query, [$path_type, $circuit_id,$path_state]);

        if (! $path_id){
            $self->_set_error("Error while creating path record.");
                $self->_rollback();
            return;
        }


        # instantiate path object
        $query = "insert into path_instantiation (path_id, end_epoch, start_epoch, path_state) values (?, -1, unix_timestamp(NOW()), ?)";

        

        my $path_instantiation_id = $self->_execute_query($query, [$path_id, $path_state]);

        if (! defined $path_instantiation_id ){
            $self->_set_error("Error while instantiating path record.");
            $self->_rollback();
            return;
        }
        
        my %seen_endpoints;
        # figure out all the nodes along this path so we can assign them an internal tag
        foreach my $link (@$relevant_links){
            my $info      = $self->get_link_by_name(name => $link);

            if (! defined $info){
                $self->_set_error("Unable to determine link with name \"$link\"");
                $self->_rollback();
                return;
            }
            my $link_id = $info->{'link_id'};
            my $endpoints = $self->get_link_endpoints(link_id => $link_id);

            #build set of endpoints
            #note: this is not safe being parallelized with this schema.
            my $interface_a_vlan_id;
            my $interface_z_vlan_id;

            foreach my $endpoint (@$endpoints){
                my $node_id = $endpoint->{'node_id'};
                my $interface_id = $endpoint->{'interface_id'};
                my $interface_a_id = $endpoint->{'interface_a_id'};
                my $interface_z_id = $endpoint->{'interface_z_id'};

                # make sure we don't double assign
                next if ($seen_endpoints{$interface_id});
                $seen_endpoints{$interface_id} = 1;
                        
                # figure out what internal ID we can use for this
                my $internal_vlan = $self->_get_available_internal_vlan_id(node_id => $node_id,interface_id =>$interface_id);

                if (! defined $internal_vlan){
                $self->_set_error("Internal error finding available internal id for node $endpoint->{'node_name'}.");
                $self->_rollback();
                return;
                }
                if ($interface_a_id == $interface_id){
                    $interface_a_vlan_id = $internal_vlan;
                }
                elsif ($interface_z_id == $interface_id){
                    $interface_z_vlan_id = $internal_vlan;
                }
            }
            $query = "insert into link_path_membership (link_id, path_id, end_epoch, start_epoch,interface_a_vlan_id,interface_z_vlan_id) values (?, ?, -1, unix_timestamp(NOW()),?,?)";
            if (!defined ($self->_execute_query($query, [$link_id, $path_id, $interface_a_vlan_id, $interface_z_vlan_id])) ){
                $self->_set_error("Error adding link '$link' into path.");
                $self->_rollback();
                return;
            }
        }

    }
    # now check to verify that the topology makes sense
    my ($success, $error) = $self->{'topo'}->validate_paths(circuit_id => $circuit_id);

    if (! $success){
        $self->_set_error($error);
        $self->_rollback();
        return;
    }

    $self->_commit();

    my $to_return = {"success" => 1, "circuit_id" => $circuit_id};

    return $to_return;
}

=head2 remove_circuit

Turns down all active components of a circuit in the database. Note that this does not change the network, just updates the database records.

=over

=item circuit_id

The internal MySQL primary key int identifier for this circuit.

=item remove_time

When to remove this circuit in epoch seconds.

=back

=cut

sub remove_circuit {
    my $self = shift;
    my %args = @_;

    my $circuit_id  = $args{'circuit_id'};
    my $remove_time = $args{'remove_time'};
    my $user_name   = $args{'username'};

    my $user_id = $self->get_user_id_by_auth_name(auth_name => $user_name);
    if (!$user_id){
	$self->_set_error("Unknown user \"$user_name\"");
	return;
    }

    if ($remove_time > time()){
	$args{'user_id'} = $user_id;

	return $self->_add_remove_event(\%args);
    }

    $self->_start_transaction();
    my $update_result = $self->update_circuit_state(
        circuit_id          => $circuit_id,
        old_state           => 'active',
        new_state           => 'decom',
        modified_by_user_id => $user_id,
        no_transact         => 1
	);
    if (!defined $update_result) {
        $self->_rollback();
        return;
    }

    my $results = $self->_execute_query("update path_instantiation " .
					" join path on path.path_id = path_instantiation.path_id " .
					"set end_epoch = unix_timestamp(NOW()) " .
					" where end_epoch = -1 and path.circuit_id = ?",
					[$circuit_id]
	                                );
    if (!defined $results){
	$self->_set_error("Unable to decom path instantiations.");
	$self->_rollback();
        return;
    }

    $results = $self->_execute_query("update link_path_membership " .
				     " join path on path.path_id = link_path_membership.path_id " .
				     "set end_epoch = unix_timestamp(NOW()) " .
				     " where end_epoch = -1 and path.circuit_id = ?",
				     [$circuit_id]
	                            );
    if (!defined $results){
	$self->_set_error("Unable to decom link membership.");
	$self->_rollback();
        return;
    }

    $results = $self->_execute_query("update circuit_edge_interface_membership " .
				     "set end_epoch = unix_timestamp(NOW()) " .
				     " where end_epoch = -1 and circuit_id = ?",
				     [$circuit_id]
	                            );
    if (!defined $results){
	$self->_set_error("Unable to decom edge membership.");
	$self->_rollback();
        return;
    }
    $self->_commit();

    return {success => 1, circuit_id => $circuit_id};
}


=head2 _add_event

=cut

sub _add_event{
    my $self = shift;
    my $params = shift;

    my $tmp;
    $tmp->{'name'}         = $params->{'name'};
    $tmp->{'bandwidth'}    = $params->{'bandwidth'};
    $tmp->{'links'}        = $params->{'links'};
    $tmp->{'backup_links'} = $params->{'backup_links'};
    $tmp->{'nodes'}        = $params->{'nodes'};
    $tmp->{'interfaces'}   = $params->{'interfaces'};
    $tmp->{'tags'}         = $params->{'tags'};
    $tmp->{'version'}      = "1.0";
    $tmp->{'action'}       = "provision";

    my $circuit_layout = XMLout($tmp);

    my $query = "insert into scheduled_action (user_id,workgroup_id,circuit_id,registration_epoch,activation_epoch,circuit_layout,completion_epoch) VALUES (?,?,?,?,?,?,-1)";

    my $result = $self->_execute_query($query,[$params->{'user_id'},
                                               $params->{'workgroup_id'},
					       $params->{'circuit_id'},
					       time(),
					       $params->{'provision_time'},
					       $circuit_layout
				               ]
	                               );

    if (! defined $result){
	$self->_set_error("Error creating scheduled addition.");

    return;
    }

    if($params->{'remove_time'} != -1){
        my $result = $self->_add_remove_event($params);

        if (! defined $result) {
            return;
        }
    }

    return 1;
}

=head2 _add_remove_event

=cut

sub _add_remove_event {
    my $self   = shift;
    my $params = shift;

    my $tmp;
    $tmp->{'name'}         = $params->{'name'};
    $tmp->{'version'}      = "1.0";
    $tmp->{'action'}       = "remove";

    my $circuit_layout = XMLout($tmp);

    my $query = "insert into scheduled_action (user_id,workgroup_id,circuit_id,registration_epoch,activation_epoch,circuit_layout,completion_epoch) VALUES (?,?,?,?,?,?,-1)";

    my $result = $self->_execute_query($query,[$params->{'user_id'},
					       $params->{'workgroup_id'},
					       $params->{'circuit_id'},
					       time(),
					       $params->{'remove_time'},
					       $circuit_layout
				               ]
	                               );

    if (! defined $result){
	$self->_set_error("Error creating scheduled removal.");
	return;
    }

    return 1;
}

=head2 _add_remove_event

=cut

sub _add_edit_event {
    my $self   = shift;
    my $params = shift;

    my $tmp;
    $tmp->{'version'}       = "1.0";
    $tmp->{'action'}        = "edit";
    $tmp->{'state'}         = $params->{'state'};
    $tmp->{'name'}          = $params->{'name'};
    $tmp->{'bandwidth'}     = $params->{'bandwidth'};
    $tmp->{'links'}         = $params->{'links'};
    $tmp->{'backup_links'}  = $params->{'backup_links'};
    $tmp->{'nodes'}         = $params->{'nodes'};
    $tmp->{'interfaces'}    = $params->{'interfaces'};
    $tmp->{'tags'}          = $params->{'tags'};
    $tmp->{'start_time'}    = $params->{'start_time'};
    $tmp->{'end_time'}      = $params->{'end_time'};


    my $circuit_layout = XMLout($tmp);

    my $query = "insert into scheduled_action (user_id,workgroup_id,circuit_id,registration_epoch,activation_epoch,circuit_layout,completion_epoch) VALUES (?,?,?,?,?,?,-1)";

    my $result = $self->_execute_query($query,[$params->{'user_id'},
                                               $params->{'workgroup_id'},
                                               $params->{'circuit_id'},
                                               time(),
                                               $params->{'edit_time'},
                                               $circuit_layout
                                               ]);

    if (! defined $result){
        $self->_set_error("Error creating scheduled removal.");
        return;
    }

    return 1;
}

=head2 update_action_complete_epoch

=cut

sub update_action_complete_epoch{
    my $self = shift;
    my %args = @_;

    if(!defined($args{'scheduled_action_id'})){
	return;
    }

    my $query = "update scheduled_action set completion_epoch = unix_timestamp(now()) where scheduled_action_id = ?";

    return $self->_execute_query($query,[$args{'scheduled_action_id'}]);
}


=head2 get_node_by_name

Returns a hash of node information for the node identified by $name

=over

=item name

The name of the node.

=back

=cut

sub get_node_by_name {
    my $self = shift;
    my %args = @_;
    my $name = $args{'name'};
    my $query;

    if ($args{'no_instantiation'}){
        $query = "select * from node where name = ?";
    }
       else {
	$query = "select * from node join node_instantiation on node.node_id = node_instantiation.node_id ";
	$query   .= " where node.name = ?";
     }
    my $results = $self->_execute_query($query, [$name]);
    if (! defined $results){
	$self->_set_error("Internal error fetching node information.");
	return;
    }
    return @$results[0];
}


=head2 get_node_by_id

=cut

sub get_node_by_id{
    my $self = shift;
    my %args = @_;

    my $str = "select node.*,node_instantiation.* from node, node_instantiation where node.node_id = node_instantiation.node_id and node.node_id = ?";
    my $sth = $self->_prepare_query($str);

    $sth->execute($args{'node_id'});
    return $sth->fetchrow_hashref();
}


=head2 get_node_by_dpid

Returns a hash of node information for the node identified by $dpid.

=over

=item dpid

The dpid of the node. This is whatever the switch uses to identify itself in Openflow.

=back

=cut

sub get_node_by_dpid{
    my $self = shift;
    my %args = @_;

    if(!defined($args{'dpid'})){
	$self->_set_error("DPID was not defined");
	return;
    }

    my $sth = $self->{'dbh'}->prepare("select * from node,node_instantiation where node.node_id = node_instantiation.node_id and node_instantiation.dpid = ?");
    $sth->execute($args{'dpid'});
    if(my $row = $sth->fetchrow_hashref()){
	return $row;
    }else{
	$self->_set_error("Unable to find node with DPID " . $args{'dpid'});
	return;
    }
}

=head2 get_node_by_interface_id

=cut

sub get_node_by_interface_id {
    my ($self, %args) = @_;
    my $interface_id = $args{'interface_id'};
    if(!defined($interface_id)){
        $self->_set_error("interface_id was not defined");
        return;
    }

    # node_id from interface
    my $query = "SELECT node_id ".
                "FROM interface ".
                "WHERE interface_id = ?";
    my $res = $self->_execute_query($query, [$interface_id]) || return;
    if (!defined @$res[0]) {
        $self->_set_error("No records for interface_id $interface_id were found.");
        return;
    }

    my $node_id = @$res[0]->{'node_id'};
    # if(!$node_id){
    #     $self->_set_error("No records for interface_id $interface_id");
    #     return;
    # }

    # get node record
    $query = "SELECT * ".
             "FROM node ".
             "JOIN node_instantiation on node.node_id = node_instantiation.node_id ".
             "WHERE node.node_id = ? ".
             "AND node_instantiation.end_epoch = -1";
    $res = $self->_execute_query($query, [$node_id]) || return;
    return @$res[0];
}

=head2 add_node

=cut

sub add_node{
    my $self = shift;
    my %args = @_;

    if(!defined($args{'name'})){
	$self->_set_error("Node Name was not specified");
	return;
    }
    my $send_barrier_bulk = 0;
    if($args{'send_barrier_bulk'}){
        $send_barrier_bulk = $args{'send_barrier_bulk'};
    }

    my $default_lat ="0.0";
    my $default_long="0.0";
    my $res = $self->_execute_query("insert into node (name,latitude, longitude, operational_state,network_id,send_barrier_bulk, vlan_tag_range) VALUES (?,?,?,?,?,?,?)",[$args{'name'},$default_lat,$default_long,$args{'operational_state'},$args{'network_id'},$send_barrier_bulk, $self->default_vlan_range()]);

    if(!defined($res)){
	$self->_set_error("Unable to create new node record");
	return;
    }

    return $res;
}


=head2 create_node_instance

=cut

sub create_node_instance{
    my $self = shift;
    my %args = @_;

    if(!defined($args{'node_id'})){
	$self->_set_error("No node specified");
    }

    my $node_inst = $self->_execute_query("select * from node_instantiation where node_id = ? and end_epoch = -1",[$args{'node_id'}]);

    if($#{$node_inst} >= 0){
	my $res = $self->_execute_query("update node_instantiation set end_epoch = ? where node_id = ? and end_epoch = -1",[time(),$args{'node_id'}]);
	if(!defined($res)){
	    $self->_set_error("Unable to decom the node instantiation");
	    return;
	}
     }

    my $res = $self->_execute_query("insert into node_instantiation (node_id,end_epoch,start_epoch,management_addr_ipv4,admin_state,dpid) VALUES (?,?,?,?,?,?)",[$args{'node_id'},-1,time(),$args{'ipv4_addr'},$args{'admin_state'},$args{'dpid'}]);

    if(!defined($res)){
	$self->_set_error("Unable to create new node instantiation");
	return;
    }


    return 1;

}

=head2 update_node_operational_state

=cut

sub update_node_operational_state{
    my $self = shift;
    my %args = @_;
    $self->_commit();
    my $res = $self->_execute_query("update node set operational_state = ? where node_id = ?",[$args{'state'},$args{'node_id'}]);
    if(!defined($res)){
	$self->_set_error("Unable to update operational state");
	return;
    }

    return 1;
}


=head2 add_or_update_interface

=cut

sub add_or_update_interface{
    my $self = shift;
    my %args = @_;

    if(!defined($args{'node_id'})){
	$self->_set_error("Node ID was not defined");
	return;
    }

    if(!defined($args{'name'})){
	$self->_set_error("Name was not defined");
	return;
    }

    if(!defined($args{'operational_state'})){
	$args{'operational_state'} = 'unknown';
    }

    if(!defined($args{'admin_state'})){
	$args{'admin_state'} = 'unknown';
    }

    if(!defined($args{'description'})){
	$args{'description'} = $args{'name'};
    }

    if(!defined($args{'capacity_mbps'})){
	$args{'capacity_mbps'} = 10000;
    }

    if(!defined($args{'mtu_bytes'})){
	$args{'mtu_bytes'} = 9000;
    }

    if(!defined($args{'vlan_tag_range'})){
	$args{'vlan_tag_range'} = MIN_VLAN_TAG . "-" . MAX_VLAN_TAG;
    }

    my $int_id;

    my $int = $self->_execute_query("select * from interface where interface.node_id = ? and interface.name = ?",[$args{'node_id'},$args{'name'}]);

    #see if this interface already exists
    if($#{$int} >= 0){
	#interface exists
	$int = @{$int}[0];

	$int_id = $int->{'interface_id'};

	#check to see if the existing port number matches the new one
	if($int->{'port_number'} != $args{'port_num'}){

	    my $port_num_changed = $self->_execute_query("select * from interface where interface.node_id = ? and interface.port_number = ? and interface.interface_id != ?",[$args{'node_id'},$args{'port_num'},$int->{'interface_id'}]);

	    if($#{$port_num_changed} >= 0){
		#this makes me a sad monkey :(
		$port_num_changed = @{$port_num_changed}[0];
		my $res = $self->_execute_query("update interface set port_number = NULL where interface_id = ?",[$port_num_changed->{'interface_id'}]);
		if(!defined($res)){
		    $self->_set_error("Unable to update a port to NULL");
		    return;
		}
	    }

	    my $res = $self->_execute_query("update interface set port_number = ? where interface_id = ?",[$args{'port_num'},$int->{'interface_id'}]);
	    if(!defined($res)){
		return;
	    }
	}

	#update operational state
	my $res = $self->_execute_query("update interface set operational_state = ? where interface.interface_id = ?",[$args{'operational_state'},$int->{'interface_id'}]);
	if(!defined($res)){
	    $self->_set_error("Unable to update operational_state");
	    return;
	}



	if (! $args{'no_instantiation'}){
	    #ok now that we have verified the name and port exist and hopefully haven't changed on us we can check on our instantiation
	    $res = $self->_execute_query("select * from interface_instantiation where interface_id = ? and end_epoch = -1",[$int->{'interface_id'}]);

	    if(defined($res) && defined(@{$res}[0])){
		$res = @{$res}[0];
		if($res->{'capacity_mbps'} ne $args{'capacity_mbps'} || $res->{'mtu_bytes'} ne $args{'mtu_bytes'} || $res->{'admin_state'} ne $args{'admin_state'}){
		    $res = $self->_execute_query("update interface_instantiation set end_epoch = UNIX_TIMESTAMP(NOW()) where interface_instantiation.interface_id = ? and interface_instantiation.end_epoch = -1",[$int->{'interface_id'}]);
		    if(!defined($res)){
			$self->_set_error("Unable to decom interface instantiation");
			return;
		    }
		    $res = $self->_execute_query("insert into interface_instantiation (interface_id,admin_state,end_epoch,start_epoch,capacity_mbps,mtu_bytes) VALUES (?,?,-1,UNIX_TIMESTAMP(NOW()),?,?)",[$int->{'interface_id'},$args{'admin_state'},$args{'capacity_mbps'},$args{'mtu_bytes'}]);
		    if(!defined($res)){
			$self->_set_error("Unable to create interface instantaition");
			return;
		    }
		}


	    }else{
		if (! $args{'no_instantiation'}){
		    $self->_execute_query("insert into interface_instantiation (interface_id,admin_state,end_epoch,start_epoch,capacity_mbps,mtu_bytes) VALUES (?,?,-1,UNIX_TIMESTAMP(NOW()),?,?)",[$int->{'interface_id'},$args{'admin_state'},$args{'capacity_mbps'},$args{'mtu_bytes'}]);
		    if(!defined($res)){
			return;
		    }
		}
	    }
	}

    }
    else{
	#interface does not exist
	#however we aren't guaranteed the same port number didn't already exist... lets check and verify
	$int = $self->_execute_query("select * from interface where interface.node_id = ? and interface.port_number = ?",[$args{'node_id'},$args{'port_num'}]);

	if(defined($int) && defined(@{$int}[0])){
	    #Uh oh, the name changed but the port number already existed... this device configuration is just completely different
	    $int = @{$int}[0];
	    my $update = $self->_execute_query("update interface set port_number=NULL where interface_id = ?",[$int->{'interface_id'}]);
	    if(!defined($update)){
		$self->_set_error("This device had something pretty crappy happen, its going to require manual intervention");
		return;
	    }
	}

	#interface/port number doesn't exist lets create it
	$int_id = $self->_execute_query("insert into interface (node_id,name,description,operational_state,port_number) VALUES (?,?,?,?,?)",[$args{'node_id'},$args{'name'},$args{'description'},$args{'operational_state'},$args{'port_num'}]);
	if(!defined($int_id)){
	    $self->_set_error("Unable to insert a new interface!!");
	    return;
	}

	if (! $args{'no_instantiation'}){

	    my $res = $self->_execute_query("insert into interface_instantiation (interface_id,admin_state,end_epoch,start_epoch,capacity_mbps,mtu_bytes) VALUES (?,?,-1,UNIX_TIMESTAMP(NOW()),?,?)",[$int_id,$args{'admin_state'},$args{'capacity_mbps'},$args{'mtu_bytes'}]);
	    if(!defined($res)){
		return;
	    }

	}

    }

    return $int_id;
}


=head2 edit_circuit

=cut

sub edit_circuit {
    my $self = shift;
    my %args = @_;

    my $circuit_id                = $args{'circuit_id'};
    my $description               = $args{'description'};
    my $bandwidth                 = $args{'bandwidth'};
    my $provision_time            = $args{'provision_time'};
    my $remove_time               = $args{'remove_time'};
    my $links                     = $args{'links'};
    my $backup_links              = $args{'backup_links'};
    my $nodes                     = $args{'nodes'};
    my $interfaces                = $args{'interfaces'};
    my $tags                      = $args{'tags'};
    my $state                     = $args{'state'} || "active";
    my $user_name                 = $args{'user_name'};
    my $workgroup_id              = $args{'workgroup_id'};
    my $loop_node                 = $args{'loop_node'};
    my $remote_endpoints          = $args{'remote_endpoints'} || [];
    my $remote_tags               = $args{'remote_tags'} || [];
    my $restore_to_primary        = $args{'restore_to_primary'} || 0;
    my $mac_addresses             = $args{'mac_addresses'};
    my $endpoint_mac_address_nums = $args{'endpoint_mac_address_nums'};
    my $static_mac                = $args{'static_mac'} || 0;
    my $do_commit                 = defined($args{'do_commit'}) ? $args{'do_commit'} : 1;
    my $do_sanity_check           = defined($args{'do_sanity_check'}) ? $args{'do_sanity_check'} : 1;

    # whether this edit should only edit everything or just local bits
    my $do_external               = $args{'do_external'} || 0;

    # do a quick check on arguments passed in
    if($do_sanity_check && !$self->circuit_sanity_check(%args)){
        return;
    }

    my $query;
    $self->_start_transaction() if($do_commit);
    my $circuit = $self->get_circuit_by_id(circuit_id => $circuit_id);
    if(!defined($circuit)){
        $self->_set_error("Unable to find circuit by id $circuit_id");
        $self->_rollback()if($do_commit);
        return;
    }

    my $user_id = $self->get_user_id_by_auth_name(auth_name => $user_name);
    $args{'user_id'} = $user_id;

    if ($provision_time > time()){

        my $success = $self->_add_event(\%args);

        if (! defined $success){
            $self->_rollback() if($do_commit);
            return;
        }
        $self->_commit() if($do_commit);
        return {'success' => 1, 'circuit_id' => $circuit_id};
    }

    my $result = $self->_execute_query("update circuit set description = ?, restore_to_primary = ?, static_mac = ? where circuit_id = ?", [$description,$restore_to_primary,$static_mac,$circuit_id]);
    if (! defined $result){
        $self->_set_error("Unable to update circuit description.");
        $self->_rollback() if($do_commit);
        return;
    }

    # daldoyle - no need to instantiation on circuit edit, causes conflicts with the scheduler and other tools since
    # things happen in sub 1 second

    #aragusa - its been too long lets fix it!
    #instantiate circuit
    $query = "update circuit_instantiation set end_epoch = UNIX_TIMESTAMP(NOW()) where circuit_id = ? and end_epoch = -1";
    if(!defined($self->_execute_query($query, [$circuit_id]))){
        $self->_set_error("Unable to decom old circuit instantiation.");
        $self->_rollback() if($do_commit);
        return
    }

    $query = "insert into circuit_instantiation (circuit_id, reserved_bandwidth_mbps, circuit_state, modified_by_user_id, end_epoch, start_epoch, loop_node) values (?, ?, ?, ?, -1, unix_timestamp(now()), ?)";
    if(!defined($self->_execute_query($query, [$circuit_id, $bandwidth,$state, $user_id, $loop_node]))){
        $self->_set_error("Unable to create new circuit instantiation.");
        $self->_rollback() if($do_commit);
        return

    }

    #first decom everything
    if ($do_external){
        $query = "update circuit_edge_interface_membership set end_epoch = unix_timestamp(now()) where circuit_id = ? and end_epoch = -1";
    }
    else{
        $query = "update circuit_edge_interface_membership " .
            " join interface on interface.interface_id = circuit_edge_interface_membership.interface_id " .
            " join node on node.node_id = interface.node_id " .
            " join network on network.network_id = node.network_id and network.is_local = 1 " .
            " set end_epoch = unix_timestamp(now()) where circuit_id = ? and end_epoch = -1";
    }

    if(!defined($self->_execute_query($query, [$circuit_id]))){
        $self->_set_error("Unable to decom circuit_edge_interface_membership.");
        $self->_rollback() if($do_commit);
        return
    }

    $query = "select * from path where circuit_id = ?";
    my $paths = $self->_execute_query($query, [$circuit_id]);

    foreach my $path (@$paths){
        $query = "update path_instantiation set end_epoch = unix_timestamp(now()) where path_id = ? and end_epoch = -1";
        if(!defined($self->_execute_query($query, [$path->{'path_id'}]))){
            $self->_set_error("Unable to decom path_instantiations");
            $self->_rollback() if($do_commit);
            return
        }
        $query = "update link_path_membership set end_epoch = unix_timestamp(now()) where path_id = ? and end_epoch = -1";
        if(!defined($self->_execute_query($query, [$path->{'path_id'}]))){
            $self->_set_error("Unable to decom link_path_membership");
            $self->_rollback() if($do_commit);
            return
        }
    }

    #re-instantiate
    # first set up endpoints
    for (my $i = 0; $i < @$nodes; $i++){

        my $node      = @$nodes[$i];
        my $interface = @$interfaces[$i];
        my $vlan      = @$tags[$i];
        my $endpoint_mac_address_num = @$endpoint_mac_address_nums[$i];
        my $circuit_edge_id;

        $query = "select interface_id from interface " .
            " join node on node.node_id = interface.node_id " .
            " where node.name = ? and interface.name = ? ";
        my $interface_id = $self->_execute_query($query, [$node, $interface])->[0]->{'interface_id'};

        $query = "insert into circuit_edge_interface_membership (interface_id, circuit_id, extern_vlan_id, end_epoch, start_epoch) values (?, ?, ?, -1, unix_timestamp(NOW()))";

        $circuit_edge_id = $self->_execute_query($query, [$interface_id, $circuit_id, $vlan]);
        if (! defined($circuit_edge_id) ){

            $self->_set_error("Unable to create circuit edge to interface '$interface'");
            $self->_rollback() if($do_commit);
            return;
        }


        # now add any static mac addresses if the static mac address flag was sent
        if($static_mac){

            # create an array of all the mac addresses for this endpoint
            my @endpoint_mac_addresses;
            for (my $j = 0; $j < $endpoint_mac_address_num; $j++){
                my $mac_address = shift(@$mac_addresses);
                push(@endpoint_mac_addresses, $mac_address);
            }

            # now add the mac addresses to the endpoint
            $query = "insert into circuit_edge_mac_address values (?,?)";
            foreach my $mac_address (@endpoint_mac_addresses){
                $mac_address = mac_hex2num( $mac_address );
                if( ! defined $self->_execute_query($query, [$circuit_edge_id, $mac_address]) ){
                    $self->_set_error("Unable to create mac address edge to interface '$interface' on endpoint '$node'");
                    $self->_rollback() if($do_commit);
                    return;
                }
            }
        }
    }

    # set up any remote_endpoints if we have them
    for (my $i = 0; $i < @$remote_endpoints; $i++){
        my $urn = @$remote_endpoints[$i];
        my $tag = @$remote_tags[$i];

        $query = "select interface.interface_id from interface join urn on interface.interface_id=urn.interface_id where urn.urn = ?";
        my $interface_id = $self->_execute_query($query, [$urn])->[0]->{'interface_id'};
        if (! $interface_id){
            $self->_set_error("Unable to find interface associated with URN: $urn");
            $self->_rollback() if($do_commit);
            return;
        }
        $query = "insert into circuit_edge_interface_membership (interface_id, circuit_id, extern_vlan_id, end_epoch, start_epoch) values (?, ?, ?, -1, unix_timestamp(NOW()))";
        if (! defined $self->_execute_query($query, [$interface_id, $circuit_id, $tag])){
            $self->_set_error("Unable to create circuit edge to interface \"$urn\" with tag $tag.");
            $self->_rollback() if($do_commit);
            return;
        }

    }

    my $link_lookup = {
        'primary' => $links,
        'backup'  => $backup_links
    };

    foreach my $path_type (qw(primary backup)){

        my $relevant_links = $link_lookup->{$path_type};

        next if(!defined(@$relevant_links) || !defined($relevant_links->[0]));

        #try to find the path first
        $query = "select * from path where circuit_id = ? and path_type = ?";
        my $res = $self->_execute_query($query,[$circuit_id, $path_type]);
        my $path_id;
        if( !defined($res) || !defined(@{$res}[0]) ){
            # create the primary path object
            $query = "insert into path (path_type, circuit_id) values (?, ?)";
            $path_id = $self->_execute_query($query, [$path_type, $circuit_id]);
        }
        else{
            $path_id = @{$res}[0]->{'path_id'};
        }

        if (!$path_id){
            $self->_set_error("Error while creating path record.");
            $self->_rollback() if($do_commit);
            return;
        }

        # instantiate path object
        $query = "insert into path_instantiation (path_id, end_epoch, start_epoch, path_state) values (?, -1, unix_timestamp(NOW()), ?)";

        my $path_state = "deploying";

        if ($path_type eq "backup"){
            $path_state = "available";
        }

        my $path_instantiation_id = $self->_execute_query($query, [$path_id, $path_state]);

        if (! defined $path_instantiation_id){
            $self->_set_error("Error while instantiating path record.");
            $self->_rollback() if($do_commit);
            return;
        }


        my %seen_endpoints;
        foreach my $link (@$relevant_links){
            my $info = $self->get_link_by_name(name => $link);
            my $link_id = $info->{'link_id'};
            my $endpoints = $self->get_link_endpoints(link_id => $link_id);
            my $interface_a_vlan_id;
            my $interface_z_vlan_id;

            foreach my $endpoint (@$endpoints){
                my $node_id = $endpoint->{'node_id'};
                my $interface_id = $endpoint->{'interface_id'};
                my $interface_a_id = $endpoint->{'interface_a_id'};
                my $interface_z_id = $endpoint->{'interface_z_id'};

                next if ($seen_endpoints{$interface_id});
                $seen_endpoints{$interface_id} = 1;

                # figure out what internal ID we can use for this
                my $internal_vlan = $self->_get_available_internal_vlan_id(node_id => $node_id,interface_id => $interface_id);

                if (! defined $internal_vlan){
                    $self->_set_error("Internal error finding available internal id.");
                    $self->_rollback() if($do_commit);
                    return;
                }

                if ($interface_a_id == $interface_id){
                    $interface_a_vlan_id = $internal_vlan;
                }
                elsif ($interface_z_id == $interface_id){
                    $interface_z_vlan_id = $internal_vlan;
                }
            }

            $query = "insert into link_path_membership (link_id, path_id, end_epoch, start_epoch,interface_a_vlan_id,interface_z_vlan_id) values (?, ?, -1, unix_timestamp(NOW()),?,?)";
            if (!defined ($self->_execute_query($query, [$link_id, $path_id, $interface_a_vlan_id, $interface_z_vlan_id])) ){
                $self->_set_error("Error adding link '$link' into path.");
                $self->_rollback() if($do_commit);
                return;
            }
        }
    }

    $self->_commit() if($do_commit);

    if (defined $loop_node) {

        return {"success" => 1, "circuit_id" => $circuit_id, "loop_node" => $loop_node};
    }
    else {

        return {"success" => 1, "circuit_id" => $circuit_id};
    }
}



=head1 Internal Methods

=head2 _set_error

=over

=item error_string

The error text to set the internal error state to.

=back

=cut

sub _set_error {
    my $self = shift;
    my $err  = shift;

    warn "Setting error to $err\n";

    $self->{'error'} = $err;
}

=head2 _start_transaction

Begins a transaction on the database.

=cut

sub _start_transaction {
    my $self = shift;

    my $dbh = $self->{'dbh'};

    $dbh->begin_work() or die $dbh->errstr;
}

sub _rollback{
    my $self = shift;
    my $dbh = $self->{'dbh'};
    $dbh->rollback();
}

=head2 _get_uuid

Returns a UUID. This is generated via the underlying MySQL database.

=cut

sub _get_uuid {
    my $self = shift;

    my $result = $self->_execute_query("select UUID() as uuid");

    if (! defined $result){
	$self->_set_error("Internal error generating UUID.");
	return;
    }

    return @$result[0]->{'uuid'};
}

=head2 _rollback

=cut

=head2 _commit

Commits a transaction to the database. Assumes you are in a transaction to begin with.

=cut

sub _commit {
    my $self = shift;

    my $dbh = $self->{'dbh'};

    $dbh->commit();
}

=head2 _prepare_query

Returns a statement handle (DBI) after preparing the given query.

=over

=item query

The query to prepare.

=back

=cut

sub _prepare_query {
    my $self  = shift;
    my $query = shift;

    my $dbh = $self->{'dbh'};

    my $sth = $dbh->prepare($query);

    if (! $sth){
	warn "Error in prepare query: $DBI::errstr";
	$self->_set_error("Unable to prepare query: $DBI::errstr");
	return;
    }

    return $sth;
}

=head2 _execute_query

Return type varies depending on query type. Select queries return an array of hashes of rows returned. Update and Delete queries return the number of rows affected. Insert returns the auto_increment key used if relevant. Returns undef on failure.

=over

=item query

The query string to execute.

=item arguments

An array of arguments to pass into the query execute. This is the same as executing a DBI based query with placeholders (?).

=back

=cut

sub _execute_query {
    my $self  = shift;
    my $query = shift;
    my $args  = shift;
    my $caller = ( caller(1) )[3];
    my $dbh = $self->{'dbh'};
    my $sth = $dbh->prepare($query);
    #warn "Query is: $query\n";

    if (! $sth){
    warn "Error in prepare query: $DBI::errstr";
	$self->_set_error("Unable to prepare query: $DBI::errstr");
	return;
    }

    if (! $sth->execute(@$args) ){
	warn "Error in executing query: $caller: $DBI::errstr";
	$self->_set_error("Unable to execute query: $caller: $DBI::errstr");
	return;
    }

    if ($query =~ /^\s*select/i){
        my @array;
	while (my $row = $sth->fetchrow_hashref()){
        push(@array, $row);
    }

	#warn "Returning " . (scalar @array) . " rows";
    return \@array;
    }

    if ($query =~ /^\s*insert/i){
	my $id = $dbh->{'mysql_insertid'};
	#warn "Returning $id";
	return $id;
    }

    if ($query =~ /^\s*delete/i || $query =~ /^\s*update/i){
	my $count = $sth->rows();
	#warn "Updated / deleted $count rows";
	return $count;
    }
    
    return -1;

}

=head2 _get_available_internal_vlan_id

Returns the lowest currently available internal vlan identifier or undef if none are available.

=over

=item node_id

=back

=cut

sub _get_available_internal_vlan_id {
    my $self = shift;
    my %args = @_;

    
    my $node_id = $args{'node_id'};
    my $interface_id = $args{'interface_id'};

    #my $query = "select internal_vlan_id from path_instantiation_vlan_ids " .
#	" join path_instantiation on path_instantiation.path_instantiation_id = path_instantiation_vlan_ids.path_instantiation_id " .
#	"   where path_instantiation.end_epoch = -1 and path_instantiation_vlan_ids.node_id = ?";
    my $query = 
        "select CASE
WHEN link_instantiation.interface_a_id = ? 
THEN link_path_membership.interface_a_vlan_id 
ELSE link_path_membership.interface_z_vlan_id 
END as 'internal_vlan_id' 
from link_path_membership
join link on (link.link_id = link_path_membership.link_id and link_path_membership.end_epoch = -1)
join link_instantiation 
on link.link_id = link_instantiation.link_id
and link_instantiation.end_epoch=-1
and (link_instantiation.interface_a_id = ? or link_instantiation.interface_z_id = ?)
join path_instantiation on link_path_membership.path_id = path_instantiation.path_id
and path_instantiation.end_epoch = -1
";    

    my %used;

    my $results = $self->_execute_query($query, [$interface_id,$interface_id,$interface_id]);

    # something went wrong
    if (! defined $results){
	$self->_set_error("Internal error finding available internal id.");
	return;
    }

    foreach my $row (@$results){
	$used{$row->{'internal_vlan_id'}} = 1;
    }

    my $allowed_vlan_tags = $self->get_allowed_vlans(node_id => $node_id);

    foreach my $tag (@$allowed_vlan_tags){
	if (! exists $used{$tag}){
	    return $tag;
	}
    }

    return;
}

=head2 get_allowed_vlans

Returns an array of tags that are configured to be allowed for this node.

=over

=item node_id

=back

=cut

sub get_allowed_vlans {
    my $self = shift;
    my %args = @_;

    my $node_id = $args{'node_id'};

    my $query = "select vlan_tag_range from node where node_id = ?";

    my $results = $self->_execute_query($query, [$node_id]);

    if (! defined $results){
	$self->_set_error("Internal error while determining what vlan tag ranges are allowed for node id: $node_id.");
	return;
    }

    # stored as a string so we can define multiple ranges
    my $string = $results->[0]->{'vlan_tag_range'};

    my $tags = $self->_process_tag_string($string);
    return $tags;
}

sub _process_tag_string{
    my $self          = shift;
    my $string        = shift;
    my $oscars_format = shift || 0;
    my $MIN_VLAN_TAG  = ($oscars_format) ? 0 : MIN_VLAN_TAG;

    if(!defined($string)){
	    return;
    }
    if($oscars_format){
        $string =~ s/^-1/0/g;
        $string =~ s/,-1/0/g;
    }

    my @split = split(/,/, $string);
    my @tags;

    foreach my $element (@split){
	if ($element =~ /^(\d+)-(\d+)$/){

	    my $start = $1;
	    my $end   = $2;

	    if (($start < $MIN_VLAN_TAG && $start != UNTAGGED)|| $end > MAX_VLAN_TAG){
		return;
	    }

	    foreach my $tag_number ($start .. $end){
		push(@tags, $tag_number);
	    }

	}elsif ($element =~ /^(\-?\d+)$/){
	    my $tag_number = $1;
	    if (($tag_number < $MIN_VLAN_TAG && $tag_number != UNTAGGED) || $tag_number > MAX_VLAN_TAG){
		return;
	    }
	    push (@tags, $1);

	}else{

	    return;
	}

    }

    return \@tags;
}

=head2 _validate_endpoint

Verifies that the endpoint in question is accessible to the given workgroup. If a vlan tag is not passed in returns the list of available vlan tag ranges.

=over

=item interface_id

=item workgroup_id

=back

=cut

sub _validate_endpoint {
    my $self = shift;
    my %args = @_;

    my $interface_id = $args{'interface_id'};
    my $workgroup_id = $args{'workgroup_id'};
    my $vlan         = $args{'vlan'};

    my $query  = "select * ";
       $query .= " from interface_acl ";
       $query .= " join interface on interface_acl.interface_id = interface.interface_id ";
       $query .= " where interface_acl.interface_id = ? ";
       $query .= " and (interface_acl.workgroup_id = ? or interface_acl.workgroup_id IS NULL) order by eval_position";

    my $results = $self->_execute_query($query, [$interface_id, $workgroup_id]);

    if (! defined $results){
	$self->_set_error("Internal error validating endpoint.");
	return;
    }


    my $vlan_range_hash;
    foreach my $result (@$results) {
        my $permission = $result->{'allow_deny'};
        my $vlan_start = $result->{'vlan_start'};
        my $vlan_end   = $result->{'vlan_end'} || $vlan_start;


        # if vlan is not defined determine what ranges are available
        if(!defined($vlan)) {
            if($permission eq "deny") {
                $vlan_range_hash = $self->_set_vlan_range_allow_deny(
                    vlan_range_hash  => $vlan_range_hash,
                    vlan_start       => $vlan_start,
                    vlan_end         => $vlan_end,
                    allow_deny       => 0
                );
            } else {
                $vlan_range_hash = $self->_set_vlan_range_allow_deny(
                    vlan_range_hash  => $vlan_range_hash,
                    vlan_start       => $vlan_start,
                    vlan_end         => $vlan_end,
                    allow_deny       => 1
                );
            }
        }
        # otherwise if our vlan falls within this rules range determine if it is allow
        # or deny
        elsif( ($vlan_start <= $vlan) && ($vlan <= $vlan_end)  ) {
            if($permission eq "deny") {
                return 0;
            } else {
                return 1;
            }
        }
    }

    # convert the hash to a vlan range string
    if(!defined($vlan)){
        return $self->_vlan_range_hash2str( vlan_range_hash => $vlan_range_hash );
    }

    # if no applicable rules were found default to deny
    return 0;
}

=head2 _set_vlan_range_allow_deny

Sets the hash element keyed on vlan range to 1 for allow and 0 for deny. If the key already exists it does nothing because
we already encountered a rule that either allowed of denied it.

=cut
sub _set_vlan_range_allow_deny {
    my $self = shift;
    my %args = @_;

    my $vlan_range_hash = $args{'vlan_range_hash'};
    my $vlan_start      = $args{'vlan_start'};
    my $vlan_end        = $args{'vlan_end'} || $vlan_start;
    my $allow_deny      = $args{'allow_deny'};

    for(my $vlan = $vlan_start; $vlan <= $vlan_end; $vlan++){
        # only set allow_deny if we dont already have a value for this vlan
        # otherwise we have already determined if it should be allowed or denied in a previous rule
        if(!exists($vlan_range_hash->{$vlan})){
            $vlan_range_hash->{$vlan} = $allow_deny;
        }
    }

    return $vlan_range_hash;
}

sub _vlan_range_hash2str {
    my $self = shift;
    my %args = @_;
    my $vlan_range_hash = $args{'vlan_range_hash'};
    my $oscars_format   = $args{'oscars_format'} || 0;
    # delete zero if it exists since its an invalid tag
    if(!$oscars_format && exists($vlan_range_hash->{'0'})){
        delete $vlan_range_hash->{'0'};
    }
    # create an array of the allowed vlans and sort them
    my @allowed_vlan_array;
    foreach my $vlan (keys %$vlan_range_hash) {
        my $is_allowed = $vlan_range_hash->{$vlan};
        if($is_allowed){
            push(@allowed_vlan_array, $vlan);
        }
    }
    @allowed_vlan_array = sort {$a <=> $b} @allowed_vlan_array;

    # return undef if there are no allowed vlans
    return undef if(@allowed_vlan_array == 0);

    # now create a string of vlan ranges
    my $vlan_start;
    my $vlan_end;
    my $last_vlan;
    my $vlan_range_string = "";
    foreach my $allowed_vlan (@allowed_vlan_array) {
        # if we don't have a start set yet for consecutive ranges set it
        if(!defined($vlan_start)){
            $vlan_start = $allowed_vlan;
        }
        else {
            # if we are in consecutive order set a new end
            if($allowed_vlan == ($last_vlan + 1) ){
                $vlan_end = $allowed_vlan;
            }
            else {
                # if we have a last set append the range on the string
                #if(defined($last_vlan)){
                if(defined($vlan_end)){
                    $vlan_range_string .= "$vlan_start-$vlan_end,";
                    $vlan_start = $allowed_vlan;
                    $vlan_end   = undef;
                }
                # if we do not append the single value onto the string
                else {
                    $vlan_range_string .= "$vlan_start,";
                    $vlan_start = $allowed_vlan;
                }
            }
        }

        $last_vlan = $allowed_vlan;
    }

    # check to see if we were still calculating a range when the loop finished
    if(defined($vlan_start)){
        if(defined($vlan_end)){
            $vlan_range_string .= "$vlan_start-$vlan_end";
        } else {
            $vlan_range_string .= "$vlan_start";
        }
    }
    # otherwise remove the trailing comma
    else {
        chop($vlan_range_string);
    }

    return $vlan_range_string;
}

=head2 get_oscars_host

Returns OSCARS host

=cut

sub get_oscars_host{
    my $self = shift;
    return $self->{'oscars'}->{'host'};
}

=head2 get_oscars_key

=cut
sub get_oscars_key{
    my $self = shift;
    return $self->{'oscars'}->{'key'};
}

=head2 get_oscars_cert

=cut
sub get_oscars_cert{
    my $self = shift;
    return $self->{'oscars'}->{'cert'};
}

=head2 get_oscars_topo

=cut
sub get_oscars_topo{
    my $self = shift;
    return $self->{'oscars'}->{'topo'};
}

=head2 get_snapp_config_location

Returns the location of the SNAPP config

=cut

sub get_snapp_config_location{
    my $self = shift;
    return $self->{'snapp_config_location'};

}

=head2 get_current_actions

 returns a set of actions that are set to be complete NOW

=cut

sub get_current_actions{
    my $self = shift;

    my $query = "select * from scheduled_action where activation_epoch < unix_timestamp(now()) and completion_epoch = -1";

    return $self->_execute_query($query,[]);

}


=head2 can_modify_circuit

=cut

sub can_modify_circuit {
    my $self = shift;
    my %params = @_;



    if(!defined($params{'circuit_id'})){
        $self->_set_error("can_modify_circuit requires a circuit_id");
        return;
    }

    if(!defined($params{'username'})){
        $self->_set_error("can_modify_circuit requires a username");
        return;
    }

    if(!defined($params{'workgroup_id'})){
        $self->_set_error("can_modify_circuit requires a workgroup_id");
        return;
    }

    my $workgroup = $self->get_workgroup_by_id( workgroup_id => $params{'workgroup_id'});
    if (! defined $workgroup){
        $self->_set_error("Unknown workgroup.");
        return;
    }

    my $user_id = $self->get_user_id_by_auth_name( auth_name => $params{'username'});
    if (! $user_id ){
        $self->_set_error("Unknown user '".$params{'username'}."'");
        return;
    }


    my $user = $self->get_user_by_id( user_id => $user_id )->[0];
    if($user->{'type'} eq 'read-only'){
        $self->_set_error("User '" . $params{'username'} . "' has read-only permissions.");
        return 0;
    }
    elsif($user->{'status'} eq 'decom'){
        $self->_set_error("User '" . $params{'username'} . "' has been decommissioned.");
        return 0;
    }

    my $authorization = $self->get_user_admin_status( 'user_id' => $user_id);
    #giving Admins permission to edit / reprovision / delete circuits ISSUE=7690
    if ( $authorization->[0]{'is_admin'} == 1 ) {
        return 1;
    }
    my $is_user_in_workgroup = $self->is_user_in_workgroup( 
        workgroup_id => $params{'workgroup_id'},
        user_id => $user_id
    );
    
    if(!$is_user_in_workgroup){
        return 0;
    }

    my $query = "select workgroup_id from circuit where circuit_id = ?";
    my $res = $self->_execute_query($query,[$params{'circuit_id'}])->[0];
    if(!defined($res)){
        $self->_set_error("Unable to find circuit with id " . $params{'circuit_id'});
        return;
    }

    if($res->{'workgroup_id'} == $params{'workgroup_id'}){
        return 0 if $workgroup->{'type'} eq 'demo';
        return 0 if $workgroup->{'status'} eq 'decom';
        return 1 if $workgroup->{'type'} eq 'normal' || $workgroup->{'type'} eq 'admin';
    }

    if($workgroup->{'type'} eq 'admin'){
        return 1;
    }

    return 0;
}

=head2 validate_endpoints
    validates circuit endpoints passed in

=cut

sub validate_endpoints {
    my ($self, %args) = @_;

    my $circuit_id     = $args{'circuit_id'};
    my $nodes          = $args{'nodes'};
    my $interfaces     = $args{'interfaces'};
    my $tags           = $args{'tags'};
    my $workgroup_id   = $args{'workgroup_id'};
    my $mac_addresses  = $args{'mac_addresses'};
    my $static_mac     = $args{'static_mac'} || 0; 
    my $endpoint_mac_address_nums = $args{'endpoint_mac_address_nums'};

    for (my $i = 0; $i < @$nodes; $i++){
        my $node      = @$nodes[$i];
        my $interface = @$interfaces[$i];
        my $vlan      = @$tags[$i];
        my $endpoint_mac_address_num = @$endpoint_mac_address_nums[$i];

        my $query = "select interface_id from interface " .
                    " join node on node.node_id = interface.node_id " .
                    " where node.name = ? and interface.name = ? ";
        my $interface_id = $self->_execute_query($query, [$node, $interface])->[0]->{'interface_id'};

        if (! $interface_id ){
            $self->_set_error("Unable to find interface '$interface' on node '$node'");
            return;
        }

        if (! $self->_validate_endpoint(interface_id => $interface_id, workgroup_id => $workgroup_id, vlan => $vlan)){
            $self->_set_error("Interface \"$interface\" on endpoint \"$node\" with VLAN tag \"$vlan\" is not allowed for this workgroup.");
            return;
        }

        # need to check to see if this external vlan is open on this interface first
        if (! $self->is_external_vlan_available_on_interface(vlan => $vlan, interface_id => $interface_id, circuit_id => $circuit_id) ){
            $self->_set_error("Vlan '$vlan' is currently in use by another circuit on interface '$interface' on endpoint '$node'");
            return;
        }

        # now add any static mac addresses if the static mac address flag was sent
        if($static_mac){
            # create an array of all the mac addresses for this endpoint
            my @endpoint_mac_addresses;
            for (my $j = 0; $j < $endpoint_mac_address_num; $j++){
                my $mac_address = $mac_addresses->[$j];
                push(@endpoint_mac_addresses, $mac_address);
            }

            # check that the mac_addresses fall within the limits
            my $result = $self->is_within_mac_limit(
                mac_address  => \@endpoint_mac_addresses,
                interface    => $interface,
                node         => $node,
                workgroup_id => $workgroup_id
            );
            if(!$result->{'verified'}){
                $self->_set_error($result->{'explanation'});
                return;
            }

            # now make sure the mac_addresses are valid
            foreach my $mac_address (@endpoint_mac_addresses){
                if( ! mac_validate( $mac_address ) ){
                    $self->_set_error("$mac_address is not a valid mac address.");
                    return;
                }
            }
        }
    }

    return 1;
}

=head2 validate_paths

validates paths set on circuit before its provisioned

=cut

sub validate_paths {
    my ($self, %args) = @_;

    my $nodes          = $args{'nodes'};
    my $interfaces     = $args{'interfaces'};
    my $tags           = $args{'tags'};
    my $links          = $args{'links'};
    my $backup_links   = $args{'backup_links'};

    my $endpoints = [];
    for (my $i = 0; $i < @$nodes; $i++){
        my $node      = 
        my $interface = 
        my $vlan      = 
        push(@$endpoints, {
            node => @$nodes[$i],
            interface => @$interfaces[$i],
            vlan => @$tags[$i]
        });        
    }

    # now check to verify that the topology makes sense
    my ($success, $error) = $self->{'topo'}->validate_paths(
        links        => $links,
        backup_links => $backup_links,
        endpoints    => $endpoints
    );
    if (! $success){
        $self->_set_error($error);
        return;
    }

    return 1;
}

=head2 circuit_sanity_check

performs a preflight check on circuit parameters

=cut

sub circuit_sanity_check {
    my ($self, %args) = @_;

    # make sure user passed in can modify circuit
    if(!$self->can_modify_circuit(username => $args{'user_name'}, %args)){
        return;
    }

    # makes sure this workgroup hasn't gone over their endpoint limit
    my $endpoint_num = @{$args{'nodes'}};
    my $within_limit = $self->is_within_circuit_endpoint_limit( 
        workgroup_id => $args{'workgroup_id'},
        endpoint_num => $endpoint_num
    );
    if(!$within_limit){
        $self->_set_error("Permission denied: $endpoint_num endpoints exceeds the limit of endpoints per circuit placed on this workgroup.");
        return;
    }

    # make sure endpoints pass validation
    if(!$self->validate_endpoints(%args)){
        return;
    }

    # make sure paths make sense
    if(!$self->validate_paths(%args)){
        return;
    }

    return 1;
}


=head2 get_circuits_by_state

returns the all circuits in a given state

=cut

sub get_circuits_by_state{
    my $self = shift;
    my %params = @_;

    if(!defined($params{'state'})){
	$self->_set_error("get_circuits_by_state requires state parameter to be defined");

    return;
    }

    my $query  = "select * from circuit";
       $query .= " JOIN circuit_instantiation";
       $query .= " WHERE circuit.circuit_id = circuit_instantiation.circuit_id";
       $query .= " AND circuit_instantiation.end_epoch = -1";
       $query .= " AND circuit_instantiation.circuit_state = ?";

    my $sth = $self->{'dbh'}->prepare($query);
    if(!defined($sth)){
	$self->_set_error("Unable to prepare Query: $query: $DBI::errstr");
	return;
    }

    my $res = $sth->execute($params{'state'});
    if(!$res){
	$self->_set_error("Error executing query: $DBI::errstr");
	return;
    }

    my @results;
    while(my $row = $sth->fetchrow_hashref()){
	push(@results,$row);
    }

    return \@results;

}



=head2 get_local_domain_name

Returns the domain name of the network which is local to this instance.

=cut

sub get_local_domain_name {
    my $self = shift;

    my $result = $self->_execute_query("select name from network where is_local = 1")->[0];

    return $result->{'name'};
}

=head2 gen_topo

Generates an XML representation of the OESS database designed to be compliant OSCARS.

=cut

sub gen_topo{
    my $self   = shift;
    my $wg = shift || OSCARS_WG;
    my $domain_prefix = shift;

    my $workgroup = $self->get_workgroup_details_by_name( name => $wg );
    my $domain = $self->get_local_domain_name();

    if(defined($domain_prefix)){
        $domain = "$domain_prefix." . $domain;
    }

    my $xml = "";
    my $writer = new XML::Writer(OUTPUT => \$xml, DATA_INDENT => 2, DATA_MODE => 1, NAMESPACES => 1);
    $writer->startTag("topology", id=> $domain);
    $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","idcId"]);
    $writer->characters($domain);
    $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","idcId"]);
    $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","domain"], id => $domain);

    #generate the topology
    my $nodes = $self->get_nodes_by_admin_state(admin_state => "active");

    foreach my $node (@$nodes){
    $node->{'name'} =~ s/ /+/g;
        $node->{'name'} =~ s/ /+/g;
        $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","node"], id => "urn:ogf:network:domain=" . $domain . ":node=" . $node->{'name'});
        $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","address"]);
        $writer->characters($node->{'management_addr_ipv4'});
        $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","address"]);

        $node->{'vlan_tag_range'} =~ s/^-1/0/g;
        $node->{'vlan_tag_range'} =~ s/,-1/0/g;

        my %interfaces;
            my $ints = $self->get_node_interfaces( node => $node->{'name'}, workgroup_id => $workgroup->{'workgroup_id'}, show_down => 1);

        foreach my $int (@$ints){
            $interfaces{$int->{'name'}} = $int;
        }

        my $link_ints = $self->get_link_ints_on_node( node_id => $node->{'node_id'} );

        foreach my $int (@$link_ints){
            $interfaces{$int->{'name'}} = $int;
        }

        foreach my $int_name (keys (%interfaces)){
            my $int = $interfaces{$int_name};
            $int->{'name'} =~ s/ /+/g;
            if(!defined($int->{'capacity_mbps'})){
                my $interface = $self->get_interface( interface_id => $int->{'interface_id'} );
                my $speed = $self->get_interface_speed( interface_id => $int->{'interface_id'});
                $int->{'capacity_mbps'} = $speed;
            }
            $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","port"], id => "urn:ogf:network:domain=" . $domain . ":node=" . $node->{'name'} . ":port=" . $int->{'name'});

            $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","capacity"]);
            $writer->characters($int->{'capacity_mbps'} * 1000000);
            $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","capacity"]);
            $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","maximumReservableCapacity"]);
            $writer->characters($int->{'capacity_mbps'} * 1000000);
            $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","maximumReservableCapacity"]);
            $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","minimumReservableCapacity"]);
            $writer->characters(1000000);
            $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","minimumReservableCapacity"]);
            $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","granularity"]);
            $writer->characters(1000000);
            $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","granularity"]);

            my $links = $self->get_link_by_interface_id( 
                interface_id => $int->{'interface_id'}, 
                force_active => 1 
            );
            my $processed_link = 0;

            foreach my $link (@$links){
                # only show links we know about that are trunked (this is actually the interface role)
                $processed_link = 1;
                if(!defined($link->{'remote_urn'})){
                    $link->{'link_name'} =~ s/ /+/g;
                    $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","link"], id => "urn:ogf:network:domain=" . $domain . ":node=" . $node->{'name'} . ":port=" . $int->{'name'} . ":link=" . $link->{'link_name'});

                    my $link_endpoints = $self->get_link_endpoints(link_id => $link->{'link_id'});
                    my $remote_int;
                    foreach my $link_endpoint (@$link_endpoints){
                        if ($link_endpoint->{'node_id'} ne $node->{'node_id'} ){
                            $remote_int = $link_endpoint;
                        }
                    }

                    my $remote_node = $self->get_node_by_id( node_id => $remote_int->{'node_id'});

                    if(!defined($remote_node->{'name'})){
                        $remote_node->{'name'} = "*";
                    }

                    if(!defined($remote_int->{'interface_name'})){
                        $remote_int->{'interface_name'} = "*";
                    }

                    if(!defined($link->{'link_name'})){
                        $link->{'link_name'} = "*";
                    }

                    $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","remoteLinkId"]);
                    $writer->characters("urn:ogf:network:domain=" . $domain . ":node=" . $remote_node->{'name'} . ":port=" . $remote_int->{'interface_name'} . ":link=" . $link->{'link_name'});
                    $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","remoteLinkId"]);
                }else{
                    $link->{'link_name'} =~ s/ /+/g;
                    #remote urn is defined
                    $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","link"], id => "urn:ogf:network:domain=" . $domain . ":node=" . $node->{'name'} . ":port=" . $int->{'name'} . ":link=" . $link->{'link_name'});
                    $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","remoteLinkId"]);
                    $writer->characters($link->{'remote_urn'});
                    $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","remoteLinkId"]);
                }
                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","trafficEngineeringMetric"]);

                if(defined($link->{'remote_urn'})){
                    $writer->characters("100");
                }else{
                    $writer->characters("10");
                }

                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","trafficEngineeringMetric"]);
                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","capacity"]);
                $writer->characters($int->{'capacity_mbps'} * 1000000);
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","capacity"]);

                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","maximumReservableCapacity"]);
                $writer->characters($int->{'capacity_mbps'} * 1000000);
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","maximumReservableCapacity"]);
                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","minimumReservableCapacity"]);
                $writer->characters(1000000);
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","minimumReservableCapacity"]);
                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","granularity"]);
                $writer->characters(1000000);
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","granularity"]);

                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","SwitchingCapabilityDescriptors"]);
                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","switchingcapType"]);
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","switchingcapType"]);
                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","encodingType"]);
                $writer->characters("packet");
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","encodingType"]);
                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","switchingCapabilitySpecificInfo"]);
                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","capability"]);
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","capability"]);
                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","interfaceMTU"]);
                $writer->characters($int->{'mtu_bytes'});
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","interfaceMTU"]);
                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","vlanRangeAvailability"]);

                #$writer->characters("2-4094");
                my $tag_range;
                if(defined($link->{'remote_urn'})){
                    $tag_range = $self->_validate_endpoint( workgroup_id => $workgroup->{'workgroup_id'}, interface_id => $int->{'interface_id'});
                    $tag_range =~ s/^-1/0/g;
                    $tag_range =~ s/,-1/0/g;
                }else{
                    $tag_range = $node->{'vlan_tag_range'};
                }
                # compute the intersection of the vlan tag range set on the link and our range as determined my the interface acl or the
                # node's allowed vlan_range
                if($link->{'vlan_tag_range'}){

                    $tag_range = $self->_get_vlan_range_intersection( 
                        vlan_ranges => [$tag_range,$link->{'vlan_tag_range'}], 
                        oscars_format => 1 
                    );
                }

                $writer->characters( $tag_range );


                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","vlanRangeAvailability"]);
                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","vlanTranslation"]);
                $writer->characters("true");
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","vlanTranslation"]);
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","switchingCapabilitySpecificInfo"]);
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","SwitchingCapabilityDescriptors"]);

                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","link"]);
            }

            if($int->{'role'} ne 'trunk' && $processed_link == 0){
                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","link"], id => "urn:ogf:network:domain=" . $domain . ":node=" . $node->{'name'} . ":port=" . $int->{'name'} . ":link=*");
                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","remoteLinkId"]);
                $writer->characters("urn:ogf:network:domain=*:node=*:port=*:link=*");
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","remoteLinkId"]);

                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","trafficEngineeringMetric"]);
                $writer->characters("10");
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","trafficEngineeringMetric"]);
                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","capacity"]);
                $writer->characters($int->{'capacity_mbps'} * 1000000);
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","capacity"]);

                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","maximumReservableCapacity"]);
                $writer->characters($int->{'capacity_mbps'} * 1000000);
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","maximumReservableCapacity"]);
                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","minimumReservableCapacity"]);
                $writer->characters(1000000);
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","minimumReservableCapacity"]);
                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","granularity"]);
                $writer->characters(1000000);
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","granularity"]);

                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","SwitchingCapabilityDescriptors"]);
                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","switchingcapType"]);
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","switchingcapType"]);
                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","encodingType"]);
                $writer->characters("packet");
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","encodingType"]);
                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","switchingCapabilitySpecificInfo"]);
                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","capability"]);
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","capability"]);
                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","interfaceMTU"]);
                $writer->characters($int->{'mtu_bytes'});
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","interfaceMTU"]);
                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","vlanRangeAvailability"]);
                #replace -1 with 0 for OSCARS
                $int->{'vlan_tag_range'} =~ s/^-1/0/g;
                $int->{'vlan_tag_range'} =~ s/,-1/0/g;
                $writer->characters( $int->{'vlan_tag_range'} );

                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","vlanRangeAvailability"]);

                $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","vlanTranslation"]);
                $writer->characters("true");
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","vlanTranslation"]);
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","switchingCapabilitySpecificInfo"]);
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","SwitchingCapabilityDescriptors"]);

                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","link"]);

            }

            $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","port"]);
        }

        $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","node"]);
    }

    #end do stuff
    $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","domain"]);
    $writer->endTag("topology");
    $writer->end();
    return $xml;
}

=head2 get_admin_email

=cut
sub get_admin_email{
    my $self = shift;
    return $self->{'admin_email'};
}

=head2 get_circuit_edge_on_interface

=cut
sub get_circuit_edge_on_interface{
    my $self = shift;
    my %params = @_;

    if(!defined($params{'interface_id'})){
	$self->_set_error("No Interface ID specified for get_circuit_edge_on_interface");
	return undef;
    }

    my $query = "select * from circuit, circuit_instantiation, circuit_edge_interface_membership where circuit.circuit_id = circuit_edge_interface_membership.circuit_id and circuit_instantiation.circuit_id = circuit.circuit_id and circuit_instantiation.end_epoch = -1 and circuit_edge_interface_membership.end_epoch = -1 and circuit_edge_interface_membership.interface_id = ? and circuit_instantiation.circuit_state != 'decom'";

    my $circuits = $self->_execute_query($query,[$params{'interface_id'}]);
    return $circuits;
}

=head2 update_circuit_owner

=cut
sub update_circuit_owner{
    my $self = shift;
    my %args = @_;

    return if(!defined($args{'circuit_id'}));
    return if(!defined($args{'workgroup_id'}));

    my $str = "update circuit set workgroup_id = ? where circuit_id = ?";
    my $success = $self->_execute_query($str,[$args{'workgroup_id'},$args{'circuit_id'}]);
    return 1;
}

=head2 get_edge_interface_move_maintenances

=cut

sub get_edge_interface_move_maintenances {
    my ($self, %args) = @_;
    my $show_history        = $args{'show_history'} || 0;
    my $show_moved_circuits = $args{'show_moved_circuits'} || 0;
    my $maintenance_id      = $args{'maintenance_id'}; 

    # first retrieve all the edge interface records
    my $params = [];
    my $query  = "SELECT maint.maintenance_id, ".
                 "       maint.name, ".
                 "       maint.orig_interface_id, ".
                 "       maint.temp_interface_id, ".
                 "       maint.start_epoch, ".
                 "       maint.end_epoch, ".
                 "       orig_int.name AS orig_interface_name, ".
                 "       temp_int.name AS temp_interface_name ".
                 "FROM edge_interface_move_maintenance as maint ".
                 "JOIN interface AS orig_int ON maint.orig_interface_id = orig_int.interface_id ".
                 "JOIN interface AS temp_int ON maint.temp_interface_id = temp_int.interface_id";

    # build where clause
    my $where = "";
    if($maintenance_id) {
        $where .= " maint.maintenance_id = ?";
        push(@$params, $maintenance_id);
    }
    if(!$show_history){
        $where .= " AND " if($where ne "");
        $where .= " maint.end_epoch = -1";
    }
    if($where ne ""){
        $query .= " WHERE $where";
    }

    my $maintenances = $self->_execute_query($query, $params) || return;

    # append all the moved circuit info if they've asked for it
    if($show_moved_circuits){
        foreach my $maintenance (@$maintenances){
            $query  = "SELECT circuit.circuit_id AS circuit_id, ".
                            " circuit.name AS circuit_name, ".
                            " circuit.description AS circuit_description ".
                      "FROM edge_interface_move_maintenance_circuit_membership ".
                      "JOIN circuit ".
                      "ON edge_interface_move_maintenance_circuit_membership.circuit_id = circuit.circuit_id ".
                      "WHERE maintenance_id = ?";
            my $circuits = $self->_execute_query($query, [$maintenance->{'maintenance_id'}]) || return;
            $maintenance->{'moved_circuits'} = $circuits;
        }
    }

    return $maintenances; 
}

=head2 add_edge_interface_move_maintenance 

=cut
sub add_edge_interface_move_maintenance {
    my ($self, %args) = @_;
    my $name              = $args{'name'};
    my $orig_interface_id = $args{'orig_interface_id'};     
    my $temp_interface_id = $args{'temp_interface_id'};     
    my $circuit_ids       = $args{'circuit_ids'};     
    my $do_commit         = (defined($args{'do_commit'})) ? $args{'do_commit'} : 1;

    # sanity checks 
    if(!defined($name)){
	    $self->_set_error("Must pass in name for maintenance.");
        return;
    }

    $self->_start_transaction() if($do_commit);

    # first insert the maintenance record
    my $query = "INSERT INTO edge_interface_move_maintenance ( ".
                "  name, ".
                "  orig_interface_id, ". 
                "  temp_interface_id, ". 
                "  start_epoch ) ". 
                "VALUES (?,?,?,UNIX_TIMESTAMP(NOW()))";
    my $maintenance_id = $self->_execute_query($query,[
        $name,
        $orig_interface_id,
        $temp_interface_id
    ]);
    if(!defined($maintenance_id)){
	    $self->_set_error("Unable to add edge_interface_move_maintenance.");
	    $self->_rollback() if($do_commit);
        return;
    }

    # now move the circuits from the original interface to the temporary one
    my $res = $self->move_edge_interface_circuits(
        orig_interface_id => $orig_interface_id,
        new_interface_id  => $temp_interface_id,
        circuit_ids       => $circuit_ids,
        do_commit         => 0
    );
    if(!defined($res)){
	    $self->_rollback() if($do_commit);
        return;
    }
    my $moved_circuit_ids   = $res->{'moved_circuits'};
    my $unmoved_circuit_ids = $res->{'unmoved_circuits'};

    # now create edge_interface_move_maintenance_circuit_membership records for each moved circuit
    foreach my $circuit_id (@$moved_circuit_ids){
        my $query = "INSERT INTO edge_interface_move_maintenance_circuit_membership ( ".
                    "  maintenance_id, ".
                    "  circuit_id ) ". 
                    "VALUES (?,?)";
        my $res = $self->_execute_query($query,[
            $maintenance_id,
            $circuit_id
        ]);
        if(!defined($res)){
            $self->_set_error("Unable to add edge_interface_move_maintenance_circuit_membership.".$self->{'dbh'}->errstr);
            $self->_rollback() if($do_commit);
            return;
        }
    }

    $self->_commit() if($do_commit);
    return { 
        maintenance_id   => $maintenance_id,
        moved_circuits   => $res->{'moved_circuits'},
        unmoved_circuits => $res->{'unmoved_circuits'},
        dpid             => $res->{'dpid'}
    };
}

=head2 revert_edge_interface_move_maintenance 

=cut
sub revert_edge_interface_move_maintenance {
    my ($self, %args) = @_;
    my $maintenance_id = $args{'maintenance_id'};
    my $do_commit = (defined($args{'do_commit'})) ? $args{'do_commit'} : 1;

    #sanity checks
    if(!defined($maintenance_id)){
	    $self->_set_error("maintenance_id must be defined");
        return;
    }
    
    # get our maintenance
    my $maints = $self->get_edge_interface_move_maintenances(
        maintenance_id      => $maintenance_id,
        show_moved_circuits => 1
    );
    if(!defined($maints) || @$maints < 1){
	    $self->_set_error("Error retrieving maintenance with maintenance_id $maintenance_id");
        return;
    }

    # get the circuits it moved
    my @circuit_ids = map { $_->{'circuit_id'} } @{ $maints->[0]{'moved_circuits'} };

    $self->_start_transaction() if($do_commit);

    # move the circuits back
    my $res = $self->move_edge_interface_circuits(
        orig_interface_id => $maints->[0]{'temp_interface_id'},
        new_interface_id  => $maints->[0]{'orig_interface_id'},
        circuit_ids       => \@circuit_ids,
        do_commit         => 0
    );
    if(!$res){
	    $self->_set_error("Error moving circuits back to original interface");
	    $self->_rollback() if($do_commit);
        return;
    }

    # now set the end_epoch time on the maintenance record
    my $query = "UPDATE edge_interface_move_maintenance ".
                "SET end_epoch = UNIX_TIMESTAMP(NOW()) ".
                "WHERE maintenance_id = ?";
    my $recs = $self->_execute_query($query, [$maintenance_id]);
    if(!$recs){
        $self->_rollback() if($do_commit);
        return;
    }

    $self->_commit() if($do_commit);

    return { 
        maintenance_id   => $maintenance_id,
        moved_circuits   => $res->{'moved_circuits'},
        unmoved_circuits => $res->{'unmoved_circuits'},
        dpid             => $res->{'dpid'}
    };
}

=head2 get_circuit_edge_interface_memberships

=cut

sub get_circuit_edge_interface_memberships {
    my ($self, %args) = @_;
    my $interface_id  = $args{'interface_id'};
    my $circuit_ids   = $args{'circuit_ids'};

    my $params = [$interface_id];
    my $query = "SELECT * ".
                "FROM circuit_edge_interface_membership ".
                "WHERE interface_id = ?  ".
                "AND end_epoch = -1";
    if($circuit_ids){
        $query .= " AND circuit_id IN (".(join(',', ('?') x @$circuit_ids)).")";
        push(@$params, @$circuit_ids);
    }
    my $edge_interface_recs = $self->_execute_query($query, $params) || return;

    return $edge_interface_recs;
}

=head2 move_edge_interface_circuits

=cut

sub move_edge_interface_circuits {
    my ($self, %args) = @_;
    my $orig_interface_id = $args{'orig_interface_id'};
    my $new_interface_id  = $args{'new_interface_id'};
    my $circuit_ids       = $args{'circuit_ids'};
    my $do_commit    = (defined($args{'do_commit'})) ? $args{'do_commit'} : 1;

    #sanity checks
    if(!defined($orig_interface_id)){
	    $self->_set_error("Must pass in orig_interface_id.");
        return;
    }
    if(!defined($new_interface_id)){
	    $self->_set_error("Must pass in new_interface_id.");
        return;
    }
    if($orig_interface_id == $new_interface_id){
	    $self->_set_error("Original interface and new interface must be different.");
        return;
    }

    my $orig_int_node = $self->get_node_by_interface_id( interface_id => $orig_interface_id ) || return;
    my $new_int_node  = $self->get_node_by_interface_id( interface_id => $new_interface_id ) || return;
    if($orig_int_node->{'name'} ne $new_int_node->{'name'}){
	    $self->_set_error("You can only move circuits between edge interfaces on the same node.");
        return;
    }
    my $dpid = $orig_int_node->{'dpid'};
   
    # first retrieve all of the edge records that we're moving 
    my $src_edge_interface_recs = $self->get_circuit_edge_interface_memberships(
        interface_id => $orig_interface_id,
        circuit_ids  => $circuit_ids
    ) || return;

    # stop right here if there are no circuits on this interface
    if(@$src_edge_interface_recs < 1){
	    $self->_set_error("No circuits on original interface, nothing to do.");
        return;
    }

    # now retrieve all the edge interface records we're moving to.
    # we'll use these to create a hash of vlan tags already used
    # so we know which circuits can not be moved 
    my $dst_edge_interface_recs = $self->get_circuit_edge_interface_memberships(
        interface_id => $new_interface_id 
    ) || return;
    my %used_vlans;
    foreach my $edge_int_rec (@$dst_edge_interface_recs){
        $used_vlans{$edge_int_rec->{'extern_vlan_id'}} = 1;
    }

    # start work
    $self->_start_transaction() if($do_commit);
    
    # now loop through each of the records we're moving 
    my $now = time();
    my %moved_circuits;
    my %unmoved_circuits;
    foreach my $edge_int_rec (@$src_edge_interface_recs){
        # first check to see if the vlan is already used
        if($used_vlans{$edge_int_rec->{'extern_vlan_id'}}){
            $unmoved_circuits{$edge_int_rec->{'circuit_id'}} = 1;
            next;
        }

        # set the old edge record's end_epoch time
        my $query = "UPDATE circuit_edge_interface_membership ".
                 "SET end_epoch = ? ".
                 "WHERE circuit_edge_id = ?";
        my $recs = $self->_execute_query($query, [
            $now,
            $edge_int_rec->{'circuit_edge_id'}
        ]);
        if(!$recs){
            $self->_rollback() if($do_commit);
            return;
        }

        # insert a new edge record with the new interface_id
        $query = "INSERT INTO circuit_edge_interface_membership (".
                 "  interface_id, ".
                 "  circuit_id, ".
                 "  start_epoch, ".
                 "  end_epoch, ".
                 "  extern_vlan_id ) ".
                 "VALUES( ?,?,?,?,? )";
        $recs = $self->_execute_query($query, [
            $new_interface_id, 
            $edge_int_rec->{'circuit_id'},
            $now,
            -1,
            $edge_int_rec->{'extern_vlan_id'},
        ]);
        if(!$recs){
            $self->_rollback() if($do_commit);
            return;
        }
        $moved_circuits{$edge_int_rec->{'circuit_id'}} = 1;
    }
    $self->_commit() if($do_commit);

    my @moved_circuits   = keys %moved_circuits;
    my @unmoved_circuits = keys %unmoved_circuits;

    return { 
        moved_circuits   => \@moved_circuits,
        unmoved_circuits => \@unmoved_circuits,
        dpid             => $dpid
    };
}

=head2 is_within_circuit_limit

=cut
sub is_within_circuit_limit {
    my ($self, %args) = @_;

    my $workgroup_id = $args{'workgroup_id'}; 

    my $str = "SELECT COUNT(*) as circuit_num ".
        "FROM circuit join circuit_instantiation on circuit_instantiation.circuit_id = circuit.circuit_id ".
        "WHERE end_epoch = -1 and workgroup_id = ? ".
        "AND circuit_instantiation.circuit_state != 'decom'";
    my $rows = $self->_execute_query($str, [$workgroup_id]);
    my $circuit_num = $rows->[0]{'circuit_num'};

    $str = "SELECT * from workgroup where workgroup_id = ?";
    $rows = $self->_execute_query($str, [$workgroup_id]);
    my $circuit_limit = $rows->[0]{'max_circuits'};

    if($circuit_num >= $circuit_limit) {
        return 0;
    }

    return 1;
}

=head2 is_within_circuit_endpoint_limit

=cut
sub is_within_circuit_endpoint_limit {
    my ($self, %args) = @_;

    my $workgroup_id = $args{'workgroup_id'};
    my $endpoint_num = $args{'endpoint_num'};

    my $str = "SELECT * from workgroup where workgroup_id = ?";
    my $rows = $self->_execute_query($str, [$workgroup_id]);
    my $circuit_endpoint_limit = $rows->[0]{'max_circuit_endpoints'};

    if($endpoint_num > $circuit_endpoint_limit) {
        return 0;
    }

    return 1;
}

=head2 is_within_mac_limit

=cut
sub is_within_mac_limit {
    my ($self, %args) = @_;

    my $mac_address   = $args{'mac_address'};
    my $interface     = $args{'interface'};
    my $node          = $args{'node'};
    my $workgroup_id  = $args{'workgroup_id'};

    my $new_mac_address_count = @$mac_address;

    #--- get the node_id and limit
    my $str = "select * from node where name = ?";
    my $rows = $self->_execute_query($str, [$node]);
    my $node_id        = $rows->[0]{'node_id'};
    my $node_mac_limit = $rows->[0]{'max_static_mac_flows'};  

    #--- get the number of mac addresses associated with the node
    $str = "SELECT COUNT(mac_address) AS mac_address_count FROM circuit_edge_mac_address ".
           " JOIN circuit_edge_interface_membership ".
           "   ON circuit_edge_mac_address.circuit_edge_id = circuit_edge_interface_membership.circuit_edge_id ".
           " JOIN circuit_instantiation ".
           "   ON circuit_edge_interface_membership.circuit_id = circuit_instantiation.circuit_id ".

           " JOIN interface ON circuit_edge_interface_membership.interface_id = interface.interface_id ".
           " JOIN node ON node.node_id = interface.node_id ".
           " WHERE node.node_id = ? ".
           "   AND circuit_instantiation.end_epoch = -1 ".
           "   AND circuit_instantiation.circuit_state != 'decom'";

    $rows = $self->_execute_query($str, [$node_id]);
    my $node_mac_address_count = $rows->[0]{'mac_address_count'};

    #--- get the number of mac addresses associated with the node by this workgroup
    $str = "SELECT COUNT(mac_address) AS mac_address_count FROM circuit_edge_mac_address ".
           " JOIN circuit_edge_interface_membership ".
           "   ON circuit_edge_mac_address.circuit_edge_id = circuit_edge_interface_membership.circuit_edge_id ".
           " JOIN circuit_instantiation ".
           "   ON circuit_edge_interface_membership.circuit_id = circuit_instantiation.circuit_id ".
           " JOIN interface ON circuit_edge_interface_membership.interface_id = interface.interface_id ".
           " JOIN node ON node.node_id = interface.node_id ".
           " JOIN circuit ON circuit_edge_interface_membership.circuit_id = circuit.circuit_id ".
           " WHERE node.node_id = ?".
           "   AND circuit.workgroup_id = ? ".
           "   AND circuit_instantiation.end_epoch = -1 ".
           "   AND circuit_instantiation.circuit_state != 'decom'";

    $rows = $self->_execute_query($str, [$node_id, $workgroup_id]);
    my $workgroup_node_mac_address_count = $rows->[0]{'mac_address_count'};

    #--- verify this won't cause us to go over the limit
    #if( ($new_mac_address_count + ($node_mac_address_count - $workgroup_node_mac_address_count)) > $node_mac_limit ){
    if( ($new_mac_address_count + $node_mac_address_count) > $node_mac_limit ){
        my $result = {
            verified => 0,
            explanation => "There are currently $node_mac_address_count mac addresses associated with node, $node. Adding $new_mac_address_count mac addresses to the node will cause it to exceed the nodes limit of $node_mac_limit."
        };
        return $result;
    } 

    #--- get the workgroup's per endpoint mac address limit
    $str = "select * from workgroup where workgroup_id = ?";
    $rows = $self->_execute_query($str, [$workgroup_id]);
    my $max_mac_per_endpoint = $rows->[0]{'max_mac_address_per_end'};

    #--- make sure the number of macs on the node falls withing the endpoint limit
    #if( ($new_mac_address_count + ($node_mac_address_count - $workgroup_node_mac_address_count)) > $max_mac_per_endpoint ){
    if( ($new_mac_address_count + $workgroup_node_mac_address_count) > $max_mac_per_endpoint ){
        my $result = {
            verified => 0,
            explanation => "There are currently $node_mac_address_count mac addresses associated with node, $node. Adding $new_mac_address_count mac addresses to the node will cause it to exceed the limit imposed on this workgroup of $max_mac_per_endpoint."
        };
        return $result;
    }   

    my $result = {
        verified => 1,
        explanation => undef
    };

    return $result;
}


=head2 update_remote_device

=cut

sub update_remote_device{
    my $self = shift;
    my %params = @_;

    my $node_id = $params{'node_id'};
    my $lat = $params{'lat'};
    my $lon = $params{'lon'};
    
    if(!defined($node_id) || !defined($lat) || !defined($lon)){
	return {error => "Node_id latitude and longitude are required"};
    }

    my $query = "select * from node where node_id = ?";
    my $node = $self->_execute_query($query, [$node_id])->[0];
    if(!defined($node)){
	return {error => "unable to find node with id: " . $node_id};
    }

    if($node->{'network_id'} == 1){
	return {error => "not a remote node!"};
    }

    if($lat > 90 || $lat < -90){
	return {error => "invalid latitue, must be between 90 and -90"};
    }

    if($lon > 180 || $lon < -180){
	return {error => "invalid longitude, must be between 180 and -180"};
    }

    my $res = $self->_execute_query("update node set latitude = ?, longitude = ? where node_id = ?",[ $lat, $lon, $node_id]);
    return {success => $res};
}

=head2 mac_hex2num

=cut
sub mac_hex2num {
  my $mac_hex = shift;

  $mac_hex =~ s/://g;

  $mac_hex = substr(('0'x12).$mac_hex, -12);
  my @mac_bytes = unpack("A2"x6, $mac_hex);

  my $mac_num = 0;
  foreach (@mac_bytes) {
    $mac_num = $mac_num * (2**8) + hex($_);
  }

  return $mac_num;
}

=head2 mac_num2hex

=cut
sub mac_num2hex {
  my $mac_num = shift;

  my @mac_bytes;
  for (1..6) {
    unshift(@mac_bytes, sprintf("%02x", $mac_num % (2**8)));
    $mac_num = int($mac_num / (2**8));
  }

  return join(':', @mac_bytes);
}

=head2 mac_validate

=cut
sub mac_validate {
    my $mac = shift;

    if( $mac =~ /^([0-9a-f]{2}([:-]|$)){6}$/i ){
        return 1;
    }

    return 0;
}

=head2 default vlan_range
 get/sets the default vlan range set on switches
=cut
sub default_vlan_range {
    my ($self, %args) = @_;

    $self->{'default_vlan_range'} = $args{'range'} if(defined($args{'range'}));

    return $self->{'default_vlan_range'};
}

=head2 is_topo_enabled

=cut

sub is_topo_enabled{
    my $self = shift;
    
    return 1 if(!defined($self->{'processes'}->{'topo'}));
    
    if($self->{'processes'}->{'topo'}->{'status'} eq 'enabled'){
        return 1;
    }else{
        return 0;
    }
    
}

=head2 is_fwdctl_enabled

=cut

sub is_fwdctl_enabled{
    my $self = shift;
    
    return 1 if(!defined($self->{'processes'}->{'fwdctl'}));

    if($self->{'processes'}->{'fwdctl'}->{'status'} eq 'enabled'){
        return 1;
    }else{
        return 0;
    }
}

=head2 is_vlan_stats_enabled

=cut

sub is_vlan_stats_enabled{
    my $self = shift;

    return 1 if(!defined($self->{'processes'}->{'vlan_stats'}));

    if($self->{'processes'}->{'vlan_stats'}->{'status'} eq 'enabled'){
        return 1;
    }else{
        return 0;
    }
}

=head2 is_nox_enabled

=cut

sub is_nox_enabled{
    my $self = shift;

    return 1 if(!defined($self->{'processes'}->{'nox'}));

    if($self->{'processes'}->{'nox'}->{'status'} eq 'enabled'){
        return 1;
    }else{
        return 0;
    }

}

=head2 is_notification_enabled

=cut

sub is_notification_enabled{
    my $self = shift;
    return 1 if(!defined($self->{'processes'}->{'notification'}));

    if($self->{'processes'}->{'notification'}->{'status'} eq 'enabled'){
        return 1;
    }else{
        return 0;
    }
}

=head2 is_watchdog_enabled

=cut

sub is_watchdog_enabled{
    my $self = shift;
    return 1 if(!defined($self->{'processes'}->{'watchdog'}));

    if($self->{'processes'}->{'watchdog'}->{'status'} eq 'enabled'){
        return 1;
    }else{
        return 0;
    }
}

=head2 is_nsi_enabled

=cut

sub is_nsi_enabled{
    my $self = shift;
    return 1 if(!defined($self->{'processes'}->{'nsi'}));

    if($self->{'processes'}->{'nsi'}->{'status'} eq 'enabled'){
        return 1;
    }else{
        return 0;
    }
}

=head2 is_fvd_enabled

=cut

sub is_fvd_enabled{
    my $self = shift;
    return 1 if(!defined($self->{'processes'}->{'fvd'}));

    if($self->{'processes'}->{'fvd'}->{'status'} eq 'enabled'){
        return 1;
    }else{
        return 0;
    }
}

=head2 is_traceroute_enabled

=cut

sub is_traceroute_enabled{
    my $self = shift;

    return 1 if(!defined($self->{'processes'}->{'traceroute'}));

    if($self->{'processes'}->{'traceroute'}->{'status'} eq 'enabled'){
        return 1;
    }else{
        return 0;
    }
}


return 1;
