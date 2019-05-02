#!/usr/bin/perl

use strict;
use warnings;

package OESS::DB::Endpoint;

use Data::Dumper;

=head2 update_vrf

=cut
sub update_vrf {
    my %params = @_;
    my $db = $params{db};
    my $endpoint = $params{endpoint};

    my $reqs = [];
    my $args = [];
    my $set = '';
    

    if(!defined($endpoint->{vrf_endpoint_id})) {
        return;
    }
    
    if(defined($endpoint->{inner_tag})){
        push @$reqs, 'inner_tag=?';
        push @$args, $endpoint->{inner_tag};
    }
    
    if(defined($endpoint->{tag})){
        push @$reqs, 'tag=?';
        push @$args, $endpoint->{tag};
    }
    
    if(defined($endpoint->{bandwidth})){
        push @$reqs, 'bandwidth=?';
        push @$args, $endpoint->{bandwidth};
    }

    if(defined($endpoint->{interface}) &&
       defined($endpoint->{interface}->{interface_id})) {
        push @$reqs, 'interface_id=?';
        push @$args, $endpoint->{interface}->{interface_id};
    }

    if(defined($endpoint->{state})) {
        push @$reqs, 'state=?';
        push @$args, $endpoint->{state};
    }
    
    if(defined($endpoint->{unit})){
        push @$reqs, 'unit=?';
        push @$args, $endpoint->{unit};
    }

    $set .= join(', ', @$reqs);
    push @$args, $endpoint->{vrf_endpoint_id};
    my $result = $db->execute_query(
        "UPDATE vrf_ep SET $set WHERE vrf_ep_id=?",
        $args
    );
    return $result;
}

=head2 remove_circuit_edge_membership

=cut
sub remove_circuit_edge_membership{
    my %params = @_;
    my $db = $params{db};
    my $endpoint = $params{endpoint};

    my $result = $db->execute_query(
        "DELETE FROM circuit_edge_interface_membership ".
        "WHERE circuit_edge_id = ? AND end_epoch = -1",
        [$endpoint->{circuit_endpoint_id}]);
    return $result;
}

=head2 add_circuit_edge_membership

=cut
sub add_circuit_edge_membership{
    my %params = @_;
    my $db = $params{db};
    my $endpoint = $params{endpoint};
    
    my $result = $db->execute_query(
        "INSERT INTO circuit_edge_interface_membership (".
            "interface_id, ".
            "circuit_id, ".
            "end_epoch, ".
            "start_epoch,".
            "extern_vlan_id, ".
            "inner_tag, ".
            "circuit_edge_id, ".
            "unit".
            ") VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            [$endpoint->{interface}->{interface_id},
             $endpoint->{circuit_id},
             -1,
             $endpoint->{start_epoch},
             $endpoint->{tag},
             $endpoint->{inner_tag},
             $endpoint->{circuit_endpoint_id},
             $endpoint->{unit}]);
    return $result;
}

=head2 remove_vrf_peers

=cut
sub remove_vrf_peers{
    my %params = @_;
    my $db = $params{db};
    my $endpoint = $params{endpoint};

    my $result = $db->execute_query(
        "DELETE FROM vrf_ep_peer WHERE vrf_ep_peer_id=?",
        [$endpoint->{vrf_endpoint_id}]);
    return $result;
}

=head2 add_vrf_peers

=cut
sub add_vrf_peers{
    my %params = @_;
    my $db = $params{db};
    my $endpoint = $params{endpoint};

    my $values = [];
    my $params = [];

    if(scalar(@{$endpoint->{peers}}) == 0){
        return 1;
    }

    foreach my $peer (@{$endpoint->{peers}}){
        push @$params, '(?, ?, ?, ?, ?, ?, ?, ?)';
        
        push @$values, $peer->{vrf_ep_peer_id};
        push @$values, $peer->{peer_ip};
        push @$values, $peer->{peer_asn};
        push @$values, $peer->{vrf_ep_id};
        push @$values, $peer->{operational_state};
        push @$values, $peer->{state};
        push @$values, $peer->{local_ip};
        push @$values, $peer->{md5_key};
    }
    
    my $param_str = join(', ', @$params);
    my $result = $db->execute_query(
        "INSERT INTO vrf_ep_peer (".
            "vrf_ep_peer_id, ".
            "peer_ip, ".
            "peer_asn, ".
            "vrf_ep_id,".
            "operational_state, ".
            "state, ".
            "local_ip, ".
            "md5_key".
            ") VALUES $param_str", $values);
    return $result;
}

1;
