use strict;
use warnings;

package OESS::DB::Peer;

use Data::Dumper;

=head1 OESS::DB::Peer

    use OESS::DB::Peer;

=cut

=head2 create

    my $id = OESS::DB::Peer::create(
        db => $db,
        model => {
            circuit_ep_id     => 7,                # Optional
            vrf_ep_id         => 7,                # Optional
            local_ip          => '192.168.1.2/31',
            peer_asn          => 1200
            peer_ip           => '192.168.1.3/31',
            md5_key           => undef,
            operational_state => 'up'
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

    my $q1 = "
        INSERT INTO vrf_ep_peer (circuit_ep_id, vrf_ep_id, local_ip, peer_asn, peer_ip, md5_key, operational_status, state)
        VALUES (?,?,?,?,?,?,?,?)
    ";

    $args->{model}->{circuit_ep_id} = (exists $args->{model}->{circuit_ep_id}) ? $args->{model}->{circuit_ep_id} : undef;
    $args->{model}->{vrf_ep_id} = (exists $args->{model}->{vrf_ep_id}) ? $args->{model}->{vrf_ep_id} : undef;
    $args->{model}->{operational_state} = (defined $args->{model}->{operational_state} && $args->{model}->{operational_state} eq 'up') ? 1 : 0;

    my $peer_id = $args->{db}->execute_query($q1, [
        $args->{model}->{circuit_ep_id},
        $args->{model}->{vrf_ep_id},
        $args->{model}->{local_ip},
        $args->{model}->{peer_asn},
        $args->{model}->{peer_ip},
        $args->{model}->{md5_key},
        $args->{model}->{operational_state},
        'active'
    ]);
    if (!defined $peer_id) {
        return (undef, $args->{db}->get_error);
    }

    return ($peer_id, undef);
}

=head2 fetch_all

    my ($peers, $error) = OESS::DB::Peer::fetch_all(
        db            => $db,
        circuit_ep_id => 100,          # Optional
        vrf_ep_id     => 100           # Optional
    );
    warn $error if defined $error;

fetch_all returns a list of all Peers of both Circuits and VRFs. Each
VRF Peer will contain C<vrf_ep_id> and Circuit Peers will contain
C<circuit_ep_id>.

    {
        vrf_ep_peer_id    => 1
        circuit_ep_id     => undef,
        vrf_ep_id         => 3,
        local_ip          => '192.168.1.2/31',
        peer_asn          => 1200
        peer_ip           => '192.168.1.3/31',
        md5_key           => undef,
        operational_state => 'up'
    }

=cut
sub fetch_all {
    my $args = {
        db => undef,
        circuit_ep_id => undef,
        vrf_ep_id => undef,
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};

    my $params = [];
    my $values = [];

    if (defined $args->{circuit_ep_id}) {
        push @$params, 'circuit_ep_id=?';
        push @$values, $args->{circuit_ep_id};
    }
    if (defined $args->{vrf_ep_id}) {
        push @$params, 'vrf_ep_id=?';
        push @$values, $args->{vrf_ep_id};
    }

    my $where = (@$params > 0) ? 'WHERE ' . join(' AND ', @$params) : '';

    my $q = "
        SELECT vrf_ep_peer_id, circuit_ep_id, vrf_ep_id,
               local_ip, peer_asn, peer_ip, md5_key, operational_state
        FROM vrf_ep_peer
        $where
    ";
    my $peers = $args->{db}->execute_query($q, $values);
    if (!defined $peers) {
        return (undef, "Couldn't find Peers: " . $args->{db}->get_error);
    }
    foreach my $peer (@$peers) {
        $peer->{operational_state} = ($peer->{operational_state} == 1) ? 'up' : 'down';
    }

    return ($peers, undef);
}

1
