#!/usr/bin/perl

use strict;
use warnings;

package OESS::DB::Circuit;

use OESS::Endpoint;
use OESS::Peer;
use OESS::Interface;
use OESS::User;
use OESS::Workgroup;

use Data::Dumper;

=head2 create

    my $id = OESS::DB::Circuit::create(
        db => $db,
        model => {
            name                => $name,
            description         => $description,
            user_id             => $user_id,
            workgroup_id        => $workgroup_id,
            provision_time      => '',                   # Optional
            remove_time         => '',                   # Optional
            remote_url          => $remote_url,          # Optional
            remote_requester    => $remote_requester,    # Optional
            external_identifier => $external_identifier  # Optional
        }
    );

=cut
sub create {
    my $args = {
        db => undef,
        model => undef,
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};
    return (undef, 'Required argument `model` is missing.') if !defined $args->{model};

    my $circuit_state = 'active';
    if (defined $args->{model}->{provision_time}) {
        # TODO add provision event
        $circuit_state = 'scheduled';
    }

    if (defined $args->{model}->{remove_time}) {
        # TODO add remove event
    }

    my $circuit = [
        $args->{model}->{name},
        $args->{model}->{description},
        $args->{model}->{workgroup_id},
        $args->{model}->{external_identifier},
        $circuit_state,
        0,
        0,
        $args->{model}->{remote_url},
        $args->{model}->{remote_requester},
        'mpls'
    ];
    my $circuit_id = $args->{db}->execute_query(
        "INSERT INTO circuit (
                name, description, workgroup_id, external_identifier,
                circuit_state, restore_to_primary, static_mac,
                remote_url, remote_requester, type
         )
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        $circuit
    );
    if (!defined $circuit_id) {
        return (undef, $args->{db}->get_error);
    }

    my $circuit_inst = [
        $circuit_id,
        0,
        $circuit_state,
        $args->{model}->{user_id},
        'Circuit Creation'
    ];
    my $circuit_inst_id = $args->{db}->execute_query(
        "INSERT INTO circuit_instantiation (
                circuit_id, end_epoch, start_epoch,
                reserved_bandwidth_mbps, circuit_state,
                modified_by_user_id, reason
         )
         VALUES (?, -1, UNIX_TIMESTAMP(NOW()), ?, ?, ?, ?)",
        $circuit_inst
    );
    if (!defined $circuit_inst_id) {
        return (undef, $args->{db}->get_error);
    }

    return ($circuit_id, undef);
}

=head2 fetch_circuits

=cut
sub fetch_circuits {
    my $args = {
        db         => undef,
        circuit_id => undef,
        state      => undef,
        first      => undef,
        @_
    };

    my $params = [];
    my $values = [];

    if (defined $args->{circuit_id}) {
        push @$params, "circuit.circuit_id=?";
        push @$values, $args->{circuit_id};
    }
    if (defined $args->{workgroup_id}) {
        push @$params, "(circuit.workgroup_id=? OR interface.workgroup_id=?)";
        push @$values, $args->{workgroup_id};
        push @$values, $args->{workgroup_id};
    }
    if (defined $args->{state}) {
        push @$params, "circuit.circuit_state=?";
        push @$values, $args->{state};
    }

    # We hardcode end_epoch to -1 to prevent history from being
    # queried. Ideally history will be stored in other ways in the
    # future.
    my $end_epoch;
    if (defined $args->{first} && $args->{first} == 1) {
        push @$params, "circuit_instantiation.end_epoch > ?";
        push @$values, -1;
        $end_epoch = 'min(circuit_instantiation.end_epoch) as end_epoch';
    } else {
        push @$params, "circuit_instantiation.end_epoch = ?";
        push @$values, -1;
        $end_epoch = 'circuit_instantiation.end_epoch';
    }

    my $where = (@$params > 0) ? 'WHERE ' . join(' AND ', @$params) : '';

    my $res = $args->{db}->execute_query(
        "SELECT circuit_instantiation.start_epoch, $end_epoch, circuit.circuit_id, circuit.name, circuit.description,
                circuit.workgroup_id, circuit.circuit_state as state, modified_by_user_id as user_id, reason,
                external_identifier, remote_url, remote_requester
         FROM circuit
         JOIN circuit_instantiation on circuit.circuit_id=circuit_instantiation.circuit_id
         JOIN circuit_edge_interface_membership on circuit_edge_interface_membership.circuit_id=circuit.circuit_id
         JOIN interface on interface.interface_id=circuit_edge_interface_membership.interface_id
         $where
         GROUP BY circuit.circuit_id",
        $values
    );
    if (!defined $res) {
        return;
    }

    return $res;
}

=head2 fetch_circuits_on_interface

=cut
sub fetch_circuits_on_interface{
    my %params = @_;
    my $db = $params{'db'};
    my $interface_id = $params{'interface_id'};

    # First gather all current entries from the circuit membership  table
    my $rows = $db->execute_query(
            "SELECT circuit_id FROM circuit_edge_interface_membership ".
            "WHERE interface_id = ? AND end_epoch = -1", [$interface_id]);
    if(!defined($rows)){
        return;
    }
    if(scalar(@$rows) == 0){
        return [];
    }

    my $results = [];
    foreach my $row (@$rows) {
        push(@$results, $row->{'circuit_id'});
    }
    return $results;
}

=head2 fetch_circuit_endpoint

=cut
sub fetch_circuit_endpoint {
    my %params = @_;
    my $db = $params{'db'};
    my $circuit_id = $params{'circuit_id'};
    my $interface_id = $params{'interface_id'};
    
    my $query = "select distinct(interface.interface_id), circuit_edge_interface_membership.start_epoch, circuit_edge_interface_membership.circuit_id, circuit_edge_interface_membership.unit, circuit_edge_interface_membership.extern_vlan_id as tag, circuit_edge_interface_membership.inner_tag, circuit_edge_interface_membership.circuit_edge_id, interface.name as interface, interface.description as interface_description, node.name as node, node.node_id as node_id, interface.port_number, interface.role, network.is_local from interface left join  interface_instantiation on interface.interface_id = interface_instantiation.interface_id and interface_instantiation.end_epoch = -1 join node on interface.node_id = node.node_id left join node_instantiation on node_instantiation.node_id = node.node_id and node_instantiation.end_epoch = -1 join network on node.network_id = network.network_id join circuit_edge_interface_membership on circuit_edge_interface_membership.interface_id = interface.interface_id where circuit_edge_interface_membership.circuit_id = ? and interface.interface_id = ? and circuit_edge_interface_membership.end_epoch = -1";

    my $res = $db->execute_query($query, [$circuit_id, $interface_id]);
    if(!defined($res) || scalar(@$res) != 1){
        return;
    }
    return $res->[0];
}

=head2 fetch_endpoints_on_interface

=cut
sub fetch_endpoints_on_interface {
    my %params = @_;
    my $db = $params{'db'};
    my $interface_id = $params{'interface_id'};
    my @results;

    my $circuits = fetch_circuits_on_interface(
            db => $db, interface_id => $interface_id);

    foreach my $circuit_id (@$circuits){
        push(@results, fetch_circuit_endpoint(
                            db => $db, circuit_id => $circuit_id,
                            interface_id => $interface_id));
    }
    return \@results;
}

1;
