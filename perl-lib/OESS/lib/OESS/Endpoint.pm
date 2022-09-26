#!/usr/bin/perl

use strict;
use warnings;

package OESS::Endpoint;

use OESS::DB;
use OESS::DB::Endpoint;
use OESS::DB::Peer;
use OESS::Interface;
use OESS::Entity;
use OESS::Node;
use OESS::Peer;
use OESS::Entity;
use Data::Dumper;


=head1 OESS::Endpoint

An C<Endpoint> represents an edge connection of a circuit or vrf.

=cut

=head2 new

B<Example 0:>

    my $ep = new OESS::Endpoint(
        db => $db,
        circuit_ep_id => 100,
        vrf_ep_id     => 100
    }

    # or

    my $ep = new OESS::Endpoint(
        db => $db,
        model => {
            entity              => 'mx960-1',
            entity_id           => 3,
            node                => 'test.grnoc.iu.edu',
            node_id             => 2,
            interface           => 'xe-7/0/2',
            interface_id        => 57,
            unit                => 6,
            tag                 => 6,
            inner_tag           => undef,
            bandwidth           => 0,
            cloud_account_id    => undef,
            cloud_connection_id => undef,
            mtu                 => 9000,
            operational_state   => 'up',
            state               => 'active',
        }
    )

B<Example 1:>

    my $json = {
        inner_tag           => undef,      # Inner VLAN tag (qnq only)
        tag                 => 1234,       # Outer VLAN tag
        cloud_account_id    => '',         # AWS account or GCP pairing key
        cloud_connection_id => '',         # Probably shouldn't exist as an arg
        entity              => 'us-east1', # Interfaces to select from
        bandwidth           => 100,        # Acts as an interface selector and validator
        workgroup_id        => 10,         # Acts as an interface selector and validator
        mtu                 => 9000,
        unit                => 345,
        state               => 'active',
    };
    my $endpoint = OESS::Endpoint->new(db => $db, type => 'vrf', model => $json);

B<Example 2:>

    my $json = {
        inner_tag           => undef,      # Inner VLAN tag (qnq only)
        tag                 => 1234,       # Outer VLAN tag
        cloud_account_id    => '',         # AWS account or GCP pairing key
        cloud_connection_id => '',         # Probably shouldn't exist as an arg
        node                => 'switch.1', # Name of node to select
        interface           => 'xe-7/0/1', # Name of interface to select
        bandwidth           => 100,        # Acts as an interface validator
        workgroup_id        => 10,         # Acts as an interface validator
        mtu                 => 9000,
        unit                => 345,
        state               => 'active',
    };
    my $endpoint = OESS::Endpoint->new(db => $db, type => 'vrf', model => $json);

=cut
sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS.Endpoint");

    my %args = (
        details => undef,
        vrf_id => undef,
        db => undef,
        @_
    );

    my $self = \%args;
    
    bless $self, $class;

    $self->{'logger'} = $logger;

    if(!defined($self->{'db'})){
        $self->{'logger'}->error("No Database Object specified");
        return;
    }

    if ((defined($self->circuit_id()) && $self->circuit_id() != -1) ||
        (defined($self->vrf_endpoint_id()) && $self->vrf_endpoint_id() != -1)){
        $self->{model} = $self->_fetch_from_db();
    }
    if (!defined $self->{model}) {
        $self->{logger}->error("Couldn't load Endpoint object from database or model.");
        return;
    }
    $self->from_hash($self->{model});

    return $self;
}

=head2 to_hash

