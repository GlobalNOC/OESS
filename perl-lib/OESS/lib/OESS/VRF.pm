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
use NetAddr::IP;
use OESS::Config;

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

    if(!defined($self->{'config'})){
        $self->{'config'} = OESS::Config->new();
    }

    if(!defined($self->{'vrf_id'}) || $self->{'vrf_id'} == -1){
        #build from model
        $self->_build_from_model();
    }else{
        $self->_fetch_from_db();
    }

    return $self;
}

=head2 _build_from_model

=cut
sub _build_from_model{
    my $self = shift;

    $self->{'name'} = $self->{'model'}->{'name'};
    $self->{'description'} = $self->{'model'}->{'description'};
    $self->{'prefix_limit'} = $self->{'model'}->{'prefix_limit'};

    $self->{'endpoints'} = ();
    #process Endpoints
    foreach my $ep (@{$self->{'model'}->{'endpoints'}}){
        $ep->{workgroup_id} = $self->{model}->{workgroup_id};

        my $ep_obj = OESS::Endpoint->new(db => $self->{'db'}, model => $ep, type => 'vrf');
        push(@{$self->{'endpoints'}}, $ep_obj);
    }

    #process Workgroups
    $self->{'workgroup'} = OESS::Workgroup->new( db => $self->{'db'}, workgroup_id => $self->{'model'}->{'workgroup_id'});

    #process user
    $self->{'created_by'} = OESS::User->new( db => $self->{'db'}, user_id => $self->{'model'}->{'created_by'});
    $self->{'last_modified_by'} = OESS::User->new(db => $self->{'db'}, user_id => $self->{'model'}->{'last_modified_by'});
    $self->{'local_asn'} = $self->{'model'}->{'local_asn'} || $self->{'config'}->local_as();

    return;
}

=head2 from_hash

=cut
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
    $self->{'state'} = $hash->{'state'};
}

=head2 _fetch_from_db

=cut
sub _fetch_from_db{
    my $self = shift;

    my $hash = OESS::DB::VRF::fetch(db => $self->{'db'}, vrf_id => $self->{'vrf_id'});
    $self->from_hash($hash);
}

=head2 to_hash

=cut
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
    $obj->{'state'} = $self->{'state'};
    $obj->{'endpoints'} = \@endpoints;
    $obj->{'prefix_limit'} = $self->prefix_limit();
    $obj->{'workgroup'} = $self->workgroup()->to_hash();
    $obj->{'created_by'} = $self->created_by()->to_hash();
    $obj->{'last_modified_by'} = $self->last_modified_by()->to_hash();
    $obj->{'created'} = $self->created();
    $obj->{'last_modified'} = $self->last_modified();
    $obj->{'local_asn'} = $self->local_asn();
    $obj->{'operational_state'} = $self->operational_state();
    return $obj;
}

=head2 vrf_id

=cut
sub vrf_id{
    my $self =shift;
    return $self->{'vrf_id'};
}

=head2 id

=cut
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

=head2 endpoints

=cut
sub endpoints{
    my $self = shift;
    my $eps = shift;

    if (!defined $eps) {
        return $self->{endpoints} || [];
    }

    $self->{endpoints} = $eps;
    return $self->{endpoints};
}

=head2 name

=cut
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

=head2 description

=cut
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

=head2 workgroup

=cut
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

=head2 update_db

=cut
sub update_db{
    my $self = shift;

    if (!defined $self->{'vrf_id'}) {
        $self->create();
        return 1;
    } else {
        return $self->_edit();
    }
}

=head2 create

=cut
sub create{
    my $self = shift;

    #need to validate endpoints
    foreach my $ep (@{$self->endpoints()}){
        if(!defined($ep) || !defined($ep->interface())){
            $self->{'logger'}->error("No Endpoint specified");
	    $self->error("No Endpoint specified");
            return 0;
        }

        if( !$ep->interface()->vlan_valid( workgroup_id => $self->workgroup()->workgroup_id(), vlan => $ep->tag() )){
            $self->{'logger'}->error("VLAN: " . $ep->tag() . " is not allowed for workgroup on interface: " . $ep->interface()->name());
	    $self->error("VLAN: " . $ep->tag() . " is not allowed for workgroup on interface: " . $ep->interface()->name());
            return 0;
        }

        #validate IP addresses for peerings
        foreach my $peer (@{$ep->peers()}){
            my $peer_ip = NetAddr::IP->new($peer->peer_ip());
            my $local_ip = NetAddr::IP->new($peer->local_ip());
            if(!$local_ip->contains($peer_ip)){
                $self->{'logger'}->error("Peer and Local IPs are not in the same subnet...");
		$self->error("Peer and Local IPs are not in the same subnet...");
                return 0;
            }
        }
    }

    #validate that we have at least 2 endpoints
    if(scalar($self->endpoints()) < 2){
        $self->{'logger'}->error("VRF Needs at least 2 endpoints");
	$self->error("VRF Needs at least 2 endpoints");
        return 0;
    }

    my $vrf_id = OESS::DB::VRF::create(db => $self->{'db'}, model => $self->to_hash());
    if ($vrf_id == -1) {
	$self->error("Could not add VRF to db.");
	return 0;
    }
    $self->{'vrf_id'} = $vrf_id;
    return 1;
}

=head2 update

