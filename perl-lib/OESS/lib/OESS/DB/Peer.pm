use strict;
use warnings;

package OESS::DB::Peer;

use Data::Dumper;

=head1 OESS::DB::Peer

    use OESS::DB::Peer;

=cut

=head2 create

    my ($id, $err) = OESS::DB::Peer::create(
        db => $db,
        model => {
            circuit_ep_id     => 7,                # Optional
            vrf_ep_id         => 7,                # Optional
            ip_version        => 'ipv4',           # Optional - Derived from local_ip
            local_ip          => '192.168.1.2/31',
            peer_asn          => 1200
            peer_ip           => '192.168.1.3/31',
            md5_key           => undef,
            operational_state => 'up',
            bfd               => 0
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
        INSERT INTO vrf_ep_peer (circuit_ep_id, vrf_ep_id, local_ip, peer_asn, peer_ip, md5_key, operational_state, state, bfd, ip_version)
        VALUES (?,?,?,?,?,?,?,?,?,?)
    ";

    $args->{model}->{circuit_ep_id} = (exists $args->{model}->{circuit_ep_id}) ? $args->{model}->{circuit_ep_id} : undef;
    $args->{model}->{vrf_ep_id} = (exists $args->{model}->{vrf_ep_id}) ? $args->{model}->{vrf_ep_id} : undef;
    $args->{model}->{operational_state} = (defined $args->{model}->{operational_state} && $args->{model}->{operational_state} eq 'up') ? 1 : 0;
    $args->{model}->{bfd} = (defined $args->{model}->{bfd}) ? $args->{model}->{bfd} : 0;

    if (!defined $args->{model}->{ip_version}) {
        if ($args->{model}->{local_ip} =~ /^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/([0-9]|[1-2][0-9]|3[0-2]))$/) {
            $args->{model}->{ip_version} = 'ipv4';
        } else {
            $args->{model}->{ip_version} = 'ipv6';
        }
    }

    my $peer_id = $args->{db}->execute_query($q1, [
        $args->{model}->{circuit_ep_id},
        $args->{model}->{vrf_ep_id},
        $args->{model}->{local_ip},
        $args->{model}->{peer_asn},
        $args->{model}->{peer_ip},
        $args->{model}->{md5_key},
        $args->{model}->{operational_state},
        'active',
        $args->{model}->{bfd},
        $args->{model}->{ip_version}
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
        operational_state => 'up',
        bfd               => 0,
        ip_version        => 'ipv4'
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

    push @$params, 'state=?';
    push @$values, 'active';

    my $where = (@$params > 0) ? 'WHERE ' . join(' AND ', @$params) : '';

    my $q = "
        SELECT vrf_ep_peer_id, circuit_ep_id, vrf_ep_id, ip_version,
               local_ip, peer_asn, peer_ip, md5_key, operational_state, bfd
        FROM vrf_ep_peer
        $where
    ";
    my $peers = $args->{db}->execute_query($q, $values);
    if (!defined $peers) {
        return (undef, "Couldn't find Peers: " . $args->{db}->get_error);
    }
    foreach my $peer (@$peers) {
        $peer->{operational_state} = ($peer->{operational_state} == 1) ? 'up' : 'down';
        $peer->{bfd} = int($peer->{bfd});
    }

    return ($peers, undef);
}

=head2 update

    my $err = OESS::DB::Peer::update(
        db => $db,
        peer => {
            vrf_ep_peer_id => 1,
            interface_a_id => 100,
            ip_a           => undef,
            interface_z_id => 21,
            ip_z           => undef,
            name           => 'Peer', # Optional
            status         => 'up',   # Optional
            remote_urn     => undef,  # Optional
            metric         => 553,    # Optional
            bfd            => 0       # Optional
       }
    );

=cut
sub update {
    my $args = {
        db  => undef,
        peer => {},
        @_
    };

    return 'Required argument `db` is missing.' if !defined $args->{db};
    return 'Required argument `peer->vrf_ep_peer_id` is missing.' if !defined $args->{peer}->{vrf_ep_peer_id};

    my $params = [];
    my $values = [];

    if (defined $args->{peer}->{peer_ip}) {
        push @$params, 'peer_ip=?';
        push @$values, $args->{peer}->{peer_ip};
    }
    if (defined $args->{peer}->{peer_asn}) {
        push @$params, 'peer_asn=?';
        push @$values, $args->{peer}->{peer_asn};
    }
    if (defined $args->{peer}->{local_ip}) {
        push @$params, 'local_ip=?';
        push @$values, $args->{peer}->{local_ip};
    }
    if (defined $args->{peer}->{operational_state}) {
        push @$params, 'operational_state=?';
        push @$values, $args->{peer}->{operational_state};
    }
    if (defined $args->{peer}->{bfd}) {
        push @$params, 'bfd=?';
        push @$values, $args->{peer}->{bfd};
    }

    my $fields = join(', ', @$params);
    push @$values, $args->{peer}->{vrf_ep_peer_id};

    my $ok = $args->{db}->execute_query(
        "UPDATE vrf_ep_peer SET $fields WHERE vrf_ep_peer_id=?",
        $values
    );
    if (!defined $ok) {
        return $args->{db}->get_error;
    }

    return;
}


1;