=cut
sub to_hash{
    my $self = shift;
    my $obj;

    $obj->{'type'} = $self->{'type'};
    $obj->{'interface'} = $self->{'interface'};
    $obj->{'interface_id'} = $self->{'interface_id'};
    $obj->{'node'} = $self->{'node'};
    $obj->{'short_node_name'} = $self->{'short_node_name'};
    $obj->{'node_id'} = $self->{'node_id'};
    $obj->{'controller'} = $self->{'controller'};
    $obj->{'description'} = $self->{'description'};
    $obj->{'operational_state'} = $self->{'operational_state'};
    $obj->{'inner_tag'} = $self->inner_tag();
    $obj->{'tag'} = $self->tag();
    $obj->{'bandwidth'} = $self->{'bandwidth'};
    $obj->{cloud_account_id} = $self->cloud_account_id();
    $obj->{cloud_connection_id} = $self->cloud_connection_id();
    # cloud_interconnect_id omitted from hash to ensure hidden
    $obj->{cloud_interconnect_type} = $self->cloud_interconnect_type;
    $obj->{'state'} = $self->{'state'};

    $obj->{'mtu'} = $self->mtu();
    $obj->{'jumbo'} = ($self->mtu() > 1500) ? 1 : 0;
    $obj->{'unit'} = $self->unit();

    # TODO There's no reason for this Endpoint object to track the
    # Entity used to select its Interface. Removing this would
    # probably simplify a few things, but will require a bit of
    # testing to ensure this relationship isn't used elsewhere.

    $obj->{'entity'} = $self->entity;
    $obj->{'entity_id'} = $self->entity_id;

    if ($self->{'type'} eq 'vrf') {
        $obj->{'peers'} = [];
        foreach my $peer (@{$self->{'peers'}}){
            push(@{$obj->{'peers'}}, $peer->to_hash());
        }
        $obj->{'vrf_id'} = $self->vrf_id();
        $obj->{'vrf_endpoint_id'} = $self->vrf_endpoint_id();
    } else {
        $obj->{'circuit_id'} = $self->circuit_id();
        $obj->{'circuit_ep_id'} = $self->circuit_ep_id();
        $obj->{'start_epoch'} = $self->{start_epoch};
    }

    return $obj;
}

=head2 from_hash

The default selection method is to find the first interface that has
supports C<bandwidth> and has C<tag> available.

As there is only one interface per AWS Entity there is no special
selection method.

Interface selection for a GCP Entity is based purely on the user
provided GCP pairing key.

Interface selection for an Azure Entity is somewhat irrelevent. Each
interface of the Azure port pair is configured similarly with the only
difference between the two being the peer addresses assigned to each.

=cut
sub from_hash{
    my $self = shift;
    my $hash = shift;

    $self->{'type'} = $hash->{'type'};
    $self->{'interface'} = $hash->{'interface'};
    $self->{'interface_id'} = $hash->{'interface_id'};
    $self->{'node'} = $hash->{'node'};
    $self->{'short_node_name'} = $hash->{'short_node_name'};
    $self->{'node_id'} = $hash->{'node_id'};
    $self->{'controller'} = $hash->{'controller'};
    $self->{'description'} = $hash->{'description'};
    $self->{'operational_state'} = $hash->{'operational_state'};
    $self->{'inner_tag'} = $hash->{'inner_tag'};
    $self->{'tag'} = $hash->{'tag'};
    $self->{'bandwidth'} = $hash->{'bandwidth'};
    $self->{cloud_account_id} = $hash->{cloud_account_id};
    $self->{cloud_connection_id} = $hash->{cloud_connection_id};
    $self->{cloud_interconnect_id} = $hash->{cloud_interconnect_id};
    $self->{cloud_interconnect_type} = $hash->{cloud_interconnect_type};
    # Since l2 endpoints lacked state at one point in time, endpoints
    # with an undef state are assumed active on load.
    $self->{'state'} = $hash->{'state'} || 'active';
    $self->{'mtu'} = $hash->{'mtu'};
    $self->{'unit'} = $hash->{'unit'};

    if ($self->{'type'} eq 'vrf' || (!defined $hash->{'circuit_edge_id'} && !defined $hash->{'circuit_ep_id'})) {
        # $self->{'peers'} = $hash->{'peers'};
        $self->{'vrf_id'} = $hash->{'vrf_id'};
        $self->{'vrf_endpoint_id'} = $hash->{'vrf_endpoint_id'} || $hash->{'vrf_ep_id'};

        # if (defined $hash->{peers}) {
        #     $self->{peers} = [];
        #     foreach my $peer (@{$hash->{peers}}) {
        #         push(@{$self->{peers}}, new OESS::Peer(db => $self->{db}, model => $peer));
        #     }
        # }
    } else {
        $self->{'circuit_id'} = $hash->{'circuit_id'};
        $self->{'circuit_ep_id'} = $hash->{'circuit_edge_id'} || $hash->{'circuit_ep_id'};
        $self->{start_epoch} = $hash->{start_epoch};
    }

    $self->{'entity'} = $hash->{'entity'};
    $self->{'entity_id'} = $hash->{'entity_id'};
}