=cut
sub update {
    my $self  = shift;
    my $modal = shift;

    my $endpoints = {};
    foreach my $endpoint (@{$self->{endpoints}}) {
        my $intf = $endpoint->{interface}->{name};
        my $node = $endpoint->{interface}->{node}->{name};

        $endpoints->{$node}->{$intf} = $endpoint->{tag};
    }

    # Validate we have at least 2 endpoints
    if (@{$modal->{endpoints}} < 2) {
        $self->{'logger'}->error("VRF Needs at least 2 endpoints");
	$self->error("VRF Needs at least 2 endpoints");
        return 0;
    }

    my $new_endpoints = [];

    foreach my $ep (@{$modal->{endpoints}}) {
        my $intf = $ep->{interface};
        my $node = $ep->{node};
        my $tag = $ep->{tag};

        if (!defined $tag) {
	    $self->error("Endpoint tag is missing.");
            return 0;
        }
        if (!defined $intf) {
	    $self->error("Endpoint interface is missing.");
            return 0;
        }
        if (!defined $node) {
	    $self->error("Endpoint node is missing.");
            return 0;
        }

        # VLANs already in use will come back as invalid; If previously validated continue.
        my $endpoint = OESS::Endpoint->new(db => $self->{db}, model => $ep, type => 'vrf');
        my $valid_tag = $endpoint->interface()->vlan_valid(workgroup_id => $self->workgroup()->workgroup_id(), vlan => $tag);
        my $previously_validated = defined $endpoints->{$node}->{$intf} && $endpoints->{$node}->{$intf} == $tag;

        if (!$previously_validated && !$valid_tag) {
            $self->error("Endpoint tag $tag may not be used.");
            return 0;
        }

        foreach my $peer (@{$endpoint->peers()}){
            my $peer_ip = NetAddr::IP->new($peer->peer_ip());
            my $local_ip = NetAddr::IP->new($peer->local_ip());

            if(!$local_ip->contains($peer_ip)){
		$self->error("Peer and Local IPs must be in the same subnet.");
                return 0;
            }
        }

        push @{$new_endpoints}, $endpoint;
    }

    $self->{endpoints} = $new_endpoints;

    # Maybe updated:
    $self->{name} = $modal->{name} if (defined $modal->{name});
    $self->{description} = $modal->{description} if (defined $modal->{description});
    $self->{local_asn} = $modal->{local_asn} if (defined $modal->{local_asn});

    # Always updated:
    $self->{last_modified} = $modal->{last_modified} if (defined $modal->{last_modified});
    $self->{last_modified_by} = OESS::User->new(db => $self->{'db'}, user_id => $modal->{last_modified_by}) if (defined $modal->{last_modified_by});

    return 1;
}

=head2 _edit

=cut
sub _edit {
    my $self = shift;

    my $vrf = $self->to_hash();

    $self->{db}->start_transaction();

    my $result = OESS::DB::VRF::update(db => $self->{db}, vrf => $vrf);
    if (!$result) {
        $self->{db}->rollback();
	$self->error("Could not update VRF: $result");
        return;
    }

    $result = OESS::DB::VRF::delete_endpoints(db => $self->{db}, vrf_id => $vrf->{vrf_id});
    if (!$result) {
        $self->{db}->rollback();
	$self->error("Could not remove old endpoints from VRF.");
        return;
    }

    foreach my $ep (@{$vrf->{endpoints}}) {
        $result = OESS::DB::VRF::add_endpoint(db => $self->{db}, vrf_id => $vrf->{vrf_id}, model => $ep);
        if (!$result) {
            $self->{db}->rollback();
            $self->error("Could not add endpoint to VRF.");
            return;
        }
    }

    $self->{db}->commit();

    return 1;
}

=head2 update_vrf_details

reload the vrf details from the database to make sure everything is in
sync with what should be there

=cut
sub update_vrf_details{
    my $self = shift;
    my %params = @_;

    $self->_fetch_from_db();
}

=head2 decom

=cut
sub decom{
    my $self = shift;
    my %params = @_;
    my $user_id = $params{'user_id'};
    
    foreach my $ep (@{$self->endpoints()}){
        $ep->decom();
    }

    my $res = OESS::DB::VRF::decom(db => $self->{'db'}, vrf_id => $self->{'vrf_id'}, user_id => $user_id);
    return $res;

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

=head2 prefix_limit

=cut
sub prefix_limit{
    my $self = shift;
    if(!defined($self->{'prefix_limit'})){
        return 1000;
    }
    return $self->{'prefix_limit'};
}

=head2 created_by

=cut
sub created_by{
    my $self = shift;
    my $created_by = shift;

    return $self->{'created_by'};
}

=head2 last_modified_by

=cut
sub last_modified_by{
    my $self = shift;
    return $self->{'last_modified_by'};
}


=head2 last_modified

=cut
sub last_modified{
    my $self = shift;
    return $self->{'last_modified'};
}

=head2 created

=cut
sub created{
    my $self = shift;
    return $self->{'created'};
}

=head2 local_asn

=cut
sub local_asn{
    my $self = shift;
    return $self->{'local_asn'};
}

=head2 state

=cut
sub state{
    my $self = shift;
    return $self->{'state'};
}

=head2 operational_state

=cut
sub operational_state{
    my $self = shift;
    
    my $operational_state = 1;
    foreach my $ep (@{$self->endpoints()}){
        foreach my $peer (@{$ep->peers()}){
            if($peer->operational_state() ne 'up'){
                $operational_state = 0;
            }
        }
    }

    if($operational_state){
        return "up";
    }else{
        return "down";
    }
}

1;
