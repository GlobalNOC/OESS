#!/usr/bin/perl

use strict;
use warnings;

package OESS::VRF;

use Log::Log4perl;

#link statuses
use constant OESS_LINK_UP       => 1;
use constant OESS_LINK_DOWN     => 0;
use constant OESS_LINK_UNKNOWN  => 2;

use Data::Dumper;
use OESS::DB;
use OESS::Endpoint;
use OESS::Workgroup;

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

    if(!defined($self->{'vrf_id'}) || $self->{'vrf_id'} == -1){
        #build from model
        $self->_build_from_model();
    }else{
        $self->_fetch_from_db();
    }

    return $self;
}

<<<<<<< HEAD
sub _build_from_model{
=======
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
>>>>>>> cloud
    my $self = shift;

    warn Dumper($self->{'model'});

    $self->{'name'} = $self->{'model'}->{'name'};
    $self->{'description'} = $self->{'model'}->{'description'};
    $self->{'prefix_limit'} = $self->{'model'}->{'prefix_limit'};

<<<<<<< HEAD
    $self->{'endpoints'} = ();
    #process Endpoints
    foreach my $ep (@{$self->{'model'}->{'endpoints'}}){
        push(@{$self->{'endpoints'}},OESS::Endpoint->new( db => $self->{'db'}, model => $ep, type => 'vrf'));
    }
=======
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
>>>>>>> cloud
    
    #process Workgroups
    $self->{'workgroup'} = OESS::Workgroup->new( db => $self->{'db'}, workgroup_id => $self->{'model'}->{'workgroup_id'});

    #process user
    $self->{'created_by'} = OESS::User->new( db => $self->{'db'}, user_id => $self->{'model'}->{'created_by'});
    $self->{'last_modified_by'} = OESS::User->new(db => $self->{'db'}, user_id => $self->{'model'}->{'last_modified_by'});
    $self->{'local_asn'} = $self->{'model'}->{'local_asn'} || 55038;

    return;
}

<<<<<<< HEAD
sub from_hash{
    my $self = shift;
    my $hash = shift;

    $self->{'endpoints'} = $hash->{'endpoints'};
    $self->{'name'} = $hash->{'name'};
    $self->{'description'} = $hash->{'description'};
    $self->{'prefix_limit'} = $hash->{'prefix_limit'};
    $self->{'workgroup'} = $hash->{'workgroup'};
    $self->{'created_by'} = $hash->{'created_by'};
    $self->{'last_modified_by'} = $hash->{'last_modified_by'};
    $self->{'created'} = $hash->{'created'};
    $self->{'last_modified'} = $hash->{'last_modified'};
    $self->{'local_asn'} = $hash->{'local_asn'};
=======
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
    return $self->_get_vrf_details();
>>>>>>> cloud
}

sub _fetch_from_db{
    my $self = shift;

    my $hash = OESS::DB::VRF::fetch(db => $self->{'db'}, vrf_id => $self->{'vrf_id'});
    $self->from_hash($hash);

}

sub to_hash{
    my $self = shift;

    my $obj;

    $obj->{'name'} = $self->name();
    $obj->{'vrf_id'} = $self->vrf_id();
    $obj->{'description'} = $self->description();
    my @endpoints;
    foreach my $endpoint (@{$self->endpoints()}){
        push(@endpoints, $endpoint->to_hash());
    }

    $obj->{'endpoints'} = \@endpoints;
    $obj->{'prefix_limit'} = $self->prefix_limit();
    $obj->{'workgroup'} = $self->workgroup()->to_hash();
    $obj->{'created_by'} = $self->created_by()->to_hash();
    $obj->{'last_modified_by'} = $self->last_modified_by()->to_hash();
    $obj->{'created'} = $self->created();
    $obj->{'last_modified'} = $self->last_modified();
    $obj->{'local_asn'} = $self->local_asn();

    return $obj;
}

sub vrf_id{
    my $self =shift;
    return $self->{'vrf_id'};
}

sub id{
    my $self = shift;
    my $id = shift;

    if(!defined($id)){
        return $self->{'vrf_id'};
    }else{
        $self->{'vrf_id'} = $id;
        return $self->{'vrf_id'};
    }
}

sub endpoints{
    my $self = shift;
    my $eps = shift;

    if(!defined($eps)){
        if(!defined($self->{'endpoints'})){
            return []
        }
        return $self->{'endpoints'};
    }else{
        return [];
    }
}

sub name{
    my $self = shift;
    my $name = shift;
    
    if(!defined($name)){
        return $self->{'name'};
    }else{
        $self->{'name'} = $name;
        return $self->{'name'};
    }
}

sub description{
    my $self = shift;
    my $description = shift;

    if(!defined($description)){
        return $self->{'description'};
    }else{
        $self->{'description'} = $description;
        return $self->{'description'};
    }
}

sub workgroup{
    my $self = shift;
    my $workgroup = shift;

    if(!defined($workgroup)){

        return $self->{'workgroup'};
    }else{
        $self->{'workgroup'} = $workgroup;
        return $self->{'workgroup'};
    }
}

sub update_db{
    my $self = shift;

    if(!defined($self->{'vrf_id'})){
        $self->create();
    }else{
        $self->_edit();
    }
}

sub create{
    my $self = shift;
    
    my $vrf_id = OESS::DB::VRF::create(db => $self->{'db'}, model => $self->to_hash());
    $self->{'vrf_id'} = $vrf_id;
    
}

sub _edit{
    my $self = shift;
    
    

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

sub prefix_limit{
    my $self = shift;
    return $self->{'prefix_limit'};
}

sub created_by{
    my $self = shift;
    my $created_by = shift;

    return $self->{'created_by'};
}

sub last_modified_by{
    my $self = shift;
    return $self->{'last_modified_by'};
}

<<<<<<< HEAD
sub last_modified{
    my $self = shift;
    return $self->{'last_modified'};
}
=======
=head2 state

=cut

sub state{
    my $self = shift;
    return $self->{'details'}->{'state'};
}

=head2 error
>>>>>>> cloud

sub created{
    my $self = shift;
    return $self->{'created'};
}

sub local_asn{
    my $self = shift;
    return $self->{'local_asn'};
}

1;