=head2 _fetch_from_db

=cut
sub _fetch_from_db{
    my $self = shift;

    my $db = $self->{'db'};
    my $hash;

    if ($self->{'type'} eq 'circuit') {
        my ($data, $err) = OESS::DB::Endpoint::fetch_all(
            db => $self->{db},
            circuit_id => $self->{circuit_id},
            interface_id => $self->{interface_id}
        );
        if (!defined $err) {
            $hash = $data->[0];
        }
    } else {
        my ($data, $err) = OESS::DB::Endpoint::fetch_all(
            db => $db,
            vrf_ep_id => $self->{vrf_endpoint_id}
        );
        if (defined $err) {
            $self->{logger}->error($err);
            return;
        } else {
            $hash = $data->[0];
        }
    }

    return $hash;
}

=head2 load_peers

=cut
sub load_peers {
    my $self = shift;

    if (!defined $self->{vrf_endpoint_id}) {
        warn 'Currently no support for Peers on a Circuit.';
        return 1;
    }

    my ($peer_datas, $error) = OESS::DB::Peer::fetch_all(
        db => $self->{db},
        vrf_ep_id => $self->{vrf_endpoint_id}
    );
    if (defined $error) {
        $self->{logger}->error($error);
        return;
    }

    $self->{peers} = [];
    foreach my $data (@$peer_datas) {
        my $peer = new OESS::Peer(db => $self->{db}, model => $data);
        push @{$self->{peers}}, $peer;
    }

    return 1;
}

=head2 add_peer

    $endpoint->add_peer(new OESS::Peer(...));

=cut
sub add_peer {
    my $self = shift;
    my $peer = shift;

    push @{$self->{peers}}, $peer;
}

=head2 get_peer

    my $ep = $endpoint->get_peer(
        vrf_ep_peer_id => 100
    );

get_peer returns the Peer identified by C<vrf_ep_peer_id>.

=cut
sub get_peer {
    my $self = shift;
    my $args = {
        vrf_ep_peer_id => undef,
        @_
    };

    if (!defined $args->{vrf_ep_peer_id}) {
        return;
    }

    foreach my $peer (@{$self->{peers}}) {
        if ($args->{vrf_ep_peer_id} eq $peer->{vrf_ep_peer_id}) {
            return $peer;
        }
    }

    return;
}

=head2 remove_peer

    my $ok = $endpoint->remove_peer(
        vrf_ep_peer_id => 100
    );

remove_peer removes the peer identified by C<vrf_ep_peer_id> from this
Endpoint.

=cut
sub remove_peer {
    my $self = shift;
    my $vrf_ep_peer_id = shift;

    if (!defined $vrf_ep_peer_id) {
        return;
    }

    my $new_peers = [];
    foreach my $ep (@{$self->{peers}}) {
        if ($vrf_ep_peer_id == $ep->{vrf_ep_peer_id}) {
            next;
        }
        push @$new_peers, $ep;
    }
    $self->{peers} = $new_peers;

    return 1;
}

=head2 get_endpoints_on_interface

=cut
sub get_endpoints_on_interface{
    my %args = @_;
    my $db = $args{'db'};
    my $interface_id = $args{'interface_id'};
    my $state = $args{'state'} || 'active';
    my $type = $args{'type'} || 'all';
    my @results;

    # Gather all VRF endpoints
    if ($type eq 'all' || $type eq 'vrf') {
        my $endpoints = OESS::DB::VRF::fetch_endpoints_on_interface(
            db => $db,
            interface_id => $interface_id,
            state => $state
        );
        foreach my $endpoint (@$endpoints) {
            push @results, OESS::Endpoint->new(db => $db, type => 'vrf', vrf_endpoint_id => $endpoint->{'vrf_ep_id'});
        }
    }

    # Gather all Circuit endpoints
    if ($type eq 'all' || $type eq 'circuit') {
        my $endpoints = OESS::DB::Circuit::fetch_endpoints_on_interface(
            db => $db,
            interface_id => $interface_id
        );
        foreach my $endpoint (@$endpoints) {
            push @results, OESS::Endpoint->new(db => $db, type => 'circuit', model => $endpoint);
        }
    }

    return \@results;
}

