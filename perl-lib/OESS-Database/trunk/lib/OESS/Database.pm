#!/usr/bin/perl
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

Version 1.0.0

=cut

our $VERSION = '1.0.0';

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
use File::ShareDir;
use Data::Dumper qw(Dumper);
use XML::Writer;

use OESS::Topology;

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

sub new{
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
				{mysql_auto_reconnect => 1,
				 }				
	                       );

    if (! $dbh){
	return undef;
    }

    $dbh->{'mysql_auto_reconnect'}   = 1;

    $self->{'snapp_config_location'} = $snapp_config_location;
    $self->{'dbh'}                   = $dbh;
    $self->{'oscars'} = $oscars_info;

    if (! defined $self->{'topo'}){
	$self->{'topo'} = OESS::Topology->new(db => $self);
    }

    
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

=back 

=cut

sub update_circuit_state{
    my $self = shift;
    my %args = @_;

    my $circuit_id  = $args{'circuit_id'};
    my $old_state   = $args{'old_state'};
    my $new_state   = $args{'new_state'};
    my $user_id     = $args{'modified_by_user_id'};

    $self->_start_transaction();

    my $details = $self->get_circuit_details(circuit_id => $circuit_id);

    if (! defined $details){
	$self->_set_error("Unable to find circuit information for circuit $circuit_id");
	return undef;
    }

    my $bandwidth = $details->{'bandwidth'};

    my $query = "update circuit_instantiation set end_epoch = unix_timestamp(NOW()) " .
	" where circuit_id = ? and end_epoch = -1 and circuit_state = ?";
    
    my $result = $self->_execute_query($query, [$circuit_id, $old_state]);

    if (! defined $result){
	$self->_set_error("Unable to decom old circuit instantiation.");
	return undef;
    }

    $query = "insert into circuit_instantiation (circuit_id, end_epoch, start_epoch, reserved_bandwidth_mbps, circuit_state, modified_by_user_id) values (?, -1, unix_timestamp(now()), ?, ?, ?)";

    $result = $self->_execute_query($query, [$circuit_id, $bandwidth, $new_state, $user_id]);

    if (! defined $result){
	$self->_set_error("Unable to create new circuit instantiation record.");
	return undef;
    }

    $self->_commit();

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
	return undef;
    }

    $self->_commit();

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

sub switch_circuit_to_alternate_path {
    my $self = shift;
    my %args = @_;

    my $query;

    my $circuit_id     = $args{'circuit_id'};
    
    if (! $self->circuit_has_alternate_path(circuit_id => $circuit_id ) ){
	$self->_set_error("Circuit $circuit_id has no alternate path, refusing to try to switch to alternate.");
	return undef;
    }

    $self->_start_transaction();

    # grab the path id of the one we're going to switch to
    $query = "select path_instantiation.path_id from path " . 
	     " join path_instantiation on path.path_id = path_instantiation.path_id " .
	     " where path_instantiation.path_state = 'available' and path_instantiation.end_epoch = -1 " .
	     " and path.circuit_id = ?";

    my $results = $self->_execute_query($query, [$circuit_id]);

    if (! defined $results || @$results < 1){
	$self->_set_error("Unable to find path_id for alternate path.");
	return undef;
    }

    my $new_active_path_id = @$results[0]->{'path_id'};


    # grab the path_id of the one we're switching away from
    $query = "select path_instantiation.path_id, path_instantiation.internal_vlan_id from path " . 
	     " join path_instantiation on path.path_id = path_instantiation.path_id " .
	     " where path_instantiation.path_state = 'active' and path_instantiation.end_epoch = -1 " .
	     " and path.circuit_id = ?";

    $results = $self->_execute_query($query, [$circuit_id]);

    if (! defined $results || @$results < 1){
	$self->_set_error("Unable to find path_id for current path.");
	return undef;
    }

    my $old_active_path_id   = @$results[0]->{'path_id'};
    my $old_active_path_vlan = @$results[0]->{'internal_vlan_id'};
 
    # decom the current path instantiation
    $query = "update path_instantiation set path_instantiation.end_epoch = unix_timestamp(NOW()) " .
	     " where path_instantiation.path_id = ? and path_instantiation.end_epoch = -1";

    my $success = $self->_execute_query($query, [$old_active_path_id]);

    if (! $success ){
	$self->_set_error("Unable to change path_instantiation of current path to inactive.");
	return undef;
    }


    # create a new path instantiation of the old path
    $query = "insert into path_instantiation (path_id, start_epoch, end_epoch, path_state, internal_vlan_id) " .
	     " values (?, unix_timestamp(NOW()), -1, 'available', ?)";
    
    $success = $self->_execute_query($query, [$old_active_path_id, $old_active_path_vlan]);

    if (! defined $success){
	$self->_set_error("Unable to create new available path based on old instantiation.");
	return undef;
    }


    # at this point, the old path instantiation has been decom'd by virtue of its end_epoch
    # being set and another one has been created in 'available' state based on it.

    # now let's change the state of the old available one to active
    $query = "update path_instantiation set path_state = 'active' where path_id = ? and end_epoch = -1";

    $success = $self->_execute_query($query, [$new_active_path_id]);

    if (! $success){
	$self->_set_error("Unable to change state to active in alternate path.");
	return undef;
    }

    $self->_commit();

    return 1;
}

=head2 circuit_has_alternate_path

Returns whether or not the circuit given has an alternate path available. Presently this only checks to see
if an available path instantiation is available, though it should also in the future determine whether that path
is even valid based on port / link statuses along the path.

=over

=item circuit_id

The internal MySQL primary key int identifier for this circuit.

=back

=cut

