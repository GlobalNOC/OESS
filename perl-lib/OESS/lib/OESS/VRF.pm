#!/usr/bin/perl

use strict;
use warnings;

package OESS::VRF;

use Log::Log4perl;

#link statuses
use constant OESS_LINK_UP       => 1;
use constant OESS_LINK_DOWN     => 0;
use constant OESS_LINK_UNKNOWN  => 2;

=head1 NAME

OESS::VRF - VRF Interaction Module

=head1 SYNOPSIS

This is a module to provide a simplified object oriented way to connect to
and interact with the OESS VRFs.

Some examples:

    use OESS::VRF;

    my $vrf = OESS::VRF->new( vrf_id => 100, db => new OESS::Database());

    my $vrf_id = $vrf->get_id();

    if (! defined $vrf_id){
        warn "Uh oh, something bad happened: " . $vrf->get_error();
        exit(1);
    }

=cut


=head2 new

    Creates a new OESS::VRF object
    requires an OESS::Database handle
    and either the details from get_vrf_details or a vrf_id

=cut

sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS.VRF");

    my %args = (
	details => undef,
	vrf_id => undef,
	db => undef,
	just_display => 0,
        link_status => undef,
        @_
        );

    my $self = \%args;

    bless $self, $class;

    $self->{'logger'} = $logger;

    if(!defined($self->{'db'})){
	$self->{'logger'}->error("No Database Object specified");
	return;
    }

    if(!defined($self->{'vrf_id'}) && !defined($self->{'details'})){
	$self->{'logger'}->error("No vrf id or details specified");
	return;
    }

    if(defined($self->{'details'})){
#	$self->_process_vrf_details();
    }else{
	$self->_load_vrf_details();
    }

    if(!defined($self->{'details'})){
	$self->{'logger'}->error("NO VRF FOUND!");
	return;
    }
    

    return $self;
}

=head2 get_prefix_limit

=cut

sub get_prefix_limit{
    my $self = shift;
    return 1000;
}

=head2 get_id

    returns the id of the circuit

=cut

sub get_id{
    my $self = shift;
    return $self->{'vrf_id'};
}

=head2 get_name

=cut

sub get_name{
    my $self = shift;
    return $self->{'details'}->{'name'};
}

=head2 update_vrf_details

    reload the vrf details from the database to make sure everything 
    is in sync with what should be there

=cut

sub update_vrf_details{
    my $self = shift;
    my %params = @_;

    $self->_load_vrf_details();
}

sub _load_vrf_details{
    my $self = shift;
    $self->{'logger'}->debug("Loading Circuit data for vrf: " . $self->{'vrf_id'});
    $self->_get_vrf_details( vrf_id => $self->{'vrf_id'});
}

sub _get_vrf_details{
    my $self = shift;
    my %params = @_;
    my $status = $params{'status'} || 'active';

    my $vrf_id = $self->{'vrf_id'};

    my $res = $self->{'db'}->_execute_query("select * from vrf where vrf_id = ?", [$vrf_id]);
    if(!defined($res) || !defined($res->[0])){
	$self->{'logger'}->error("Error fetching VRF from database");
	return;
    }

    $self->{'details'} = $res->[0];

    my $user = $self->{'db'}->get_user_by_id( user_id => $self->{'details'}->{'created_by'});

    my $workgroup = $self->{'db'}->get_workgroup_by_id( workgroup_id => $self->{'details'}->{'workgroup_id'} );

    $self->{'details'}->{'created_by'} = $user;
    $self->{'details'}->{'workgroup'} = $workgroup;
    
    #find endpoints 
    $res = $self->{'db'}->_execute_query("select vrf_ep.*, node.name as node, interface.name as int_name from vrf_ep join interface on interface.interface_id = vrf_ep.interface_id join node on node.node_id = interface.node_id where vrf_id = ? and state = ?", [$vrf_id, $status]);
    if(!defined($res) || !defined($res->[0])){
        $self->{'logger'}->error("Error fetching VRF endpoints");
        return;
    }
    
    $self->{'endpoints'} = ();

    foreach my $ep (@$res){
	my $bgp_res = $self->{'db'}->_execute_query("select * from vrf_ep_peer where vrf_ep_id = ? and state = ?",[$ep->{'vrf_ep_id'}, $status]);
	if(!defined($bgp_res) || !defined($bgp_res->[0])){
	    $bgp_res = ();
	}
	
	my @bgp;

	foreach my $bgp (@{$bgp_res}){
	    push(@bgp, $bgp);
	}


	my $int = $self->{'db'}->get_interface( interface_id => $ep->{'interface_id'});
	
	$int->{'tag'} = $ep->{'tag'};
        $int->{'node'} = $ep->{'node'};
        $int->{'node_id'} = $ep->{'node_id'};
	$int->{'bandwidth'} = $ep->{'bandwidth'};
	$int->{'state'} = $ep->{'state'};
	$int->{'vrf_ep_id'} = $ep->{'vrf_ep_id'};
	$int->{'peers'} = \@bgp;
	
	push(@{$self->{'endpoints'}}, $int);
    }

    $self->{'details'}->{'endpoints'} = $self->{'endpoints'};
    
}