=head2 cloud_account_id

=cut
sub cloud_account_id {
    my $self = shift;
    my $value = shift;
    if (defined $value) {
        $self->{cloud_account_id} = $value;
    }
    return $self->{cloud_account_id};
}

=head2 cloud_connection_id

=cut
sub cloud_connection_id {
    my $self = shift;
    my $value = shift;
    if (defined $value) {
        $self->{cloud_connection_id} = $value;
    }
    return $self->{cloud_connection_id};
}

=head2 cloud_interconnect_id

=cut
sub cloud_interconnect_id {
    my $self = shift;
    return $self->{cloud_interconnect_id};
}

=head2 cloud_interconnect_type

=cut
sub cloud_interconnect_type {
    my $self = shift;
    return $self->{cloud_interconnect_type};
}

=head2 interface

=cut
sub interface{
    my $self = shift;
    my $interface = shift;

    if(defined($interface)){
        $self->{'interface'} = $interface;
    }

    return $self->{'interface'};
}

=head2 interface_id

=cut
sub interface_id{
    my $self = shift;
    my $interface_id = shift;

    if(defined($interface_id)){
        $self->{'interface_id'} = $interface_id;
    }

    return $self->{'interface_id'};
}

=head2 controller

=cut
sub controller {
    my $self = shift;
    return $self->{'controller'};
}

=head2 description

=cut
sub description{
    my $self = shift;
    my $description = shift;

    if(defined($description)){
        $self->{'description'} = $description;
    }
    return $self->{'description'};
}

=head2 node

=cut
sub node{
    my $self = shift;
    return $self->{'node'};
}

=head2 short_node_name

=cut
sub short_node_name{
    my $self = shift;
    return $self->{'short_node_name'};
}

=head2 node_id

=cut
sub node_id {
    my $self = shift;
    return $self->{'node_id'};
}

=head2 type

=cut
sub type{
    my $self = shift;
    $self->{'type'};
}

=head2 mtu

=cut
sub mtu {
    my $self = shift;
    my $mtu = shift;

    if (defined $mtu) {
        $self->{'mtu'} = $mtu;
    }
    return $self->{'mtu'};
}

=head2 peers

=cut
sub peers{
    my $self = shift;
    my $peers = shift;

    if(defined($peers)){
        $self->{'peers'} = $peers;
    }

    if(!defined($self->{'peers'})){
        return [];
    }

    return $self->{'peers'};
}

=head2 inner_tag

=cut
sub inner_tag{
    my $self = shift;
    my $inner_tag = shift;

    if (defined $inner_tag) {
        $self->{'inner_tag'} = $inner_tag;
    }
    return $self->{'inner_tag'};
}

=head2 tag

=cut
sub tag{
    my $self = shift;
    my $tag = shift;

    if (defined $tag) {
        $self->{'tag'} = $tag;
    }
    return $self->{'tag'};
}

=head2 bandwidth

=cut
sub bandwidth{
    my $self = shift;
    my $bandwidth = shift;
    if (defined $bandwidth) {
        $self->{'bandwidth'} = $bandwidth;
    }
    return $self->{'bandwidth'};
}

=head2 vrf_endpoint_id

=cut
sub vrf_endpoint_id{
    my $self = shift;
    return $self->{'vrf_endpoint_id'};
}

=head2 vrf_id

=cut
sub vrf_id{
    my $self = shift;
    return $self->{'vrf_id'};
}

=head2 circuit_id

=cut
sub circuit_id{
    my $self = shift;
    return $self->{'circuit_id'};
}

=head2 start_epoch