sub circuit_has_alternate_path{
    my $self = shift;
    my %args = @_;

    my $circuit_id = $args{'circuit_id'};

    my $query  = "select 1 from path " . 
	         " join path_instantiation on path.path_id = path_instantiation.path_id " .
		 "  and path_instantiation.path_state = 'available' and path_instantiation.end_epoch = -1 " .
	         " where circuit_id = ?";

    my $result = $self->_execute_query($query, [$circuit_id]);

    if (! defined $result){
	$self->_set_error("Internal error determing if circuit has available alternate path.");
	return undef;
    }

    if (@$result > 0){
	return 1;
    }

    return 0;
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

    
    my $query = "select circuit.name, circuit.circuit_id from circuit " .
	        " join circuit_instantiation on circuit.circuit_id = circuit_instantiation.circuit_id " .
		"  and circuit_instantiation.end_epoch = -1 and circuit_instantiation.circuit_state = 'active' " .
		" join path on path.circuit_id = circuit.circuit_id " .
		" join path_instantiation on path_instantiation.path_id = path.path_id " .
		"  and path_instantiation.end_epoch = -1 and path_instantiation.path_state = 'active' " .
		" join link_path_membership on link_path_membership.path_id = path.path_id " . 
		" join link on link.link_id = link_path_membership.link_id " . 
		"  where link.link_id = ? ";

    my @circuits;

    my $results = $self->_execute_query($query, [$link]);

    if (! defined $results){
	return undef;
    }

    foreach my $circuit (@$results){
	push(@circuits, {"name" => $circuit->{'name'},
			 "id"   => $circuit->{'circuit_id'}
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

    my $query = "select circuit.name from circuit join circuit_edge_interface_membership " .
	        " on circuit.circuit_id = circuit_edge_interface_membership.circuit_id " . 		
		" where circuit_edge_interface_membership.interface_id = ? " . 
		"  and circuit_edge_interface_membership.extern_vlan_id = ? " .
		"  and circuit_edge_interface_membership.end_epoch = -1";

    my $result = $self->_execute_query($query, [$interface_id, $vlan_tag]);

    if (! defined $result){
	$self->_set_error("Internal error while finding available external vlan tags.");
	return undef;
    }

    if (@$result > 0){
	return 0;
    }

    return 1;
}

=head2 get_user_by_id

=cut

sub get_user_by_id{
    my $self = shift;
    my %args = @_;

    my $user_id = $args{'user_id'};
    if(!defined($user_id)){
	$self->_set_error("user_id was not defined");
	return undef;
    }

    my $query = "select * from user,remote_auth where user.user_id = remote_auth.user_id and user.user_id = ?";
    return $self->_execute_query($query,[$user_id]);
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
	return undef;
    }
    my $query = "select user_id from user where given_names = ?";

    my $result = $self->_execute_query($query, [$name]);

    if (! defined $result || @$result < 1){
	$self->_set_error("Unable to find user $name");
	return undef;
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
	return undef;
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
                                   ) or return undef;

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

    my $nodes = $self->_execute_query("select node.name from node,node_instantiation where node.node_id = node_instantiation.node_id and node_instantiation.end_epoch = -1",[]);
    
    return $nodes;   
}

=head2 add_link

=cut

sub add_link{
    my $self = shift;
    my %args = @_;
    
    if(!defined($args{'name'})){
	$self->_set_error("No Name was defined");
	return undef;
    }

    my $res = $self->_execute_query("insert into link (name, remote_urn) VALUES (?, ?)",
				    [$args{'name'}, $args{'remote_urn'}]);

    if(defined($res)){
	return $res;
    }

    $self->_set_error("Problem creating link");
    return undef;
    
}

=head2 create_link_instantiation

=cut

sub create_link_instantiation{
    my $self = shift;
    my %args = @_;

    if(!defined($args{'link_id'})){
	$self->_set_error("Link ID was not specified");
	return undef;
    }

    if(!defined($args{'state'})){
	$args{'state'} = "Unknown";
    }

    if(!defined($args{'interface_a_id'})){
	$self->_set_error("Interface A was not specified");
	return undef;
    }

    if(!defined($args{'interface_z_id'})){
	$self->_set_error("Interface Z was not specified");
	return undef;
    }

    my $res = $self->_execute_query("insert into link_instantiation (link_id,end_epoch,start_epoch,link_state,interface_a_id,interface_z_id) VALUES (?,-1,UNIX_TIMESTAMP(NOW()),?,?,?)",[$args{'link_id'},$args{'state'},$args{'interface_a_id'},$args{'interface_z_id'}]);

    if(!defined($res)){
	return undef;
    }

    return $res;


}

=head2 get_edge_links

=cut

sub get_edge_links{
    my $self = shift;
    my $reserved_bw = shift;
    my $links = $self->_execute_query("select link.name, link_instantiation.interface_a_id, link_instantiation.interface_z_id, node_a.name as node_a_name,node_b.name as node_b_name,least(interface_inst_a.capacity_mbps,interface_inst_b.capacity_mbps) as link_capacity, sum(reserved_bandwidth_mbps) as reserved_bw_mbps from link_instantiation,interface as interface_a,interface as interface_b,node as node_a, node as node_b, interface_instantiation as interface_inst_a, interface_instantiation as interface_inst_b,link left join link_path_membership on link_path_membership.link_id=link.link_id and link_path_membership.end_epoch=-1  left join path on link_path_membership.path_id=path.path_id left join path_instantiation on path_instantiation.path_id=path.path_id and path_instantiation.end_epoch=-1 and path_state='active' left join circuit on path.circuit_id=circuit.circuit_id left join circuit_instantiation on circuit.circuit_id=circuit_instantiation.circuit_id and circuit_state='active' where link.link_id=link_instantiation.link_id and  interface_inst_a.end_epoch=-1 and interface_inst_a.interface_id=interface_a.interface_id and link_instantiation.end_epoch=-1 and  interface_a.node_id=node_a.node_id and interface_b.node_id=node_b.node_id and link_instantiation.interface_a_id=interface_a.interface_id and link_instantiation.interface_z_id=interface_b.interface_id and interface_inst_b.end_epoch=-1 and interface_inst_b.interface_id=interface_b.interface_id and interface_a.operational_state = 'up' and interface_b.operational_state = 'up' group by link.link_id having (link_capacity-(IFNULL(reserved_bw_mbps,0)))>?",[$reserved_bw]);

    return $links;

}


=head2 get_node_interfaces

Returns an array of hashes containing base information about edge interfaces that are currently up on the given node. If a workgroup
id is given, it limits the intefaces to those presently available to that workgroup.

=over

=item node

The name of the node to query.

=item workgroup_id (optional)

The internal MySQL primary key int identifier for this workgroup.

=back

=cut

sub get_node_interfaces {
    my $self = shift;
    my %args = @_;

    my $node_name    = $args{'node'};
    my $workgroup_id = $args{'workgroup_id'};

    my @query_args;

    push(@query_args, $node_name);

    my $query = "select interface.name, interface.description, interface.interface_id from interface " .
	        " join node on node.name = ? and node.node_id = interface.node_id " .
		" join interface_instantiation on interface_instantiation.end_epoch = -1 and interface_instantiation.interface_id = interface.interface_id ";

    if (defined $workgroup_id){
	push(@query_args, $workgroup_id);
	$query .= " join workgroup_interface_membership on workgroup_interface_membership.interface_id = interface.interface_id ";
    }

    $query .= " where interface.operational_state = 'up' and interface.role != 'trunk' ";
		
    if (defined $workgroup_id){
	$query .= " and workgroup_interface_membership.workgroup_id = ?";
    }

    my $rows = $self->_execute_query($query, \@query_args);

    my @results;

    foreach my $row (@$rows){
	push(@results, {"name"         => $row->{'name'},
			"description"  => $row->{'description'},
			"interface_id" => $row->{'interface_id'}
	               }
	    );
    }

    return \@results;

}

=head2 get_map_layers

Returns information such as name, capacity, position, and status about the current network layout including nodes and the links between them.

=cut

sub get_map_layers {
    my $self = shift;
    my %args = @_;

    my $dbh = $self->{'dbh'};

    # grab only the local network
    my $query = "select network.longitude as network_long, network.latitude as network_lat, network.name as network_name, " .
	" node.longitude as node_long, node.latitude as node_lat, node.name as node_name, node.node_id as node_id, " .
	" to_node.name as to_node, " .
	" link.name as link_name, if(intA.operational_state = 'up' && intB.operational_state = 'up', 'up', 'down') as link_state, if(int_instA.capacity_mbps > int_instB.capacity_mbps, int_instB.capacity_mbps, int_instA.capacity_mbps) as capacity, link.link_id as link_id " .
	"from node " .
	"  join node_instantiation on node.node_id = node_instantiation.node_id and node_instantiation.end_epoch = -1 and node_instantiation.admin_state = 'active' " .
	" join network on node.network_id = network.network_id and network.is_local = 1 " . 

	" join interface intA on intA.node_id = node.node_id " .
	" join interface_instantiation int_instA on int_instA.interface_id = intA.interface_id " .
	"  and int_instA.end_epoch = -1 " .

	" left join link_instantiation on link_instantiation.end_epoch = -1 and link_instantiation.link_state = 'active' " .
	"  and intA.interface_id in (link_instantiation.interface_a_id, link_instantiation.interface_z_id) " .
	" left join link on link.link_id = link_instantiation.link_id " .

	" left join interface intB on intB.interface_id != intA.interface_id and intB.interface_id in (link_instantiation.interface_a_id, link_instantiation.interface_z_id) " .
	" left join interface_instantiation int_instB on int_instB.interface_id = intB.interface_id " .
	"  and int_instB.end_epoch = -1 " .

	" left join node to_node on to_node.node_id != node.node_id and to_node.node_id = intB.node_id";

#	"from link " .
#	" join link_instantiation on link_instantiation.link_id = link.link_id and link_instantiation.end_epoch = -1 and link_instantiation.link_state = 'active' " .
#	" join interface_instantiation int_instA on int_instA.interface_id = link_instantiation.interface_a_id " .
#	"  and int_instA.end_epoch = -1 " .
#	" join interface_instantiation int_instB on int_instB.interface_id = link_instantiation.interface_z_id " .
#	"  and int_instB.end_epoch = -1 " .
#	" join interface intA on int_instA.interface_id = intA.interface_id " .
#	" join interface intB on int_instB.interface_id = intB.interface_id " .
#	" right join node on node.node_id in (intA.node_id, intB.node_id) " .
#	"  join node_instantiation on node.node_id = node_instantiation.node_id and node_instantiation.end_epoch = -1 and node_instantiation.admin_state = 'active' " .
#	" join network on node.network_id = network.network_id and network.is_local = 1 " . 
#	" join node to_node on to_node.node_id != node.node_id and to_node.node_id in (intA.node_id, intB.node_id)";
    
    my $sth = $self->_prepare_query($query) or return undef;

    $sth->execute();

    my $networks;

    while (my $row = $sth->fetchrow_hashref()){

	my $network_name = $row->{'network_name'};
	my $node_name    = $row->{'node_name'};

	$networks->{$network_name}->{'meta'} = {"network_long" => $row->{'network_long'},
						"network_lat"  => $row->{'network_lat'},
						"network_name" => $network_name,
						"local"        => 1
	};
	
	$networks->{$network_name}->{'nodes'}->{$node_name} = {"node_name"    => $node_name,
							       "node_lat"     => $row->{'node_lat'},
							       "node_long"    => $row->{'node_long'},
							       "node_id"      => $row->{'node_id'}
							   };

	# make sure we have an array even if we never get any links for this node
	if (! exists $networks->{$network_name}->{'links'}->{$node_name}){
	    $networks->{$network_name}->{'links'}->{$node_name} = [];
	}

	# possible that this row doesn't contain any link information on account of left joins (could be standalone node)
	if ($row->{'link_name'}){
	    push(@{$networks->{$network_name}->{'links'}->{$node_name}}, {"link_name"   => $row->{'link_name'},
									  "link_state"  => $row->{'link_state'},
									  "capacity"    => $row->{'capacity'},
									  "to"          => $row->{'to_node'},
									  "link_id"     => $row->{'link_id'}
		                                                          }	
		);		
	}
    }


    # now grab the foreign networks (no instantiations, is_local = 0)
    $query = "select network.longitude as network_long, network.latitude as network_lat, network.name as network_name, network.network_id as network_id, " .
	" node.longitude as node_long, node.latitude as node_lat, node.name as node_name, node.node_id as node_id " .
	" from network " .
	"  join node on node.network_id = network.network_id " . 
	" where network.is_local = 0";

    my $rows = $self->_execute_query($query, []);
	
    foreach my $row (@$rows){

	my $node_id      = $row->{'node_id'};
	my $network_id   = $row->{'network_id'};
	my $network_name = $row->{'network_name'};
	my $node_name    = $row->{'node_name'};

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
							   };

    }

    my $results = [];

    foreach my $network_name (keys %$networks){

	push (@$results, $networks->{$network_name});

    }

    return $results;

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

    my $events = [];

    my $query = "select remote_auth.auth_name, concat(user.given_names, ' ', user.family_name) as full_name, " .
	        " from_unixtime(registration_epoch) as registration_time, from_unixtime(activation_epoch) as activation_time, " .
		" scheduled_action.circuit_layout, " .
		" from_unixtime(scheduled_action.completion_epoch) as completion_time " .
		" from scheduled_action " .
		" join user on user.user_id = scheduled_action.user_id " .
		" join remote_auth on remote_auth.user_id = user.user_id " .
		" where scheduled_action.circuit_id = ?"; 

    my $sth = $self->_prepare_query($query);

    $sth->execute($circuit_id) or die "Failed execute: $DBI::errstr";

    while (my $row = $sth->fetchrow_hashref()){
	push (@$events, {"username"  => $row->{'auth_name'},
			 "fullname"  => $row->{'full_name'},
			 "scheduled" => $row->{'registration_time'},
			 "activated" => $row->{'activation_time'},
			 "layout"    => $row->{'circuit_layout'},
			 "completed" => $row->{'completion_time'}
	      });
    }

    return $events;
}


=head2 get_circuit_network_events

Returns an array of hashes containing information about events for this circuit that have were network driven, such as links going down or
ports and nodes dropping off the network.

=over

=item circuit_id

The internal MySQL primary key int identifier for this circuit.

=back

=cut

sub get_circuit_network_events {
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
	     " join remote_auth on remote_auth.user_id = user.user_id " .
	     "where circuit.circuit_id = ?";

    my $results = $self->_execute_query($query, [$circuit_id]);

    if (! defined $results){
	$self->_set_error("Internal error fetching circuit instantiation events.");
	return undef;
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
    my %args = @_;

    my $workgroups;

    my $results = $self->_execute_query("select workgroup_id, name from workgroup");

    if (! defined $results){
	$self->_set_error("Internal error while fetching workgroups");
	return undef;
    }

    foreach my $workgroup (@$results){
	push (@$workgroups, {workgroup_id => $workgroup->{'workgroup_id'},
			     name         => $workgroup->{'name'}
	      });
    }

    return $workgroups;
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
	return undef;
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
	return undef;
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
	        " from workgroup " . 
	        " join user_workgroup_membership on user_workgroup_membership.workgroup_id = workgroup.workgroup_id " .
		" join user on user.user_id = user_workgroup_membership.user_id " .
		" join remote_auth on remote_auth.user_id = user.user_id " .
		"  and remote_auth.auth_name = ?";

    my $results = $self->_execute_query($query, [$auth_name]);

    if (! defined $results){
	$self->_set_error("Internal error fetching user workgroups.");
	return undef;
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

=head2 get_workgroup_acls

Returns an array of hashes containing node and interface information for what edge ports are allowed to be used by this workgroup.

=over

=item workgroup_id

The internal MySQL primary key int identifier for this workgroup.

=back

=cut

sub get_workgroup_acls {
    my $self = shift;
    my %args = @_;

    my $workgroup_id = $args{'workgroup_id'};

    my $acls;

    my $query = "select interface.name as int_name, interface.interface_id, node.name as node_name, node.node_id " .
	        " from workgroup " .
		"  join workgroup_interface_membership on workgroup.workgroup_id = workgroup_interface_membership.workgroup_id " .
		"  join interface on interface.interface_id = workgroup_interface_membership.interface_id " .
		"  join interface_instantiation on interface.interface_id = interface_instantiation.interface_id " .
		"    and interface_instantiation.end_epoch = -1" . 
		"  join node on node.node_id = interface.node_id " .
		"  join node_instantiation on node.node_id = node_instantiation.node_id " .
		"    and node_instantiation.end_epoch = -1 " .
		" where workgroup.workgroup_id = ?";

    my $results = $self->_execute_query($query, [$workgroup_id]);

    if (! defined $results){
	$self->_set_error("Internal error fetching workgroup acls.");
	return undef;
    }

    foreach my $row (@$results){
	push(@$acls, {"interface_id"   => $row->{'interface_id'},
		      "interface_name" => $row->{'int_name'},
		      "node_id"        => $row->{'node_id'},
		      "node_name"      => $row->{'node_name'}
	     });
    }

    return $acls;
}

=head2 add_workgroup_acl

Adds a new ACL for a workgroup. This allows users of the workgroup the capability to use a given node / port combination as an edge for their circuits.

=over

=item interface_id

The internal MySQL primary key int identifier for the interface.

=item workgroup_id

The internal MySQL primary key int identifier for this workgroup.

=back

=cut

sub add_workgroup_acl {
    my $self = shift;
    my %args = @_;

    my $interface_id = $args{'interface_id'};
    my $workgroup_id = $args{'workgroup_id'};


    my $query = "select 1 from workgroup_interface_membership where workgroup_id = ? and interface_id = ?";
    
    my $results = $self->_execute_query($query, [$workgroup_id, $interface_id]);

    if (@$results > 0){
	$self->_set_error("Interface already belongs to this workgroup's edge ports.");
	return undef;
    }

    $query = "insert into workgroup_interface_membership (workgroup_id, interface_id) values (?, ?)";

    my $success = $self->_execute_query($query, [$workgroup_id, $interface_id]);
    
    if (! defined $success ){
	$self->_set_error("Internal error while adding edge port to workgroup ACL.");
	return undef;
    }

    return 1;
}

=head2 remove_workgroup_acl

Removes an edge port from a workgroup's ACL. This removes the ability for users of that workgroup to use the edge port as an endpoint for circuits.

=over

=item interface_id

The internal MySQL primary key int identifier for the interface.

=item workgroup_id

The internal MySQL primary key int identifier for this workgroup.

=back

=cut

sub remove_workgroup_acl {
    my $self = shift;
    my %args = @_;

    my $interface_id = $args{'interface_id'};
    my $workgroup_id = $args{'workgroup_id'};

    my $query = "select 1 from workgroup_interface_membership where workgroup_id = ? and interface_id = ?";
    
    my $results = $self->_execute_query($query, [$workgroup_id, $interface_id]);

    if (@$results < 1){
	$self->_set_error("Interface does not belong to this workgroup's edge ports.");
	return undef;
    }

    $query = "delete from workgroup_interface_membership where workgroup_id = ? and interface_id = ?";

    my $success = $self->_execute_query($query, [$workgroup_id, $interface_id]);
    
    if (! defined $success ){
	$self->_set_error("Internal error while removing edge port from workgroup ACL.");
	return undef;
    }

    return 1;
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

    my $new_wg_id = $self->_execute_query("insert into workgroup (name) values (?)", [$name]);

    if (! defined $new_wg_id){
	$self->_set_error("Unable to add new workgroup");
	return undef;
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
	return undef;
    }

    foreach my $row (@$results){

	my $data = {'first_name'    => $row->{'given_names'},
		    'family_name'   => $row->{'family_name'},
		    'email_address' => $row->{'email'},
		    'user_id'       => $row->{'user_id'},
		    'auth_name'     => []
	};
	
	my $auth_results = $self->_execute_query("select auth_name from remote_auth where user_id = ?", [$row->{'user_id'}]);

	if (! defined $auth_results){
	    $self->_set_error("Internal error fetching remote_auth");
	    return undef;
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

    my $users;

    my $results = $self->_execute_query("select user.* from user " . 
					" join user_workgroup_membership on user.user_id = user_workgroup_membership.user_id " .
					" where user_workgroup_membership.workgroup_id = ?" . 
					" order by given_names ",
					[$workgroup_id]
	                                );

    if (! defined $results){
	$self->_set_error("Internal error fetching users.");
	return undef;
    }

    foreach my $row (@$results){

	my $data = {'first_name'    => $row->{'given_names'},
		    'family_name'   => $row->{'family_name'},
		    'email_address' => $row->{'email'},
		    'user_id'       => $row->{'user_id'},
		    'auth_name'     => []
	};
	
	my $auth_results = $self->_execute_query("select auth_name from remote_auth where user_id = ?", [$row->{'user_id'}]);

	if (! defined $auth_results){
	    $self->_set_error("Internal error fetching remote_auth");
	    return undef;
	}

	foreach my $auth_row (@$auth_results){
	    push(@{$data->{'auth_name'}}, $auth_row->{'auth_name'});
	}
	
	push(@$users, $data);

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

    if ($self->is_user_in_workgroup(user_id => $user_id, workgroup_id => $workgroup_id)){
	$self->_set_error("User is already a member of this workgroup.");
	return undef;
    }

    my $result = $self->_execute_query("insert into user_workgroup_membership (workgroup_id, user_id) values (?, ?)",
				       [$workgroup_id, $user_id]
	);
    
    if (! defined $result){
	$self->_set_error("Unable to create user workgroup membership.");
	return undef;
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
	return undef;
    }


    $result = $self->_execute_query("delete from user_workgroup_membership where workgroup_id = ? and user_id = ?",
				    [$workgroup_id, $user_id]
	);
    
    if (! defined $result){
	$self->_set_error("Unable to delete user workgroup membership.");
	return undef;
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

    if ($given_name =~ /^system$/ || $family_name =~ /^system$/){
	$self->_set_error("Cannot use 'system' as a username.");
	return undef;
    }

    $self->_start_transaction();

    my $query = "insert into user (email, given_names, family_name) values (?, ?, ?)";

    my $user_id = $self->_execute_query($query, [$email, $given_name, $family_name]);

    if (! defined $user_id){
	$self->_set_error("Unable to create new user.");
	return undef;
    }

    foreach my $name (@$auth_names){
	$query = "insert into remote_auth (auth_name, user_id) values (?, ?)";

	$self->_execute_query($query, [$name, $user_id]);
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
	return undef;
    }

    # first let's make sure we aren't deleting system
    if ($info->[0]->{'given_names'} =~ /^system$/i){
	$self->_set_error("Cannot delete the system user.");
	return undef;
    }

    # okay, looks good. Let's delete this user
    $self->_start_transaction();

    if (! defined $self->_execute_query("delete from user_workgroup_membership where user_id = ?", [$user_id])) {
	$self->_set_error("Internal error delete user.");
	return undef;
    }

    if (! defined $self->_execute_query("delete from remote_auth where user_id = ?", [$user_id])){
	$self->_set_error("Internal error delete user.");
	return undef;
    }

    if (! defined $self->_execute_query("delete from user where user_id = ?", [$user_id])){
	$self->_set_error("Internal error delete user.");
	return undef;
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

    if ($given_name =~ /^system$/ || $family_name =~ /^system$/){
	$self->_set_error("User 'system' is reserved.");
	return undef;
    }

    $self->_start_transaction();

    my $query = "update user set email = ?, given_names = ?, family_name = ? where user_id = ?";

    my $result = $self->_execute_query($query, [$email, $given_name, $family_name, $user_id]);

    if (! defined $user_id || $result == 0){
	$self->_set_error("Unable to edit user - does this user actually exist?");
	return undef;
    }

    $self->_execute_query("delete from remote_auth where user_id = ?", [$user_id]);

    foreach my $name (@$auth_names){
	$query = "insert into remote_auth (auth_name, user_id) values (?, ?)";

	$self->_execute_query($query, [$name, $user_id]);
    }

    $self->_commit();

    return 1;
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

    my $dbh = $self->{'dbh'};

    my @to_pass;

    my $query = "select circuit.name, circuit.description, circuit.circuit_id, " .
	" circuit_instantiation.reserved_bandwidth_mbps, circuit_instantiation.circuit_state, " .
	" path.path_type, interface.name as int_name, node.name as node_name " .
	"from circuit " .
	" join circuit_instantiation on circuit.circuit_id = circuit_instantiation.circuit_id " .
	"  and circuit_instantiation.end_epoch = -1 and circuit_instantiation.circuit_state != 'decom' " .
	" join path on path.circuit_id = circuit.circuit_id " .
	"  join path_instantiation on path_instantiation.path_id = path.path_id " .
	"    and path_instantiation.end_epoch = -1 and path_instantiation.path_state in ('active', 'deploying') " .
	" join circuit_edge_interface_membership on circuit_edge_interface_membership.circuit_id = circuit.circuit_id " .
	"  and circuit_edge_interface_membership.end_epoch = -1 " .
	" join interface on interface.interface_id = circuit_edge_interface_membership.interface_id " .
	"  left join interface_instantiation on interface.interface_id = interface_instantiation.interface_id " .
	"    and interface_instantiation.end_epoch = -1" . 
	" join node on node.node_id = interface.node_id " .
	"  left join node_instantiation on node.node_id = node_instantiation.node_id " .
	"    and node_instantiation.end_epoch = -1 ";

    if ($workgroup_id){
	$query .= " where circuit.workgroup_id = ?";
	push(@to_pass, $workgroup_id);
    }

    my $rows = $self->_execute_query($query, \@to_pass);

    if (! defined $rows){
	$self->_set_error("Internal error while getting circuits.");
	return undef;
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
					'endpoints'   => []
	    };
	    
	}
	
	push(@{$circuits->{$circuit_id}->{'endpoints'}}, {'node'      => $row->{'node_name'},
							  'interface' => $row->{'int_name'}
							  
	     });
	
    }
    
    
    foreach my $circuit_id (keys %$circuits){
	
	push (@$results, $circuits->{$circuit_id});
	
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
	return undef;
    }

    if (@$result > 0){
	my $circuit_id = @$result[0]->{'circuit_id'};
	
	return $self->get_circuit_details(circuit_id => $circuit_id);
    }

    return 0;
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

    my $details;

    # basic circuit info
    my $query = "select circuit.name, circuit.description, circuit.circuit_id, " .
	" circuit_instantiation.reserved_bandwidth_mbps, circuit_instantiation.circuit_state  , " .
        " pr_pi.internal_vlan_id as pri_path_internal_tag, bu_pi.internal_vlan_id as bu_path_internal_tag, " .
	" if(bu_pi.path_state = 'active', 'backup', 'primary') as active_path " .
	"from circuit " .
	" join circuit_instantiation on circuit.circuit_id = circuit_instantiation.circuit_id " .
	"  and circuit_instantiation.end_epoch = -1 " .
	"join path as pr_p on pr_p.circuit_id = circuit.circuit_id and pr_p.path_type = 'primary' " . 
	"join path_instantiation as pr_pi on pr_pi.path_id = pr_p.path_id and pr_pi.end_epoch = -1 ".
        " left join path as bu_p on bu_p.circuit_id = circuit.circuit_id and bu_p.path_type = 'backup' " .        
        " left join path_instantiation as bu_pi on bu_pi.path_id = bu_p.path_id and bu_pi.end_epoch = -1 ".

	" where circuit.circuit_id = ?";

    my $sth = $self->_prepare_query($query) or return undef;

    $sth->execute($circuit_id);

    if (my $row = $sth->fetchrow_hashref()){
	$details = {'circuit_id'             => $circuit_id,
		    'name'                   => $row->{'name'},
		    'description'            => $row->{'description'},
		    'bandwidth'              => $row->{'reserved_bandwidth_mbps'},
		    'state'                  => $row->{'circuit_state'},
		    'pri_path_internal_tag'  => $row->{'pri_path_internal_tag'},
		    'bu_path_internal_tag'   => $row->{'bu_path_internal_tag'},
		    'active_path'            => $row->{'active_path'}
	           };
    }

    $details->{'endpoints'}    = $self->get_circuit_endpoints(circuit_id => $circuit_id) || [];

    $details->{'links'}        = $self->get_circuit_links(circuit_id => $circuit_id) || [];

    $details->{'backup_links'} = $self->get_circuit_links(circuit_id => $circuit_id,
							  type       => 'backup'
	                                                 ) || [];

    return $details;
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

    my $query = "select interface.name as int_name, node.name as node_name, interface.interface_id, node.node_id as node_id, circuit_edge_interface_membership.extern_vlan_id, interface.port_number, network.is_local, interface.role, urn.urn " .
	" from interface " .
	" join circuit_edge_interface_membership on circuit_edge_interface_membership.circuit_id = ? " .
	"  and circuit_edge_interface_membership.end_epoch = -1 " .
	"  and interface.interface_id = circuit_edge_interface_membership.interface_id " .
	" left join interface_instantiation on interface.interface_id = interface_instantiation.interface_id " .
	"    and interface_instantiation.end_epoch = -1" . 
	" join node on node.node_id = interface.node_id " .
	"  left join node_instantiation on node.node_id = node_instantiation.node_id " .
	"    and node_instantiation.end_epoch = -1 " .
	" join network on network.network_id = node.network_id ".
        " left join urn on interface.interface_id=urn.interface_id" .
        " group by interface.interface_id ";

    my $sth = $self->_prepare_query($query) or return undef;

    $sth->execute($args{'circuit_id'});

    my $results;

    while (my $row = $sth->fetchrow_hashref()){
	push (@$results, {'node'      => $row->{'node_name'},
			  'interface' => $row->{'int_name'},
			  'tag'       => $row->{'extern_vlan_id'},
			  'node_id'   => $row->{'node_id'},
			  'port_no'   => $row->{'port_number'},
			  'local'     => $row->{'is_local'},
			  'role'      => $row->{'role'},
			  'urn'       => $row->{'urn'}
	                 }
	    );
    }

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

    my $query = "select link.name, node_a.name as node_a, if_a.name as interface_a, if_a.port_number as port_no_a, node_z.name as node_z, if_z.name as interface_z, if_z.port_number as port_no_z from link " .
	" join link_path_membership on link_path_membership.link_id = link.link_id " .
	"  and link_path_membership.end_epoch = -1 " .
        " join link_instantiation link_inst on link.link_id = link_inst.link_id and link_inst.end_epoch = -1".
	" join path on path.path_id = link_path_membership.path_id and path.circuit_id = ? " .
	"  and path.path_type = ? ".
	" join interface if_a on link_inst.interface_a_id = if_a.interface_id ".
 	" join interface if_z on link_inst.interface_z_id = if_z.interface_id ". 
	" join node node_a on if_a.node_id = node_a.node_id ".
	" join node node_z on if_z.node_id = node_z.node_id ";

    my $sth = $self->_prepare_query($query) or return undef;

    $sth->execute($args{'circuit_id'},
		  $args{'type'}
	         );

    my $results;

    while (my $row = $sth->fetchrow_hashref()){
	push (@$results, { name        =>  $row->{'name'},
			   node_a      => $row->{'node_a'},
			   port_no_a   => $row->{'port_no_a'},
			   interface_a => $row->{'interface_a'},
			   node_z      => $row->{'node_z'},
			   port_no_z   => $row->{'port_no_z'},
			   interface_z => $row->{'interface_z'}
			  });
    }

    return $results;
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

    my $query = "select * from interface where interface_id = ?";
    
    my $results = $self->_execute_query($query, [$interface_id]);

    if (! defined $results){
	$self->_set_error("Internal error getting interface information.");
	return undef;
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
	return undef;
    }

    if(!defined($args{'dpid'})){
	$self->_set_error("DPID not specified");
	return undef;
    }

    my $interface = $self->_execute_query("select interface.node_id,interface.interface_id from node,node_instantiation,interface where node.node_id = node_instantiation.node_id and interface.node_id = node.node_id  and node_instantiation.end_epoch = -1 and node_instantiation.dpid = ? and interface.port_number = ?",[$args{'dpid'},$args{'port_number'}])->[0];
    
    return $interface;

}

=head2 update_interface_operational_state

=cut

sub update_interface_operational_state{
    my $self = shift;
    my %args = @_;

    if(!defined($args{'interface_id'})){
	$self->_set_error("Interface ID was not specified");
	return undef;
    }

    if(!defined($args{'operational_state'})){
	$self->_set_error("Operational State not specified");
	return undef;
    }
    
    my $res = $self->_execute_query("update interface set operational_state = ? where interface.interface_id = ?",[$args{'operational_state'},$args{'interface_id'}]);
    if(!defined($res)){
	$self->_set_error("Unable to update interfaces operational state");
	return undef;
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
    my $select_interface_sth   = $self->_prepare_query($select_interface_query) or return undef;
    
    $select_interface_sth->execute($interface_name,$node_name);
    
    if(my $row = $select_interface_sth->fetchrow_hashref()){
	return $row->{'interface_id'};
    }

    $self->_set_error("Unable to find interface $interface_name on $node_name");

    return undef;
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

    my $node_id = $args{'node_id'};
    my $name    = $args{'name'};
    my $lat     = $args{'latitude'};
    my $long    = $args{'longitude'};

    $self->_start_transaction();

    my $result = $self->_execute_query("update node_instantiation set admin_state = 'active' where node_id = ? and admin_state = 'available'", [$node_id]);

    if ($result != 1){
	$self->_set_error("Error updating node instantiation.");
	return undef;
    }

    $result = $self->_execute_query("update node set name = ?, longitude = ?, latitude = ? where node_id = ?",
	                            [$name, $long, $lat, $node_id]
	                           );

    if ($result != 1){
	$self->_set_error("Error updating node.");
	return undef;
    }

    $self->_commit();

    return 1;
}

sub update_node {
    my $self = shift;
    my %args = @_;

    my $node_id = $args{'node_id'};
    my $name    = $args{'name'};
    my $lat     = $args{'latitude'};
    my $long    = $args{'longitude'};

    $self->_start_transaction();

    my $result = $self->_execute_query("update node set name = ?, longitude = ?, latitude = ? where node_id = ?",
				       [$name, $long, $lat, $node_id]
	                              );

    if ($result != 1){
	$self->_set_error("Error updating node.");
	return undef;
    }

    $self->_commit();

    return 1;
}

sub decom_node {
    my $self = shift;
    my %args = @_;

    my $node_id = $args{'node_id'};

    $self->_start_transaction();

    my $result = $self->_execute_query("update node set operational_state = 'down' where node_id = ?",
				       [$node_id]
	                              );

    if ($result != 1){
	$self->_set_error("Error updating node.");
	
	return undef;
    }

    $result = $self->_execute_query("update node_instantiation set end_epoch = unix_timestamp(NOW()) where end_epoch = -1 and node_id = ?",
				    [$node_id]);
    
    if ($result != 1){
	$self->_set_error("Error updating node instantiation.");
	return undef;
    }

    $result = $self->_execute_query("update interface_instantiation join interface on interface.interface_id = interface_instantiation.interface_id set end_epoch = unix_timestamp(NOW()) where end_epoch = -1 and node_id = ?", 
				    [$node_id]);

    if (! defined $result){
	$self->_set_error("Error updating interface instantiations.");
	return undef;
    }

    $result = $self->_execute_query("update link_instantiation set end_epoch = unix_timestamp(NOW()) where end_epoch -1 and interface_a_id in (select interface_id from interface where node_id = ?) or interface_z_id in (select interface_id from interface where node_id = ?)", 
				    [$node_id, $node_id]);

    if (! defined $result){
	$self->_set_error("Error updating link instantiations.");
	return undef;
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
    
    my $result = $self->_execute_query("update link_instantiation set link_state = 'active' where link_id = ? and link_state = 'available'", [$link_id]);

    if ($result != 1){
	$self->_set_error("Error updating link instantiation.");
	return undef;
    }

    $result = $self->_execute_query("update link set name = ? where link_id = ?", [$name, $link_id]);

    if ($result != 1){
	$self->_set_error("Error updating link.");
	return undef;
    }

    $result = $self->_execute_query("update interface " .
				    " join link_instantiation on interface.interface_id in (link_instantiation.interface_a_id, link_instantiation.interface_z_id) " .				    
				    " set role = 'trunk' " . 
				    " where link_instantiation.link_id = ?",
				    [$link_id]);

    if (! $result){
	$self->_set_error("Error updating link endpoints to trunks.");
	return undef;
    }

    $self->_commit();

    return 1;
}

sub update_link {
    my $self = shift;
    my %args = @_;

    my $link_id = $args{'link_id'};
    my $name    = $args{'name'};

    $self->_start_transaction();
    
    my $result = $self->_execute_query("update link set name = ? where link_id = ?", [$name, $link_id]);

    if ($result != 1){
	$self->_set_error("Error updating link.");
	return undef;
    }

    $self->_commit();

    return 1;
}


sub decom_link {
    my $self = shift;
    my %args = @_;

    my $link_id = $args{'link_id'};

    $self->_start_transaction();
    
    my $result = $self->_execute_query("update link_instantiation set end_epoch = unix_timestamp(NOW()) where end_epoch = -1 and link_id = ?", [$link_id]);

    if ($result != 1){
	$self->_set_error("Error updating link instantiation.");
	return undef;
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
	return undef;
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
				    " node.name, node.longitude, node.latitude " .
				    " from node join node_instantiation on node.node_id = node_instantiation.node_id " .
				    " where node_instantiation.admin_state = 'available'"
	                           ) or return undef;
    
    $sth->execute();

    my $results = [];

    while (my $row = $sth->fetchrow_hashref()){
	push (@$results, {"node_id"    => $row->{'node_id'},
			  "dpid"       => $row->{'dpid'},
			  "ip_address" => $row->{'address'},
			  "name"       => $row->{'name'},
			  "longitude"  => $row->{'longitude'},
			  "latitude"   => $row->{'latitude'}
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

    my $sth = $self->_prepare_query("select link.link_id, link.name as link_name, nodeA.name as nodeA, nodeB.name as nodeB, intA.name as intA, intB.name as intB " .
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
				    " where link_instantiation.link_state = 'available'"
	                           ) or return undef;

    $sth->execute();

    my $links = [];

    while (my $row = $sth->fetchrow_hashref()){

	push(@$links, {'link_id'   => $row->{'link_id'},
		       'name'      => $row->{'link_name'},
		       'endpoints' => [{'node'      => $row->{'nodeA'},
					'interface' => $row->{'intA'}
				       },
				       {'node'      => $row->{'nodeB'},
					'interface' => $row->{'intB'}
				       }
			              ]
	             }
	    );
    }
    
    return $links;
}

=head2 get_link_by_name

=cut

sub get_link_by_name{
    my $self = shift;
    my %args = @_;

    if(!defined($args{'name'})){
	$self->_set_error("Link name was not specified");
	return undef;
    }

    my $link = $self->_execute_query("select * from link where name = ?",[$args{'nane'}])->[0];
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
		" where node_instantiation.dpid = ? and interface.port_number = ?";

    my $result = $self->_execute_query($query, [$dpid, $port]);

    return $result;
}

=head2

=cut

sub get_link_endpoints {
    my $self = shift;
    my %args = @_;

    my $link_id = $args{'link_id'};

    my $query = "select node.node_id, node.name as node_name, interface.interface_id, interface.name as interface_name, interface.description, interface.operational_state, interface.role from node ";
    $query   .= " join interface on interface.node_id = node.node_id " ;
    $query   .= " join link_instantiation on interface.interface_id in (link_instantiation.interface_a_id, link_instantiation.interface_z_id) ";
    $query   .= "  and link_instantiation.end_epoch = -1 ";
    $query   .= " where link_instantiation.link_id = ?";

    my $results = $self->_execute_query($query, [$link_id]);

    if (! defined $results){
	$self->_set_error("Internal error getting link endpoints.");
	return undef;
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
    my $select_link_sth   = $self->_prepare_query($select_link_query) or return undef;
    
    $select_link_sth->execute($link_name);
    
    if(my $row = $select_link_sth->fetchrow_hashref()){
	return $row->{'link_id'};
    }

    $self->_set_error("Unable to find link $link_name");

    return undef;
}

=head2 get_link_by_a_or_z_end

=cut

sub get_link_by_a_or_z_end{
    my $self = shift;
    my %args = @_;

    if(!defined($args{'interface_a_id'})){
	$self->_set_error("Interface A ID not specified");
	return undef;
    }

    if(!defined($args{'interface_z_id'})){
	$self->_set_error("Interface Z ID Not specified");
	return undef;
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
	return undef;
    }

    return $results;
}

=head2 print_db_schema_file

A debug method to show what schema file the tests (and presumably the real database) are using.

=cut

sub print_db_schema_file{
    my $self = shift;

    my $module_dir=File::ShareDir::dist_dir('OESS-Database');
    
    warn "module_dir=$module_dir\n";
    
    my $file_path=File::ShareDir::dist_file('OESS-Database','nddi.sql');
    
    warn "file_path=$file_path\n";
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
        return undef;
    }

    my $dbh      = $self->{'dbh'};

    my $xml = XML::Simple::XMLin($self->{'config'});

    my $username = $xml->{'credentials'}->{'username'};
    my $password = $xml->{'credentials'}->{'password'};
    my $database = $xml->{'credentials'}->{'database'};

    my $import_filename = File::ShareDir::dist_file('OESS-Database','nddi.sql');

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
        return undef;
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
    my $user_sth   = $self->_prepare_query($user_query) or return undef;
    
    foreach my $user_name (keys %$users){
	$user_sth->execute($user_name,
			   $users->{$user_name}->{'given_names'},
			   $users->{$user_name}->{'last_name'}
	    ) or return undef;         
    }

    #do workgroups
    my $workgroups      = $db_dump->{'workgroup'};

    my $workgroup_query = "insert ignore into workgroup (name,description) VALUES (?,?)";
    my $workgroup_sth   = $self->_prepare_query($workgroup_query) or return undef;

    my $workgroup_select_query = "select workgroup_id from workgroup where name=?";
    my $workgroup_select_sth   = $self->_prepare_query($workgroup_select_query) or return undef;

    my $user_workgroup_insert  = 'insert into user_workgroup_membership (workgroup_id,user_id) VALUES (?,(select user_id from user where email=?))';
    my $user_workgroup_insert_sth = $self->_prepare_query($user_workgroup_insert) or return undef;
    
    foreach my $workgroup_name (keys %$workgroups){

	$workgroup_sth->execute($workgroup_name,
				$workgroups->{$workgroup_name}->{'description'}) or return undef;

	$workgroup_select_sth->execute($workgroup_name) or return undef;

	my $workgroup_db_id;
	my $row;

	if($row = $workgroup_select_sth->fetchrow_hashref()){
	    $workgroup_db_id = $row->{'workgroup_id'};
	}

	return undef unless $workgroup_db_id;

	my $users_in_workgroup = $workgroups->{$workgroup_name}->{'user_member'};

	foreach my $user (@$users_in_workgroup){
            $user_workgroup_insert_sth->execute($workgroup_db_id,
						$user) or return undef;
	}   
    } 

    #now networks
    my $network_insert_query = "insert into network (name,longitude, latitude) VALUES (?,?,?)" ;
    my $network_insert_sth   = $self->_prepare_query($network_insert_query) or return undef;

    my $insert_node_query = "insert into node (name,longitude,latitude, network_id) VALUES (?,?,?,(select network_id from network where name=?))";
    my $insert_node_sth   = $self->_prepare_query($insert_node_query) or return undef;

    my $insert_node_instantiaiton_query = "insert into node_instantiation (node_id,end_epoch,start_epoch,management_addr_ipv4,dpid,admin_state) VALUES ((select node_id from node where name=?),-1,unix_timestamp(now()),inet_aton(?),?,?)";
    my $insert_node_instantiaiton_sth   = $self->_prepare_query($insert_node_instantiaiton_query) or return undef;

    my $insert_interface_query = "insert into interface (name,description,node_id,operational_state) VALUES(?,?,(select node_id from node where name=?),?) ";
    my $insert_interface_sth   = $self->_prepare_query($insert_interface_query);

    my $select_interface_query = "select interface_id from interface where name=? and node_id=(select node_id from node where name=?)";
    my $select_interface_sth   = $self->_prepare_query($select_interface_query) or return undef;

    my $insert_interface_instantiaiton_query = "insert into interface_instantiation (interface_id,end_epoch,start_epoch,capacity_mbps,mtu_bytes) VALUES (?,-1,unix_timestamp(now()),10000,9000)";    
    my $insert_interface_instantiaiton_sth   = $self->_prepare_query($insert_interface_instantiaiton_query) or return undef;

    my $networks = $db_dump->{'network'};

    foreach my $network_name (keys %$networks){
	$network_insert_sth->execute($network_name,
				     $networks->{$network_name}->{'longitude'},
				     $networks->{$network_name}->{'latitude'}) or return undef;

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

		$insert_interface_instantiaiton_sth->execute($interface_db_id) or return undef;
		
	    }
	}

	#now links
	my $links = $networks->{$network_name}->{'link'};

	my $insert_new_link_query = "insert into link (name) VALUES (?)";
	my $insert_new_link_sth   = $self->_prepare_query($insert_new_link_query) or return undef;

	my $insert_new_link_instantiation     = "insert into link_instantiation (link_id,end_epoch,start_epoch,interface_a_id,interface_z_id,link_state) VALUES ( (select link_id from link where name=?),-1,unix_timestamp(now()),?,?,?)";
	my $insert_new_link_instantiation_sth = $self->_prepare_query($insert_new_link_instantiation) or return undef;

	foreach my $link_name (keys %$links){
	    my $link = $links->{$link_name};
	    
	    $insert_new_link_sth->execute($link_name) or return undef;
	    
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
    my $insert_circuit_sth   = $self->_prepare_query($insert_circuit_query) or return undef;

    my $insert_circuit_instantiation_query = "insert into circuit_instantiation (circuit_id,end_epoch,start_epoch,reserved_bandwidth_mbps,circuit_state,modified_by_user_id) VALUES ((select circuit_id from circuit where name=?),-1,unix_timestamp(now()),?,?,?)";
    my $insert_circuit_instantiation_sth   = $self->_prepare_query($insert_circuit_instantiation_query) or return undef;

    my $insert_path_query = "insert into path (path_type,circuit_id) VALUES (?,(select circuit_id from circuit where name=?))";
    my $insert_path_sth   = $self->_prepare_query($insert_path_query) or return undef;

    my $insert_path_inst_query = "insert into path_instantiation ( path_id,end_epoch,start_epoch,internal_vlan_id,path_state) VALUES ((select path_id from path where path_type=? and circuit_id=(select circuit_id from circuit where name=?)),-1,unix_timestamp(now()),?,?)";
    my $insert_path_inst_sth   = $self->_prepare_query( $insert_path_inst_query) or return undef;

    my $insert_link_path_membership_query = "insert into link_path_membership (path_id,link_id,end_epoch,start_epoch) VALUES ((select path_id from path where path_type=? and circuit_id=(select circuit_id from circuit where name=?)),?,-1, unix_timestamp(now()) )";
    my $insert_link_path_membership_sth   = $self->_prepare_query($insert_link_path_membership_query) or return undef;      

    my $insert_circuit_edge_interface_membership_query = "insert into circuit_edge_interface_membership (circuit_id,interface_id,extern_vlan_id,end_epoch,start_epoch) VALUES ((select circuit_id from circuit where name=?),?,?,-1,unix_timestamp(now()))";
    my $insert_circuit_edge_interface_membership_sth   = $self->_prepare_query($insert_circuit_edge_interface_membership_query) or return undef;

    my $circuits = $db_dump->{'circuit'};
    my $i = 100;
    foreach my $circuit_name (keys %$circuits){

	my $circuit = $circuits->{$circuit_name};

	$insert_circuit_sth->execute($circuit_name,
				     $circuit->{'description'}) or return undef;

	$insert_circuit_instantiation_sth->execute($circuit_name,
						   $circuit->{'reserved_bw'},
						   'active',
						   1) or return undef;

	#now paths
	my $paths = $circuit->{'path'};

	foreach my $path (@$paths){	    

	    my $path_type     = $path->{'type'};
	    my $internal_vlan = $path->{'vlan'} || $i++;

	    $insert_path_sth->execute($path_type,
				      $circuit_name) or return undef;

	    $insert_path_inst_sth->execute($path_type,
					   $circuit_name,
					   $internal_vlan,
					   'active');


	    my $path_links = $path->{'member_link'};
	    foreach my $link_name (@$path_links){
		my $link_db_id = $self->get_link_id_by_name(link => $link_name);

		$insert_link_path_membership_sth->execute($path_type,
							  $circuit_name,
							  $link_db_id) or return undef; 
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
		                                                  ) or return undef;
	}
	
    }

    return 1;
}

=head2 get_remote_links 

=cut

sub get_remote_links {
    my $self = shift;
    my %args = @_;

    my $query = "select link.link_id, link.remote_urn, node.name as node_name, interface.name as int_name from link " .
	" join link_instantiation on link.link_id = link_instantiation.link_id " .
	" join interface on interface.interface_id in (link_instantiation.interface_a_id, link_instantiation.interface_z_id) " .
	" join interface_instantiation on interface.interface_id = interface_instantiation.interface_id " .
	"  and interface_instantiation.end_epoch = -1 and interface_instantiation.admin_state != 'down' " .
	" join node on node.node_id = interface.node_id " .
	" join network on network.network_id = node.network_id and network.is_local = 1" . 
	" where link.remote_urn is not null";

    my $rows = $self->_execute_query($query, []);

    if (! defined $rows){
	$self->_set_error("Internal error getting remote links.");
	return undef;
    }

    my @results;

    foreach my $row (@$rows){
	push (@results, {"link_id"   => $row->{'link_id'},
			 "node"      => $row->{'node_name'},
			 "interface" => $row->{'int_name'},
			 "urn"       => $row->{'remote_urn'}
	                 }
	    );
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
    my $local_interface_id  = $args{'local_interface_id'}; 

    if ($urn !~ /domain=(.+):node=(.+):port=(.+):link=(.+)$/){
	$self->_set_error("Unable to deconstruct URN to determine elements. Expected format was urn:ogf:network:domain=foo:node=bar:port=biz:link=bam");
	return undef;
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
	return undef;
    }

    # remote are stored internally as $domain-$node
    $remote_node = $remote_domain . "-" . $remote_node;
    
    my $node_info = $self->get_node_by_name(name              => $remote_node,
					    no_instantiation  => 1
	                                    );

    warn Dumper($node_info);

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
	return undef;
    }

    my $remote_interface_id = $self->add_or_update_interface(node_id          => $remote_node_id,
							     name             => $remote_port,
							     no_instantiation => 1
	                                                    );
    
    if (! defined $remote_interface_id){
	$self->_set_error("Unable to determine interface id: " . $self->get_error());
	return undef;
    }

    my $link_id = $self->add_link(name       => $name,
				  remote_urn => $urn
	                         );

    if (! defined $link_id){
	$self->_set_error("Unable to create link $name: " . $self->get_error());
	return undef;
    }

    my $result = $self->create_link_instantiation(link_id         => $link_id,
						  state           => 'active',
						  interface_a_id  => $local_interface_id,
						  interface_z_id  => $remote_interface_id
	                                          );

    if (! defined $result){
	$self->_set_error("Unable to create link instantiation: " . $self->get_error());
	return undef;
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
    my $select_network_sth = $self->_prepare_query($select_network) or return undef;
    
    $select_network_sth->execute($network_name) or return undef;
    
    if(my $row = $select_network_sth->fetchrow_hashref()){
	return $row->{'network_id'};
    }
    $self->_set_error("Unable to find network named " . $network_name);
    return undef;

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
	return undef;
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
    my $sth = $self->_prepare_query($str) or return undef;
    $sth->execute($network_id) or return undef;
    
    if(my $row = $sth->fetchrow_hashref()){
	return $row;
    }

    $self->_set_error("unable to find network id " . $network_id . "\n");
    return undef;
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
    
    my $select_nodes = "select node.node_id,node.name,inet_ntoa(node_instantiation.management_addr_ipv4) as management_addr_ipv4 from node,node_instantiation where node.node_id = node_instantiation.node_id and node_instantiation.admin_state = ? and end_epoch = -1";

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
	return undef;
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
    
    my $select_link_by_interface = "select link.name as link_name, link.link_id,link.remote_urn, link_instantiation.interface_a_id, link_instantiation.interface_z_id from link,link_instantiation where link.link_id = link_instantiation.link_id and (link_instantiation.interface_a_id = ? or link_instantiation.interface_z_id = ?)";
    my $select_link_sth = $self->_prepare_query($select_link_by_interface);
    
    $select_link_sth->execute($interface_id,$interface_id);
    my @results;
    while(my $row = $select_link_sth->fetchrow_hashref()){
	push(@results,$row);
    }

    if($#results >= 0){
	return \@results;
    }else{
	$self->_set_error("Unable to find links with interface_id $interface_id");
	return undef;
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
	return undef;
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
	return undef;
    }

    return @$results[0];
}


=head2 get_circuit_by_interface_id

Returns an array of hashes containing circuit information of all active circuits that have the interface identified by $interface_id as an endpoint.

=over

=item interface_id

The internal MySQL primary key int identifier for this interface.

=back

=cut

sub get_circuit_by_interface_id{
    my $self = shift;
    my %args = @_;
    
    my $interface_id = $args{'interface_id'};

    my $select_circuit = "select circuit.name,circuit.description from circuit_edge_interface_membership,circuit_instantiation,circuit where circuit.circuit_id = circuit_edge_interface_membership.circuit_id, circuit_instantiation.cicuit_id = circuit.circuit_id and circuit_instantiation.circuit_state = 'active' and circuit_instantiation.end_epoch = -1 and circuit_edge_interface_membeship.interface_id = ? and circuit_edge_interface_membership.end_epcoh = -1";
    my $select_circuit_sth = $self->_prepare_query($select_circuit);
    $select_circuit_sth->execute($interface_id);
    my @results;

    while(my $row = $select_circuit_sth->fetchrow_hasref()){
	push(@results,$row);
    }

    if($#results > 0){
	return \@results;
    }else{
	$self->_set_error("Unable to find circuits with interface_id $interface_id");
	return undef;
    }
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
    my $user_name        = $args{'user_name'};
    my $workgroup_id     = $args{'workgroup_id'};
    my $external_id      = $args{'external_id'};
    my $remote_endpoints = $args{'remote_endpoints'} || [];
    my $remote_tags      = $args{'remote_tags'} || [];

    my $user_id        = $self->get_user_id_by_auth_name(auth_name => $user_name);

    if (! $user_id ){
	$self->_set_error("Unknown user '$user_name'");
	return undef;
    }

    my $workgroup_details = $self->get_workgroup_details(workgroup_id => $workgroup_id);

    if (! defined $workgroup_details){
	$self->_set_error("Unknown workgroup.");
	return undef;
    }

    if (! $self->is_user_in_workgroup(user_id => $user_id, workgroup_id => $workgroup_id)){
	$self->_set_error("Permission denied: user is not a part of the requested workgroup.");
	return undef;
    }

    my $query;

    $self->_start_transaction();

    my $uuid = $self->_get_uuid();

    if (! defined $uuid){
	return undef;
    }

    my $name = $workgroup_details->{'name'} . "-" . $uuid;
    
    # create circuit record
    my $circuit_id = $self->_execute_query("insert into circuit (name, description, workgroup_id, external_identifier) values (?, ?, ?, ?)",
					   [$name, $description, $workgroup_id, $external_id]);
    
    if (! defined $circuit_id ){
	$self->_set_error("Unable to create circuit record.");
	return undef;
    }

    my $state;
    if($provision_time > time()){
	$state = "scheduled";
    }else{
	$state = "deploying";
    }

    #instantiate circuit
    $query = "insert into circuit_instantiation (circuit_id, reserved_bandwidth_mbps, circuit_state, modified_by_user_id, end_epoch, start_epoch) values (?, ?, ?, ?, -1, unix_timestamp(now()))";
    $self->_execute_query($query, [$circuit_id, $bandwidth, $state, $user_id]);
    
    if($state eq 'scheduled'){

	$args{'user_id'}    = $user_id;
	$args{'circuit_id'} = $circuit_id;	

	my $success = $self->_add_event(\%args);

	if (! defined $success){
	    return undef;
	}

	$self->_commit();

	return {"success" => 1, "circuit_id" => $circuit_id};
    }

    #not a scheduled event ie.. do it now

    # first set up endpoints
    for (my $i = 0; $i < @$nodes; $i++){
	
	my $node      = @$nodes[$i];
	my $interface = @$interfaces[$i];
	my $vlan      = @$tags[$i];
	
	$query = "select interface_id from interface " .
	    " join node on node.node_id = interface.node_id " .
	    " where node.name = ? and interface.name = ? ";
	
	my $interface_id = $self->_execute_query($query, [$node, $interface])->[0]->{'interface_id'};
	
	if (! $interface_id ){
	    $self->_set_error("Unable to find interface '$interface' on node '$node'");
	    return undef;
	}

	if (! $self->_validate_endpoint(interface_id => $interface_id, workgroup_id => $workgroup_id)){
	    $self->_set_error("Interface \"$interface\" on endpoint \"$node\" is not allowed for this workgroup.");
	    return undef;
	}
	
	# need to check to see if this external vlan is open on this interface first
	if (! $self->is_external_vlan_available_on_interface(vlan => $vlan, interface_id => $interface_id) ){
	    $self->_set_error("Vlan '$vlan' is currently in use by another circuit on interface '$interface' on endpoint '$node'");
	    return undef;
	}
	
	$query = "insert into circuit_edge_interface_membership (interface_id, circuit_id, extern_vlan_id, end_epoch, start_epoch) values (?, ?, ?, -1, unix_timestamp(NOW()))";
	
	if (! defined $self->_execute_query($query, [$interface_id, $circuit_id, $vlan])){
	    $self->_set_error("Unable to create circuit edge to interface '$interface' on endpoint '$node'");
	    return undef;
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
	    return undef;
	}


	$query = "insert into circuit_edge_interface_membership (interface_id, circuit_id, extern_vlan_id, end_epoch, start_epoch) values (?, ?, ?, -1, unix_timestamp(NOW()))";
	
	if (! defined $self->_execute_query($query, [$interface_id, $circuit_id, $tag])){
	    $self->_set_error("Unable to create circuit edge to interface \"$urn\" with tag $tag.");
	    return undef;
	}

    }


    # now set up links
    my $link_lookup = {'primary' => $links,
		       'backup'  => $backup_links
    };
    
    foreach my $path_type (qw(primary backup)){
	
	my $relevant_links = $link_lookup->{$path_type};
	
	# figure out what internal ID we can use for this
	my $internal_vlan = $self->_get_available_internal_vlan_id();
	
	if (! defined $internal_vlan){
	    $self->_set_error("Internal error finding available internal id.");
	    return undef;
	}
	
	
	# create the primary path object
	$query = "insert into path (path_type, circuit_id) values (?, ?)";
	
	my $path_id = $self->_execute_query($query, [$path_type, $circuit_id]);
	
	if (! $path_id){
	    $self->_set_error("Error while creating path record.");
	    return undef;
	}
	
	
	# instantiate path object
	$query = "insert into path_instantiation (path_id, internal_vlan_id, end_epoch, start_epoch, path_state) values (?, ?, -1, unix_timestamp(NOW()), ?)";

	my $path_state = "deploying";

	if ($path_type eq "backup"){
	    $path_state = "available";
	}
	
	if (! defined $self->_execute_query($query, [$path_id, $internal_vlan, $path_state])){
	    $self->_set_error("Error while instantiating path record.");
	    return undef;	
	} 
	
	
	# now create the primary links into the primary path
	for (my $i = 0; $i < @$relevant_links; $i++){
	    
	    my $link = @$relevant_links[$i];
	    
	    $query = "select link_id from link where name = ?";
	    
	    my $link_id = $self->_execute_query($query, [$link])->[0]->{'link_id'};
	    
	    if (! $link_id){
		$self->_set_error("Unable to find link '$link'");
		return undef;
	    }
	    
	    $query = "insert into link_path_membership (link_id, path_id, end_epoch, start_epoch) values (?, ?, -1, unix_timestamp(NOW()))";
	    
	    if (! defined $self->_execute_query($query, [$link_id, $path_id])){
		$self->_set_error("Error adding link '$link' into path.");
		return undef;
	    }
	    
	}

    }

    # now check to verify that the topology makes sense
    my ($success, $error) = $self->{'topo'}->validate_paths(circuit_id => $circuit_id);

    if (! $success){
	$self->_set_error($error);
	return undef;
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
    my $user_name   = $args{'user_name'};

    my $user_id = $self->get_user_id_by_auth_name(auth_name => $user_name);

    if (! $user_id){
	$self->_set_error("Unknown user \"$user_name\"");
	return undef;
    }

    if ($remove_time > time()){
	$args{'user_id'} = $user_id;

	return $self->_add_remove_event(\%args);
    }

    $self->_start_transaction();

    $self->update_circuit_state(circuit_id          => $circuit_id,
				old_state           => 'active',
				new_state           => 'decom',
				modified_by_user_id => $user_id
	);

    my $results = $self->_execute_query("update path_instantiation " .
					" join path on path.path_id = path_instantiation.path_id " .
					"set end_epoch = unix_timestamp(NOW()) " .
					" where end_epoch = -1 and path.circuit_id = ?",
					[$circuit_id]
	                                );

    if (! defined $results){
	$self->_set_error("Unable to decom path instantiations.");
	return undef;
    }

    $results = $self->_execute_query("update link_path_membership " .
				     " join path on path.path_id = link_path_membership.path_id " .
				     "set end_epoch = unix_timestamp(NOW()) " .
				     " where end_epoch = -1 and path.circuit_id = ?",
				     [$circuit_id]
	                            );

    if (! defined $results){
	$self->_set_error("Unable to decom link membership.");
	return undef;
    }


    $results = $self->_execute_query("update circuit_edge_interface_membership " .
				     "set end_epoch = unix_timestamp(NOW()) " .
				     " where end_epoch = -1 and circuit_id = ?",
				     [$circuit_id]
	                            );

    if (! defined $results){
	$self->_set_error("Unable to decom edge membership.");
	return undef;
    }
    
    $self->_commit();

    return 1;
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
					       1,
					       $params->{'circuit_id'},
					       time(),
					       $params->{'provision_time'},
					       $circuit_layout
				               ]
	                               );

    if (! defined $result){
	$self->_set_error("Error creating scheduled addition.");
	return undef;
    }
    
    if($params->{'remove_time'} != -1){
	my $result = $self->_add_remove_event($params);	

	if (! defined $result){
	    return undef;
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
					       1,
					       $params->{'circuit_id'},
					       time(),
					       $params->{'remove_time'},
					       $circuit_layout
				               ]
	                               );

    if (! defined $result){
	$self->_set_error("Error creating scheduled removal.");
	return undef;
    }    

    return 1;
}

=head2 update_action_complete_epoch

=cut

sub update_action_complete_epoch{
    my $self = shift;
    my %args = @_;

    if(!defined($args{'scheduled_action_id'})){
	return undef;
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
	return undef;
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
	return undef;
    }    

    my $sth = $self->{'dbh'}->prepare("select * from node,node_instantiation where node.node_id = node_instantiation.node_id and node_instantiation.dpid = ?");
    $sth->execute($args{'dpid'});
    if(my $row = $sth->fetchrow_hashref()){
	return $row;
    }else{
	$self->_set_error("Unable to find node with DPID");
	return undef;
    }
}


=head2 add_node

=cut

sub add_node{
    my $self = shift;
    my %args = @_;

    if(!defined($args{'name'})){
	$self->_set_error("Node Name was not specified");
	return undef;
    }

    my $default_lat ="0.0";
    my $default_long="0.0";
    my $res = $self->_execute_query("insert into node (name,latitude, longitude, operational_state,network_id) VALUES (?,?,?,?,?)",[$args{'name'},$default_lat,$default_long,$args{'operational_state'},$args{'network_id'}]);

    if(!defined($res)){
	$self->_set_error("Unable to create new node record");
	return undef;
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
	    return undef;
	}
     }
 
    my $res = $self->_execute_query("insert into node_instantiation (node_id,end_epoch,start_epoch,management_addr_ipv4,admin_state,dpid) VALUES (?,?,?,?,?,?)",[$args{'node_id'},-1,time(),$args{'ipv4_addr'},$args{'admin_state'},$args{'dpid'}]);
    
    if(!defined($res)){
	$self->_set_error("Unable to create new node instantiation");
	return undef;
    }
    

    return 1;

}

=head2 update_node_operational_state

=cut

sub update_node_operational_state{
    my $self = shift;
    my %args = @_;
    
    my $res = $self->_execute_query("update node set operational_state = ? where node_id = ?",[$args{'state'},$args{'node_id'}]);
    if(!defined($res)){
	$self->_set_error("Unable to update operational state");
	return undef;
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
	return undef;
    }
    
    if(!defined($args{'name'})){
	$self->_set_error("Name was not defined");
	return undef;
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
		    return undef;
		}
	    }
	    
	    my $res = $self->_execute_query("update interface set port_number = ? where interface_id = ?",[$args{'port_num'},$int->{'interface_id'}]);
	    if(!defined($res)){
		return undef;
	    }
	}
	
	#update operational state
	my $res = $self->_execute_query("update interface set operational_state = ? where interface.interface_id = ?",[$args{'operational_state'},$int->{'interface_id'}]);
	if(!defined($res)){
	    $self->_set_error("Unable to update operational_state");
	    return undef;
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
			return undef;
		    }
		    $res = $self->_execute_query("insert into interface_instantiation (interface_id,admin_state,end_epoch,start_epoch,capacity_mbps,mtu_bytes) VALUES (?,?,-1,UNIX_TIMESTAMP(NOW()),?,?)",[$int->{'interface_id'},$args{'admin_state'},$args{'capacity_mbps'},$args{'mtu_bytes'}]);
		    if(!defined($res)){
			$self->_set_error("Unable to create interface instantaition");
			return undef;
		    }
		}
		
		
	    }else{
		if (! $args{'no_instantiation'}){
		    $self->_execute_query("insert into interface_instantiation (interface_id,admin_state,end_epoch,start_epoch,capacity_mbps,mtu_bytes) VALUES (?,?,-1,UNIX_TIMESTAMP(NOW()),?,?)",[$int->{'interface_id'},$args{'admin_state'},$args{'capacity_mbps'},$args{'mtu_bytes'}]);
		    if(!defined($res)){
			return undef;
		    }
		}
	    }
	}

    }else{
	#interface does not exist
	#however we aren't guaranteed the same port number didn't already exist... lets check and verify
	$int = $self->_execute_query("select * from interface where interface.node_id = ? and interface.port_number = ?",[$args{'node_id'},$args{'port_num'}]);
	
	if(defined($int) && defined(@{$int}[0])){
	    #Uh oh, the name changed but the port number already existed... this device configuration is just completely different
	    $int = @{$int}[0];
	    my $update = $self->_execute_query("update interface set port_number=NULL where interface_id = ?",[$int->{'interface_id'}]);
	    if(!defined($update)){
		$self->_set_error("This device had something pretty crappy happen, its going to require manual intervention");
		return undef;
	    }
	}

	#interface/port number doesn't exist lets create it
	$int_id = $self->_execute_query("insert into interface (node_id,name,description,operational_state,port_number) VALUES (?,?,?,?,?)",[$args{'node_id'},$args{'name'},$args{'description'},$args{'operational_state'},$args{'port_num'}]);
	if(!defined($int_id)){
	    $self->_set_error("Unable to insert a new interface!!");
	    return undef;
	}

	if (! $args{'no_instantiation'}){

	    my $res = $self->_execute_query("insert into interface_instantiation (interface_id,admin_state,end_epoch,start_epoch,capacity_mbps,mtu_bytes) VALUES (?,?,-1,UNIX_TIMESTAMP(NOW()),?,?)",[$int_id,$args{'admin_state'},$args{'capacity_mbps'},$args{'mtu_bytes'}]);
	    if(!defined($res)){
		return undef;
	    }

	}
    
    }

    return $int_id;
}


=head2 edit_circuit
TODO
=cut

sub edit_circuit {
    my $self = shift;
    my %args = @_;
    
    my $circuit_id     = $args{'circuit_id'};
    my $description    = $args{'description'};
    my $bandwidth      = $args{'bandwidth'};
    my $provision_time = $args{'provision_time'};
    my $remove_time    = $args{'remove_time'};
    my $links          = $args{'links'};
    my $backup_links   = $args{'backup_links'};
    my $nodes          = $args{'nodes'};
    my $interfaces     = $args{'interfaces'};
    my $tags           = $args{'tags'};
    my $user_name      = $args{'user_name'};
    my $workgroup_id   = $args{'workgroup_id'};
    my $remote_endpoints = $args{'remote_endpoints'} || [];
    my $remote_tags      = $args{'remote_tags'} || [];

    # whether this edit should only edit everything or just local bits
    my $do_external    = $args{'do_external'} || 0;

    my $user_id        = $self->get_user_id_by_auth_name(auth_name => $user_name);

    if (! $user_id ){
        $self->_set_error("Unknown user '$user_name'");
        return undef;
    }

    my $query;

    $self->_start_transaction();

    my $circuit = $self->get_circuit_by_id(circuit_id => $circuit_id);
    if(!defined($circuit)){
	$self->_set_error("Unable to find circuit by id $circuit_id");
	return undef;
    }

    if ($provision_time > time()){
	$args{'user_id'} = $user_id;

	my $success = $self->_add_event(\%args);

	if (! defined $success){
	    return undef;
	}

	return {'success' => 1, 'circuit_id' => $circuit_id};
    }

    my $result = $self->_execute_query("update circuit set description = ? where circuit_id = ?", [$description, $circuit_id]);

    if (! defined $result){
	$self->_set_error("Unable to update circuit description.");
	return undef;
    }

    # daldoyle - no need to instantiation on circuit edit, causes conflicts with the scheduler and other tools since
    # things happen in sub 1 second
    #instantiate circuit
    #$query = "update circuit_instantiation set end_epoch = UNIX_TIMESTAMP(NOW()) where circuit_id = ? and end_epoch = -1";
    #$self->_execute_query($query, [$circuit_id]);

    #$query = "insert into circuit_instantiation (circuit_id, reserved_bandwidth_mbps, circuit_state, modified_by_user_id, end_epoch, start_epoch) values (?, ?, 'deploying', ?, -1, unix_timestamp(now()))";
    #$self->_execute_query($query, [$circuit_id, $bandwidth, $user_id]);

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
    $self->_execute_query($query, [$circuit_id]);
    
    $query = "select * from path where circuit_id = ?";
    my $paths = $self->_execute_query($query, [$circuit_id]);

    foreach my $path (@$paths){
	$query = "update path_instantiation set end_epoch = unix_timestamp(now()) where path_id = ? and end_epoch = -1";
	$self->_execute_query($query, [$path->{'path_id'}]);
	$query = "update link_path_membership set end_epoch = unix_timestamp(now()) where path_id = ? and end_epoch = -1";
	$self->_execute_query($query, [$path->{'path_id'}]);
    }

    #re-instantiate
    # first set up endpoints                                                                                                                                                                        
    for (my $i = 0; $i < @$nodes; $i++){

        my $node      = @$nodes[$i];
        my $interface = @$interfaces[$i];
        my $vlan      = @$tags[$i];

        $query = "select interface_id from interface " .
            " join node on node.node_id = interface.node_id " .
            " where node.name = ? and interface.name = ? ";

        my $interface_id = $self->_execute_query($query, [$node, $interface])->[0]->{'interface_id'};

        if (! $interface_id ){
            $self->_set_error("Unable to find interface '$interface' on node '$node'");
            return undef;
        }

	if (! $self->_validate_endpoint(interface_id => $interface_id, workgroup_id => $workgroup_id)){
	    $self->_set_error("Interface \"$interface\" on endpoint \"$node\" is not allowed for this workgroup.");
	    return undef;
	}

        # need to check to see if this external vlan is open on this interface first                                                                                                                
        if (! $self->is_external_vlan_available_on_interface(vlan => $vlan, interface_id => $interface_id) ){
            $self->_set_error("Vlan '$vlan' is currently in use by another circuit on interface '$interface' on endpoint '$node'");
            return undef;
        }

        $query = "insert into circuit_edge_interface_membership (interface_id, circuit_id, extern_vlan_id, end_epoch, start_epoch) values (?, ?, ?, -1, unix_timestamp(NOW()))";
	print STDERR "Adding interface " . $interface_id . "." . $vlan . "\n";
        if (! defined $self->_execute_query($query, [$interface_id, $circuit_id, $vlan])){
            $self->_set_error("Unable to create circuit edge to interface '$interface'");
            return undef;
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
	    return undef;
	}

	$query = "insert into circuit_edge_interface_membership (interface_id, circuit_id, extern_vlan_id, end_epoch, start_epoch) values (?, ?, ?, -1, unix_timestamp(NOW()))";
	
	if (! defined $self->_execute_query($query, [$interface_id, $circuit_id, $tag])){
	    $self->_set_error("Unable to create circuit edge to interface \"$urn\" with tag $tag.");
	    return undef;
	}

    }


    my $link_lookup = {'primary' => $links,
                       'backup'  => $backup_links
    };

    foreach my $path_type (qw(primary backup)){

        my $relevant_links = $link_lookup->{$path_type};

        # figure out what internal ID we can use for this                                                                                                                                                 
        my $internal_vlan = $self->_get_available_internal_vlan_id();

        if (! defined $internal_vlan){
            $self->_set_error("Internal error finding available internal id.");
            return undef;
        }


	#try to find the path first
	$query = "select * from path where circuit_id = ? and path_type = ?";
	my $res = $self->_execute_query($query,[$circuit_id, $path_type]);
	my $path_id;
	if(!defined($res) || !defined(@{$res}[0])){
	    # create the primary path object
	    print STDERR "Creating path\n";
	    $query = "insert into path (path_type, circuit_id) values (?, ?)";
	    $path_id = $self->_execute_query($query, [$path_type, $circuit_id]);
	}else{
	    print STDERR "Path already exists\n";
	    $path_id = @{$res}[0]->{'path_id'};
	}

        if (! $path_id){
            $self->_set_error("Error while creating path record.");
            return undef;
        }


        # instantiate path object                                                                                                                                                                         
        $query = "insert into path_instantiation (path_id, internal_vlan_id, end_epoch, start_epoch, path_state) values (?, ?, -1, unix_timestamp(NOW()), ?)";

        my $path_state = "deploying";

        if ($path_type eq "backup"){
            $path_state = "available";
        }

        if (! defined $self->_execute_query($query, [$path_id, $internal_vlan, $path_state])){
            $self->_set_error("Error while instantiating path record.");
            return undef;
        }


        # now create the primary links into the primary path                                                                                                                                              
        for (my $i = 0; $i < @$relevant_links; $i++){

            my $link = @$relevant_links[$i];

            $query = "select link_id from link where name = ?";

            my $link_id = $self->_execute_query($query, [$link])->[0]->{'link_id'};

            if (! $link_id){
                $self->_set_error("Unable to find link '$link'");
                return undef;
            }

            $query = "insert into link_path_membership (link_id, path_id, end_epoch, start_epoch) values (?, ?, -1, unix_timestamp(NOW()))";

            if (! defined $self->_execute_query($query, [$link_id, $path_id])){
                $self->_set_error("Error adding link '$link' into path.");
                return undef;
            }

        }

    }

    $self->_commit();

    return {"success" => 1, "circuit_id" => $circuit_id};
}

=head1 Internal Methods

=head2 _set_error

=over

=item 

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

    $dbh->begin_work();
}

=head2 _get_uuid 

Returns a UUID. This is generated via the underlying MySQL database.

=cut

sub _get_uuid {
    my $self = shift;

    my $result = $self->_execute_query("select UUID() as uuid");

    if (! defined $result){
	$self->_set_error("Internal error generating UUID.");
	return undef;
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

=item

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
	return undef;
    }

    return $sth;
}

=head2 _execute_query

Return type varies depending on query type. Select queries return an array of hashes of rows returned. Update and Delete queries return the number of rows affected. Insert returns the auto_increment key used if relevant. Returns undef on failure.

=over

=item 

The query string to execute.

=item

An array of arguments to pass into the query execute. This is the same as executing a DBI based query with placeholders (?).

=back

=cut

sub _execute_query {
    my $self  = shift;
    my $query = shift;
    my $args  = shift;

    my $dbh = $self->{'dbh'};

    my $sth = $dbh->prepare($query);

    #warn "Query is: $query\n";

    #warn "Args are: " . Dumper($args);

    if (! $sth){
	#warn "Error in prepare query: $DBI::errstr";
	$self->_set_error("Unable to prepare query: $DBI::errstr");
	return undef;
    }

    if (! $sth->execute(@$args) ){
	#warn "Error in executing query: $DBI::errstr";
	$self->_set_error("Unable to execute query: $DBI::errstr");
	return undef;
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

=cut

sub _get_available_internal_vlan_id {
    my $self = shift;
    my %args = @_;

    my $query = "select internal_vlan_id from path_instantiation where end_epoch = -1";

    my %used;

    my $results = $self->_execute_query($query, []);

    # something went wrong
    if (! defined $results){
	$self->_set_error("Internal error finding available internal id.");
	return undef;
    }

    foreach my $row (@$results){
	$used{$row->{'internal_vlan_id'}} = 1;
    }

    for (my $i = 1; $i < 4096; $i++){
	if (! exists $used{$i}){
	    return $i;
	}
    }

    return undef;
}

=head2 _validate_endpoint

Verifies that the endpoint in question is accessible to the given workgroup.

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

    my $query = "select 1 from workgroup_interface_membership where interface_id = ? and workgroup_id = ?";

    my $results = $self->_execute_query($query, [$interface_id, $workgroup_id]);

    if (! defined $results){
	$self->_set_error("Internal error validating endpoint.");
	return undef;
    }

    if (@$results > 0){
	return 1;
    }

    return 0;
}


=head2 get_oscars_host

Returns OSCARS host

=cut

sub get_oscars_host{
    my $self = shift;
    return $self->{'oscars'}->{'host'};
}

sub get_oscars_key{
    my $self = shift;
    return $self->{'oscars'}->{'key'};
}

sub get_oscars_cert{
    my $self = shift;
    return $self->{'oscars'}->{'cert'};
}

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



=head2 get_circuits_by_state
returns the all circuits in a given state
=cut

sub get_circuits_by_state{
    my $self = shift;
    my %params = @_;

    if(!defined($params{'state'})){
	$self->_set_error("get_circuits_by_state requires state paramter to be defined");
	return undef;
    }

    my $query = "select * from circuit,circuit_instantiation where circuit_instantiation.circuit_state = ?";
    my $sth = $self->{'dbh'}->prepare($query);
    if(!defined($sth)){
	$self->_set_error("Unable to prepare Query: $query: $DBI::errstr");
	return undef;
    }

    my $res = $sth->execute($params{'state'});
    if(!$res){
	$self->_set_error("Error executing query: $DBI::errstr");
	return undef;
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

    my $domain = $self->get_local_domain_name();
	
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
        $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","node"], id => "urn:ogf:network:domain=" . $domain . ":node=" . $node->{'name'});
        $writer->startTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","address"]);
        $writer->characters($node->{'management_addr_ipv4'});
        $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","address"]);

        my $ints = $self->get_interfaces_by_node_and_state( node_id => $node->{'node_id'}, state => 'up');

        foreach my $int (@$ints){

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

            my $links = $self->get_link_by_interface_id( interface_id => $int->{'interface_id'});
            my $processed_link = 0;
            foreach my $link (@$links){
                # only show links we know about that are trunked (this is actually the interface role)                                                                                                                                   
                $processed_link = 1;
                if(!defined($link->{'remote_urn'})){
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
		$writer->characters("2-4094");
		$writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","vlanRangeAvailability"]);
		
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
                $writer->characters("2-4094");
                $writer->endTag(["http://ogf.org/schema/network/topology/ctrlPlane/20080828/","vlanRangeAvailability"]);

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


return 1;