=head2 on_node( $node_id )

Returns 1 if $node_id is part of a path in this vrf or 0 if it's not.

=cut
sub on_node {
    my $self    = shift;
    my $node_id = shift;

    foreach my $point (@{$self->{'endpoints'}}) {
        if ("$node_id" eq $point->{'node_id'}) {
            return 1;
        }
    }

    return 0;
}

=head2 local_asn

=cut

sub local_asn{
    my $self = shift;
    return $self->{'details'}->{'local_asn'};
}


=head2 get_details

=cut

sub get_details{
    my $self = shift;
    return $self->{'details'};
}

=head2 generate_vrf_layout

=cut

sub generate_vrf_layout{
    my $self = shift;

    my $clr = "";
    $clr .= "VRF: " . $self->{'details'}->{'name'} . "\n";
    $clr .= "Created by: " . $self->{'details'}->{'created_by'}->{'given_names'} . " " . $self->{'details'}->{'created_by'}->{'family_name'} . " at " . $self->{'details'}->{'created_on'} . " for workgroup " . $self->{'details'}->{'workgroup'}->{'name'} . "\n";
    $clr .= "Last Modified By: " . $self->{'details'}->{'last_modified_by'}->{'given_names'} . " " . $self->{'details'}->{'last_modified_by'}->{'family_name'} . " at " . $self->{'details'}->{'last_edited'} . "\n\n";
    $clr .= "Endpoints: \n";

    foreach my $endpoint (@{$self->get_endpoints()}){
	$clr .= "  " . $endpoint->{'node'} . " - " . $endpoint->{'interface'} . " VLAN " . $endpoint->{'tag'} . "\n";
    }

    my $active = $self->get_active_path();
    if ($active eq 'tertiary') {
        $active = 'default';
    }
    $clr .= "\nActive Path:\n";
    $clr .= $active . "\n";

    if($#{$self->get_path( path => 'primary')} > -1){
        $clr .= "\nPrimary Path:\n";
        foreach my $path (@{$self->get_path( path => 'primary' )}){
            $clr .= "  " . $path->{'name'} . "\n";
        }
    }

    if($#{$self->get_path( path => 'backup')} > -1){
        $clr .= "\nBackup Path:\n";
        foreach my $path (@{$self->get_path( path => 'backup' )}){
            $clr .= "  " . $path->{'name'} . "\n";
        }
    }

    if($self->{'type'} eq 'mpls'){
        # In mpls land the tertiary path is the auto-selected
        # path. Displaying 'Default' to users for less confusion.
        if($#{$self->get_path( path => 'tertiary')} > -1){
            $clr .= "\nDefault Path:\n";
            foreach my $path (@{$self->get_path( path => 'tertiary' )}){
                $clr .= "  " . $path->{'name'} . "\n";
            }
        }
    }

    return $clr;
}

=head2 generate_clr_raw

=cut

sub generate_clr_raw{
    
    my $self = shift;

    my $str = "";
    return $str;
}