=cut
sub start_epoch{
    my $self = shift;
    my $start_epoch = shift;
    if(defined($start_epoch)) {
        $self->{start_epoch} = $start_epoch;
    }
    return $self->{start_epoch};
}

=head2 state

=cut
sub state {
    my $self = shift;
    my $state = shift;
    if (defined $state) {
        $self->{'state'} = $state;
    }
    return $self->{'state'};
}

=head2 circuit_ep_id

=cut
sub circuit_ep_id{
    my $self = shift;
    return $self->{'circuit_ep_id'};
}

=head2 entity

=cut
sub entity{
    my $self = shift;
    return $self->{'entity'};
}

=head2 entity_id

=cut
sub entity_id{
    my $self = shift;
    return $self->{'entity_id'};
}

=head2 unit

=cut
sub unit{
    my $self = shift;
    my $unit = shift;

    if(defined($unit)){
        $self->{'unit'} = $unit;
    }

    return $self->{'unit'};
}

=head2 workgroup_id

=cut
sub workgroup_id {
    my $self = shift;
    my $workgroup_id = shift;
    if (defined $workgroup_id) {
        $self->{'workgroup_id'} = $workgroup_id;
    }
    return $self->{'workgroup_id'};
}

=head2 decom

=cut
sub decom{
    my $self = shift;

    my $res;
    if($self->type() eq 'vrf'){
        foreach my $peer (@{$self->peers()}){
            $peer->decom();
        }

        $res = OESS::DB::VRF::decom_endpoint(db => $self->{'db'}, vrf_endpoint_id => $self->vrf_endpoint_id());

    }else{

        $res = OESS::DB::Circuit::decom_endpoint(db => $self->{'db'}, circuit_endpoint_id => $self->circuit_ep_id());

    }

    return $res;

}

=head2 update_db_vrf

=cut
sub update_db_vrf{
    my $self = shift;
    my $endpoint = shift;

    my $result = OESS::DB::Endpoint::update_vrf(db => $self->{db},
                        endpoint => $endpoint);
    if(!defined($result)){
        $self->{db}->rollback();
        return $self->{db}->{error};
    }
    return undef;
}

=head2 update_db_circuit

=cut
sub update_db_circuit{
    my $self = shift;
    my $endpoint = shift;

    # TODO: Update end_epoch for circuits in update_circuit_edge_membership
    my $result = OESS::DB::Endpoint::update_circuit_edge_membership(
        db       => $self->{db},
        endpoint => $endpoint
    );
    if(!defined($result)){
        return $self->{db}->{error};
    }
    return;
}

=head2 update_db

    my $err = $ep->update_db;

=cut 
sub update_db {
    my $self = shift;
    my $error = undef;

    my $validation_err = $self->_validate;
    if (defined $validation_err) {
        return $validation_err;
    }

    my $unit = OESS::DB::Endpoint::find_available_unit(
        db            => $self->{db},
        interface_id  => $self->{interface_id},
        tag           => $self->{tag},
        inner_tag     => $self->{inner_tag},
        circuit_ep_id => $self->{circuit_ep_id},
        vrf_ep_id     => $self->{vrf_endpoint_id}
    );
    if (!defined $unit) {
        return "Couldn't update Endpoint: Couldn't find an available Unit.";
    }
    $self->{unit} = $unit;

    my $hash = $self->to_hash;

    if ($self->type() eq 'vrf' || defined $self->{vrf_endpoint_id}) {
        $error = $self->update_db_vrf($hash);
    } elsif ($self->type() eq 'circuit' || defined $self->{circuit_ep_id}) {
        $error = $self->update_db_circuit($hash);
    } else {
        $error = 'Unknown Endpoint type specified.';
    }

    my ($cloud_conn_ep_id, $err) = OESS::DB::Endpoint::update_cloud(
        db => $self->{db},
        endpoint => $hash
    );
    if (defined $err) {
        return $err;
    }

    return $error;
}

=head2 move_endpoints