=head2 get_endpoints

=cut

sub get_endpoints{
    my $self = shift;
    return $self->{'endpoints'};
}

=head2 has_primary_path

=cut

sub has_primary_path{
    my $self = shift;
    return $self->{'has_primary_path'};
}

=head2 has_backup_path

=cut

sub has_backup_path{
    my $self = shift;
    return $self->{'has_backup_path'};
}

=head2 has_tertiary_path

=cut

sub has_tertiary_path{
    my $self = shift;
    return $self->{'has_tertiary_path'};
}

=head2 get_path

=cut

sub get_path{
    my $self = shift;

    my %params = @_;

    my $path = $params{'path'};
    
    if(!defined($path)){
        $self->{'logger'}->error("Path was not defined");
        return;
    }

    $self->{'logger'}->trace("Returning links for path '$path'");
    
    if($path eq 'backup'){
        return $self->{'details'}->{'backup_links'};
    }elsif($path eq 'tertiary'){
        return $self->{'details'}->{'tertiary_links'};
    }else{
        return $self->{'details'}->{'links'};
    }
    
}

=head2 get_active_path

=cut

sub get_active_path{
    my $self = shift;
    
    return $self->{'active_path'};
}

=head2 update_mpls_path

=cut

sub update_mpls_path{
    my $self = shift;
    my %params = @_;

    my $do_commit = 1;
    if(defined($params{'do_commit'})){
        $do_commit = $params{'do_commit'};
    }

    if(!defined($params{'user_id'})){
        #if this isn't defined set the system user
        $params{'user_id'} = 1;
    }
    my $user_id = $params{'user_id'};
    my $reason = $params{'reason'};

    return if($#{$params{'links'}} == -1);

    if($self->get_type() ne 'mpls'){
        $self->{'logger'}->error("change mpls path can only be done on mpls circuits");
        return;
    }

    if ($self->has_primary_path()) {
        $self->{'logger'}->debug("Checking primary path for $self->{'circuit_id'}");

        if (_compare_links($self->get_path(path => 'primary'), $params{'links'})) {
            $self->{'logger'}->debug("Primary path selected for $self->{'circuit_id'}");
            return $self->_change_active_path(new_path => 'primary');
        }
    }

    if ($self->has_backup_path()) {
        $self->{'logger'}->info("Checking backup path for $self->{'circuit_id'}");

        if (_compare_links($self->get_path(path => 'backup'), $params{'links'})) {
            $self->{'logger'}->info("Backup path selected for $self->{'circuit_id'}");
            return $self->_change_active_path(new_path => 'backup');
        }
    }

    # After checking that any manually defined paths are not active,
    # we check that we are tracking the auto-generated path correctly;
    # This includes adding the path to the database if not already
    # existing.

    #check and see if circuit has any previously defined tertiary path
    my $query  = "select path.path_id from path where path.path_type=? and circuit_id=?";
    my $results = $self->{'db'}->_execute_query($query, ["tertiary", $self->{'circuit_id'}]);

    if(defined($results) && defined($results->[0])){

	$self->{'logger'}->debug("Tertiary path already exists...");
	my $tertiary_path_id = $results->[0]->{'path_id'};


	if(!_compare_links($self->get_path(path => 'tertiary'), $params{'links'})) {
	    my $query = "update link_path_membership set end_epoch = unix_timestamp(NOW()) where path_id = ? and end_epoch = -1";
	    $self->{'db'}->_execute_query($query,[$self->{'details'}->{'paths'}->{'tertiary'}->{'path_id'}]);
	    
	    $query = "insert into link_path_membership (end_epoch,link_id,path_id,start_epoch,interface_a_vlan_id,interface_z_vlan_id) " .
		"VALUES (-1,?,?,unix_timestamp(NOW()),?,?)";
	    
	    foreach my $link (@{$params{'links'}}) {
		$self->{'db'}->_execute_query($query, [
						  $link->{'link_id'},
						  $tertiary_path_id,
						  $self->{'circuit_id'} + 5000,
						  $self->{'circuit_id'} + 5000
					      ]);
		
	    }
	}else{
	    #nothing to do here
	}

    }else{
	$self->{'logger'}->error("No tertiary path exists...creating...");
	
        my @link_ids;
        foreach my $link (@{$params{'links'}}) {
            push(@link_ids, $link->{'link_id'});
        }

        $self->{'logger'}->debug("Creating tertiary path with links ". Dumper(@link_ids));

        my $path_id = $self->{'db'}->create_path($self->{'circuit_id'}, \@link_ids, 'tertiary');
        $self->{'paths'}->{'tertiary'}->{'path_id'} = $path_id; # Required by _change_active_path
        $self->{'has_tertiary_path'} = 1;

        my $query = "update link_path_membership set end_epoch=unix_timestamp(NOW()) where path_id=? and end_epoch=-1";
        $self->{'db'}->_execute_query($query,[$path_id]);

        $query = "insert into link_path_membership (end_epoch,link_id,path_id,start_epoch,interface_a_vlan_id,interface_z_vlan_id) VALUES (-1,?,?,unix_timestamp(NOW()),?,?)";
        foreach my $link (@{$params{'links'}}){
            $self->{'db'}->_execute_query($query, [$link->{'link_id'}, $path_id, $self->{'circuit_id'} + 5000, $self->{'circuit_id'} + 5000]);
        }

        $self->{'details'}->{'tertiary_links'} = $params{'links'};
    }

    return $self->_change_active_path(new_path => 'tertiary');
}

sub _change_active_path{
    my $self = shift;
    my %params = @_;
    
    my $current_path = $self->get_active_path();
    my $new_path = $params{'new_path'};

    if ($current_path eq $new_path) {
        # If an attempt is made to change the active path, but no
        # change is required return ok.
        $self->{'active_path'} = $current_path;
        $self->{'details'}->{'active_path'} = $current_path;
        return 1;
    }

    $self->{'db'}->_start_transaction();

    $self->{'logger'}->info("Circuit $self->{'circuit_id'} changing paths from $current_path to $new_path");

    my $query  = "select path.path_id from path where path.path_type=? and circuit_id=?";
    my $results = $self->{'db'}->_execute_query($query, [$current_path, $self->{'circuit_id'}]);
    my $old_path_id = $results->[0]->{'path_id'};

    $results = $self->{'db'}->_execute_query($query, [$new_path, $self->{'circuit_id'}]);
    my $new_path_id = $results->[0]->{'path_id'};

    $self->{'logger'}->info("Changing paths from $old_path_id to $new_path_id");


    # decom the current path instantiation
    $query = "update path_instantiation set path_instantiation.end_epoch = unix_timestamp(NOW()) " .
        "where path_instantiation.path_id = ? and path_instantiation.end_epoch = -1";
    
    my $success = $self->{'db'}->_execute_query($query, [$old_path_id]);
    if (!$success) {
	$self->{'db'}->_rollback();
        my $err = "Unable to change path_instantiation of current path to inactive.";
        $self->{'logger'}->error($err);
        $self->error($err);
        return;
    }

    # create a new path instantiation of the old path
    $query = "insert into path_instantiation (path_id, start_epoch, end_epoch, path_state) values (?, unix_timestamp(NOW()), -1, 'available')";
    $success = $self->{'db'}->_execute_query($query, [$old_path_id]);

    if (!$success) {
	$self->{'db'}->_rollback();
        my $err = "Unable to update path_instantiation table";
        $self->{'logger'}->error($err);
        $self->error($err);
        return;
    }

    $query = "update path_instantiation set path_state = 'active' where path_id=? and end_epoch=-1";
    $success = $self->{'db'}->_execute_query($query, [$new_path_id]);

    if (!$success) {
	$self->{'db'}->_rollback();
        my $err = "Unable to update path_instantiation table";
        $self->{'logger'}->error($err);
        $self->error($err);
        return;
    }


    # Update the path table
    $query = "update path set path_state='available' where path_id=?";
    $success = $self->{'db'}->_execute_query($query, [$old_path_id]);

    if (!$success) {
        $self->{'db'}->_rollback();
        my $err = "Unable to update path table";
        $self->{'logger'}->error($err);
        $self->error($err);
        return;
    }

    $query = "update path set path_state='active' where path_id=?";
    $success = $self->{'db'}->_execute_query($query, [$new_path_id]);
    
    if (!$success) {
	$self->{'db'}->_rollback();
        my $err = "Unable to update path table";
        $self->{'logger'}->error($err);
        $self->error($err);
        return;
    }

    $self->{'db'}->_commit();

    $self->{'active_path'} = $params{'new_path'};
    $self->{'details'}->{'active_path'} = $params{'new_path'};
    return 1;
}

sub _compare_links{
    my $a_links = shift;
    my $z_links = shift;

    if($#{$a_links} != $#{$z_links}){
        return 0;
    }

    my $same = 1;
    foreach my $a_link (@{$a_links}){
        my $found = 0;
        foreach my $z_link (@{$z_links}){
            if($a_link->{'name'} eq $z_link->{'name'}){
                $found = 1;
            }
        }
        
        if(!$found){
            $same = 0;
        }
    }
    
    return $same;
    
}

=head2 change_path

=cut

sub change_path {
    my $self = shift;
    my %params = @_;

    my $do_commit = 1;
    if(defined($params{'do_commit'})){
        $do_commit = $params{'do_commit'};
    }

    if(!defined($params{'user_id'})){
        #if this isn't defined set the system user
        $params{'user_id'} = 1;
    }
    my $user_id = $params{'user_id'};
    my $reason = $params{'reason'};

    if($self->get_type() ne 'openflow'){
        $self->{'logger'}->error("Change path can only be called for OpenFlow circuits");
        return;
    }

    #change the path

    if(!$self->has_backup_path()){
        $self->error("Circuit " . $self->{'name'} . " has no alternate path, refusing to try to switch to alternate.");
        return;
    }

    my $current_path = $self->get_active_path();
    my $alternate_path = 'primary';
    if($current_path eq 'primary'){
	$alternate_path = 'backup';
    }

    $self->{'logger'}->debug("Circuit ". $self->get_name()  . " is changing to " . $alternate_path);

     my $query  = "select path.path_id from path " .
                 " join path_instantiation on path.path_id = path_instantiation.path_id " .
                 "  and path_instantiation.path_state = 'available' and path_instantiation.end_epoch = -1 " .
                 " where circuit_id = ?";
    
    my $results = $self->{'db'}->_execute_query($query, [$self->{'circuit_id'}]);
    my $new_active_path_id = $results->[0]->{'path_id'};
    if($do_commit){
        $self->{'db'}->_start_transaction();
    }
    # grab the path_id of the one we're switching away from
    $query = "select path_instantiation.path_id, path_instantiation.path_instantiation_id from path " .
	" join path_instantiation on path.path_id = path_instantiation.path_id " .
	" where path_instantiation.path_state = 'active' and path_instantiation.end_epoch = -1 " .
	" and path.circuit_id = ?";
    
    $results = $self->{'db'}->_execute_query($query, [$self->{'circuit_id'}]);

    if (! defined $results || @$results < 1){
        $self->error("Unable to find path_id for current path.");
        $self->{'db'}->_rollback();
        return;
    }

    my $old_active_path_id   = @$results[0]->{'path_id'};
    my $old_instantiation    = @$results[0]->{'path_instantiation_id'};

    # decom the current path instantiation
    $query = "update path_instantiation set path_instantiation.end_epoch = unix_timestamp(NOW()) " .
             " where path_instantiation.path_id = ? and path_instantiation.end_epoch = -1";

    my $success = $self->{'db'}->_execute_query($query, [$old_active_path_id]);

    if (! $success ){
        $self->error("Unable to change path_instantiation of current path to inactive.");
        $self->{'db'}->_rollback();
        return;
    }

    # create a new path instantiation of the old path
    $query = "insert into path_instantiation (path_id, start_epoch, end_epoch, path_state) " .
             " values (?, unix_timestamp(NOW()), -1, 'available')";

    my $new_available = $self->{'db'}->_execute_query($query, [$old_active_path_id]);

    if (! defined $new_available){
        $self->error("Unable to create new available path based on old instantiation.");
        $self->{'db'}->_rollback();
        return;
    }    

        # point the internal vlan mappings from the old over to the new path instance
    #$query = "update path_instantiation_vlan_ids set path_instantiation_id = ? where path_instantiation_id = ?";
    
    #$success = $self->{'db'}->_execute_query($query, [$new_available, $old_instantiation]);

    #if (! defined $success){
    #    $self->{'logger'}->error("Unable to move internal vlan id mappings over to new path instance");
    #    $self->error("Unable to move internal vlan id mappings over to new path instance.");
    #    $self->_rollback();
    #    return;
    #}

    # at this point, the old path instantiation has been decom'd by virtue of its end_epoch
    # being set and another one has been created in 'available' state based on it.

    # now let's change the state of the old available one to active
    $query = "update path_instantiation set path_state = 'active' where path_id = ? and end_epoch = -1";    

    $success = $self->{'db'}->_execute_query($query, [$new_active_path_id]);

    if (! $success){
        $self->{'logger'}->error("Unable to change state to active in alternate path");
        $self->error("Unable to change state to active in alternate path.");
        $self->{'db'}->_rollback();
        return;
    }

    #now to add the history
    $query = "select * from circuit_instantiation where circuit_id = ? and end_epoch = -1";
    my $circuit_instantiation = $self->{'db'}->_execute_query($query,[$self->{'circuit_id'}])->[0];
    if(!defined($circuit_instantiation)){
        $self->error("Unable to fetch current circuit instantiation");
        $self->{'db'}->_rollback();
        return;
    }

    $query = "update circuit_instantiation set end_epoch = UNIX_TIMESTAMP(NOW()) where circuit_id = ? and end_epoch = -1";
    if(!defined($self->{'db'}->_execute_query($query, [$self->{'circuit_id'}]))){
        $self->error("Unable to decom old circuit instantiation.");
        $self->{'db'}->_rollback() if($do_commit);
        return
    }

    $query = "insert into circuit_instantiation (circuit_id, reserved_bandwidth_mbps, circuit_state, modified_by_user_id, end_epoch, start_epoch, loop_node, reason) values (?, ?, ?, ?, -1, unix_timestamp(now()),?,?)";
    if(!defined( $self->{'db'}->_execute_query($query, [ $self->{'circuit_id'}, 
                                                         $circuit_instantiation->{'reserved_bandwidth_mbps'},
                                                         $circuit_instantiation->{'circuit_state'},
                                                         $params{'user_id'}, 
                                                         $circuit_instantiation->{'loop_node'},
                                                         $params{'reason'} ] ))){
        $self->{'logger'}->error("Unable to create new circuit instantiation");
        $self->error("Unable to create new circuit instantiation.");
        $self->{'db'}->_rollback() if($do_commit);
        return;
    }
    
    if($do_commit){
        $self->{'db'}->_commit();
    }

    $self->{'active_path'} = $alternate_path;
    $self->{'details'}->{'active_path'} = $alternate_path;
    $self->{'logger'}->debug("Circuit " . $self->get_id() . " is now on " . $alternate_path);
    return 1;

}


=head2 get_mpls_path_type

=cut

sub get_mpls_path_type{
    my $self = shift;
    my %params = @_;

    if(!defined($params{'path'})){
	$self->{'logger'}->error("No path specified");
	return;
    }

    $self->{'logger'}->debug("MPLS Path Type: " . Data::Dumper::Dumper($self->{'details'}{'paths'}));

    if(!defined($self->{'details'}{'paths'}{$params{'path'}})){
	return;
    }

    return $self->{'details'}{'paths'}{$params{'path'}}{'mpls_path_type'};
}

=head2 get_mpls_hops

=cut

sub get_mpls_hops{
    my $self = shift;
    my %params = @_;

    my @ips;

    my $path = $params{'path'};
    if(!defined($path)){
	$self->{'logger'}->error("Fetching the path hops for undefined path");
	return \@ips;
    }

    my $start = $params{'start'};
    if(!defined($start)){
	$self->{'logger'}->error("Fetching hops requires a start");
	return \@ips;
    }

    my $end = $params{'end'};
    if(!defined($end)){
        $self->{'logger'}->error("Fetching hops requires an end");
        return \@ips;
    }
 
    return \@ips if ($end eq $start);
    
    $self->{'logger'}->debug("Path: " . $path);

    #fetch the path
    my $p = $self->get_path(path => $path);

    $self->{'logger'}->debug("Path is: " . Dumper($p));

    if(!defined($p)){
	return \@ips;
    }

    my $nodes = $self->{'db'}->get_current_nodes( mpls => 1);
    my %nodes;
    foreach my $node (@$nodes){
        $nodes{$node->{'name'}} = $node;
    }

    #build our lookup has to find our IP addresses
    my %ip_address;
    foreach my $link (@$p){
	my $node_a = $link->{'node_a'};
	my $node_z = $link->{'node_z'};

        # When using link based ip addresses
        # $ip_address{$node_a}{$node_z} = $link->{'ip_z'};
        # $ip_address{$node_z}{$node_a} = $link->{'ip_a'};

        $ip_address{$node_a}{$node_z} = $nodes{$node_z}->{'loopback_address'};
        $ip_address{$node_z}{$node_a} = $nodes{$node_a}->{'loopback_address'};
    }

    #verify that our start/end are endpoints
    my $eps = $self->get_endpoints();

    #find the next hop in the shortest path from $ep_a to $ep_z
    my @shortest_path = $self->{'graph'}->{$path}->SP_Dijkstra($start,$end);
    #ok we have the list of verticies... now to convert that into IP addresses
    if(scalar(@shortest_path) <= 1){
	#uh oh... no path!!!!
	$self->{'logger'}->error("Uh oh there is no path");
	return \@ips;
    }
    
    for(my $i=1;$i<=$#shortest_path;$i++){
	my $ip = $ip_address{$shortest_path[$i-1]}{$shortest_path[$i]};
	$self->{'logger'}->debug("  Next hop: " . $shortest_path[$i-1] . " to " . $shortest_path[$i]);
	$self->{'logger'}->debug("      Address: " . $ip);
	push(@ips, $ip);
    }

    $self->{'logger'}->debug("IP addresses: " . Dumper(@ips));

    return \@ips;
}


=head2 get_path_status

=cut

sub get_path_status{
    my $self = shift;
    my %params = @_;

    my $path = $params{'path'};
    my $link_status = $params{'link_status'};

    if(!defined($path)){
	return;
    }
    
    my %down_links;
    my %unknown_links;
    
    if(!defined($link_status)){
        my $links = $self->{'db'}->get_current_links(type => $self->{'type'});
        
        foreach my $link (@$links){


            if( $link->{'status'} eq 'down'){
                $down_links{$link->{'name'}} = $link;
            }elsif($link->{'status'} eq 'unknown'){
                $unknown_links{$link->{'name'}} = $link;
            }

        }

    }else{
        foreach my $key (keys (%{$link_status})){
            if($link_status->{$key} == OESS_LINK_DOWN){
                $down_links{$key} = 1;
            }elsif($link_status->{$key} == OESS_LINK_UNKNOWN){
                $unknown_links{$key} = 1;
            }
        }
    }

    my $path_links = $self->get_path( path => $path );

    foreach my $link (@$path_links){

        if( $down_links{ $link->{'name'} } ){
	    $self->{'logger'}->warn("Path is down because link: " . $link->{'name'} . " is down");
            return 0;
        }elsif($unknown_links{$link->{'name'}}){
	    $self->{'logger'}->warn("Path is unknown because link: " . $link->{'name'} . " is unknown");
            return 2;
        }

    }
    
    return 1;

}

=head2 state

=cut

sub state{
    my $self = shift;
    return $self->{'details'}->{'state'};
}

=head2 error

=cut

sub error{
    my $self = shift;
    my $error = shift;
    if(defined($error)){
        $self->{'error'} = $error;
    }
    return $self->{'error'};
}

1;