=cut
sub move_endpoints{
    my %args = @_;
    my $db = $args{db};
    my $orig_interface_id  = $args{orig_interface_id};
    my $new_interface_id   = $args{new_interface_id};
    my $type   = $args{type} || 'all';

    my $used_vlans = {};
    my $used_units = {};

    # Gather occupied vlans on the new interface 
    my $existing_endpoints = get_endpoints_on_interface(
        db => $db,
        interface_id => $new_interface_id
    );
    foreach my $endpoint (@$existing_endpoints) {
        if (defined $endpoint->inner_tag) {
            # Note tag pairs for QnQ tagged Endpoints
            $used_vlans->{$endpoint->tag}->{$endpoint->inner_tag} = 1;
        } else {
            $used_vlans->{$endpoint->tag} = 1;
        }

        $used_units->{$endpoint->unit} = 1;
    }

    # Gather the endpoints we want to attempt to move
    my $moving_endpoints = get_endpoints_on_interface(
        db => $db,
        interface_id => $orig_interface_id,
        type => $type
    );
    foreach my $endpoint (@$moving_endpoints) {
        # Verify tags on our moving Endpoints do not conflict with our
        # existing Endpoints.
        if (defined $endpoint->inner_tag) {
            if ($used_vlans->{$endpoint->tag} == 1) {
                warn 'Outer VLAN is already used in a single VLAN tagged context on the destination Interface.';
                next;
            }

            if (defined $used_vlans->{$endpoint->tag}->{$endpoint->inner_tag}) {
                warn 'QnQ tagged VLAN is already in use on the destination Interface.';
                next;
            }
        } else {
            if ($used_vlans->{$endpoint->tag} == 1) {
                warn 'VLAN is already in use on the destination Interface.';
                next;
            }
        }

        my $intf = OESS::Interface->new(db => $db, interface_id => $new_interface_id);

        # If Unit conflict exists generate a new one.
        if (defined $used_units->{$endpoint->unit}) {
            my $new_unit_number = $intf->find_available_unit(
                interface_id => $intf->interface_id,
                tag          => $endpoint->tag,
                inner_tag    => $endpoint->inner_tag
            );
            $endpoint->unit($new_unit_number);
        }

        $endpoint->{interface} = $intf->name();
        $endpoint->{interface_id} = $intf->interface_id();
        $endpoint->update_db();
    }
    return 1;
}

=head2 create

    $db->start_transaction;
    my ($id, $err) = $ep->create(
        circuit_id   => 100, # Optional
        vrf_id       => 100  # Optional
        workgroup_id => 100
    );
    if (defined $err) {
        $db->rollback;
        warn $err;
    }

create saves this Endpoint along with its Peers to the database. This
method B<must> be wrapped in a transaction and B<shall> only be used
to create a new Endpoint.

=cut
sub create {
    my $self = shift;
    my $args = {
        circuit_id   => undef,
        vrf_id       => undef,
        @_
    };

    if (!defined $self->{db}) {
        $self->{'logger'}->error("Couldn't create Endpoint: DB handle is missing.");
        return (undef, "Couldn't create Endpoint: DB handle is missing.");
    }

    my $unit = OESS::DB::Endpoint::find_available_unit(
        db            => $self->{db},
        interface_id  => $self->{interface_id},
        tag           => $self->{tag},
        inner_tag     => $self->{inner_tag}
    );
    if (!defined $unit) {
        $self->{'logger'}->error("Couldn't create Endpoint: Couldn't find an available Unit.");
        return (undef, "Couldn't create Endpoint: Couldn't find an available Unit.");
    }
    $self->{unit} = $unit;

    my $validation_err = $self->_validate;
    if (defined $validation_err) {
        $self->{'logger'}->error("Couldn't create Endpoint: $validation_err");
        return (undef, "Couldn't create Endpoint: $validation_err");
    }

    if (defined $args->{circuit_id}) {
        my $ep_data = $self->to_hash;
        $ep_data->{circuit_id} = $args->{circuit_id};

        my $circuit_ep_id = OESS::DB::Endpoint::add_circuit_edge_membership(
            db => $self->{db},
            endpoint => $ep_data
        );
        if (!defined $circuit_ep_id) {
            $self->{'logger'}->error("Couldn't create Endpoint: " . $self->{db}->get_error);
            return (undef, "Couldn't create Endpoint: " . $self->{db}->get_error);
        }

        $self->{circuit_ep_id} = $circuit_ep_id;
        $self->{circuit_id} = $args->{circuit_id};

        my ($cloud_conn_ep_id, $err) = OESS::DB::Endpoint::update_cloud(
            db => $self->{db},
            endpoint => $self->to_hash
        );
        if (defined $err) {
            $self->{'logger'}->error("Couldn't create Endpoint: $err");
            return (undef, "Couldn't create Endpoint: $err");
        }
        return ($circuit_ep_id, undef);

    } elsif (defined $args->{vrf_id}) {
        my $ep_data = $self->to_hash;
        $ep_data->{vrf_id} = $args->{vrf_id};

        my ($vrf_ep_id, $vrf_ep_err) = OESS::DB::Endpoint::add_vrf_ep(
            db => $self->{db},
            endpoint => $ep_data
        );
        if (defined $vrf_ep_err) {
            $self->{'logger'}->error("Couldn't create Endpoint: $vrf_ep_err");
            return (undef, "Couldn't create Endpoint: $vrf_ep_err");
        }

        $self->{vrf_endpoint_id} = $vrf_ep_id;
        $self->{vrf_id} = $args->{vrf_id};

        my ($cloud_conn_ep_id, $err) = OESS::DB::Endpoint::update_cloud(
            db => $self->{db},
            endpoint => $self->to_hash
        );
        if (defined $err) {
            $self->{'logger'}->error("Couldn't create Endpoint: $err");
            return (undef, "Couldn't create Endpoint: $err");
        }
        return ($vrf_ep_id, undef);

    } else {
        $self->{'logger'}->error("Couldn't create Endpoint: No associated Circuit or VRF identifier specified.");
        return (undef, "Couldn't create Endpoint: No associated Circuit or VRF identifier specified.");
    }
}

=head2 remove

    my $error = $endpoint->remove;
    if (defined $error) {
        warn $error;
    }

remove deletes this endpoint from the
circuit_edge_interface_membership or vrf_ep table depending on if it's
a Circuit or VRF Endpoint. This method should be wrapped in a
transaction.

=cut
sub remove {
    my $self = shift;
    my $args = { @_ };

    if (!defined $self->{db}) {
        $self->{logger}->error("Couldn't remove Endpoint: DB handle is missing.");
        return "Couldn't remove Endpoint: DB handle is missing.";
    }

    my $endpoint = $self->to_hash;

    if ($self->type eq 'vrf' || defined $self->{vrf_endpoint_id}) {
        my $result = OESS::DB::Endpoint::remove_vrf_peers(
            db => $self->{db},
            endpoint => $endpoint
        );
        if (!defined $result) {
            return $self->{db}->{error};
        }

        my $error = OESS::DB::Endpoint::remove_vrf_ep(
            db => $self->{db},
            vrf_ep_id => $endpoint->{vrf_endpoint_id}
        );
        return $error if (defined $error);
    }
    elsif ($self->type eq 'circuit' || defined $self->{circuit_ep_id}) {
        my $result = OESS::DB::Endpoint::remove_circuit_edge_membership(
            db       => $self->{db},
            endpoint => $endpoint
        );
        if (!defined $result) {
            return $self->{db}->{error};
        }
    }
    else {
        return 'Unknown Endpoint type specified.';
    }

    return;
}

=head2 _validate

    my $err = $ep->_validate;

_validate indicates to the user if any values are known to be
invalid. Returns a C<string> describing incompatibility or C<undef> on
success. Automatically called on C<< $self->create >> and C<<
$self->update >>.

=cut
sub _validate {
    my $self = shift;

    if (defined $self->{inner_tag}) {
        return 'Endpoint->{inner_tag} must be 1 to 4094 inclusive.' if ($self->{inner_tag} < 1 || $self->{inner_tag} > 4094);
    }

    return 'Endpoint->{tag} must be 1 to 4095 inclusive.' if ($self->{tag} < 1 || $self->{tag} > 4095);

    return;
}

1;
