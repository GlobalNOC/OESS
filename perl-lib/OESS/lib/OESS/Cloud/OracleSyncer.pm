package OESS::Cloud::OracleSyncer;

use strict;
use warnings;

use Data::Dumper;
use JSON::XS;
use Log::Log4perl;
use Net::IP;
use Net::IP qw(ip_is_ipv4);

use OESS::DB;
use OESS::DB::Endpoint;
use OESS::Endpoint;

=head1 OESS::Cloud::OracleSyncer

=cut


=head2 new

    my $azure = new OESS::Cloud::OracleSyncer(
        config => new OESS::Config,
        oracle => new OESS::Cloud::Oracle, # OESS::Cloud::OracleStub for testing
    );

=cut
sub new {
    my $class = shift;
    my $args  = {
        oracle      => undef,
        config      => undef,
        config_file => "/etc/oess/database.xml",
        logger      => Log::Log4perl->get_logger("OESS.Cloud.OracleSyncer"),
        @_
    };
    my $self = bless $args, $class;

    return $self;
}

=head2 peers_synced

=cut
sub peers_synced {
    my $self = shift;
    my $args = {
        local_peers  => undef,
        remote_peers => undef,
        @_
    };
    
    return 1;
}

=head2 get_peering_addresses_from_oracle

    Returns
    [
        { ip_version => 'ipv4', remote_ip => '', local_ip => '' },
        { ip_version => 'ipv6', remote_ip => '', local_ip => '' },
    ]

=cut
sub get_peering_addresses_from_oracle {
    my $self = shift;
    my $conn = shift;
    my $interconnect_id = shift;

    my $result = [];

    foreach my $cc (@{$conn->{crossConnectMappings}}) {
        if ($cc->{crossConnectOrCrossConnectGroupId} ne $interconnect_id) {
            next;
        }

        push @$result, {
            ip_version => 'ipv4',
            local_ip   => $cc->{customerBgpPeeringIp},
            remote_asn => $conn->{oracleBgpAsn},
            remote_ip  => $cc->{oracleBgpPeeringIp},
        };

        if (defined $cc->{oracleBgpPeeringIpv6}) {
            push @$result, {
                ip_version => 'ipv6',
                local_ip   => $cc->{customerBgpPeeringIpv6},
                remote_asn => $conn->{oracleBgpAsn},
                remote_ip  => $cc->{oracleBgpPeeringIpv6},
            };
        }
    }
    
    return $result;
}

=head2 update_local_peers

update_local_peers sets the peers of an OESS Endpoint to the values saved
within an Oracle VirtualCircuit's CrossConnectMapping.

=cut
sub update_local_peers {
    my $self = shift;
    my $args = {
        endpoint     => undef,
        remote_peers => undef,
        @_
    };

    my $endpoint = $args->{endpoint};
    my $local_peers = $args->{endpoint}->peers;
    my $remote_peers = $args->{remote_peers};

    my $i = 0;
    while ($i < @$remote_peers) {
        my $peer;
        if ($i+1 > @$local_peers) {
            # While more remote_peers than local_peers create one
            my $peer = new OESS::Peer(
                db => $endpoint->{db},
                model => {
                    local_ip   => $remote_peers->[$i]->{local_ip},
                    peer_asn   => $remote_peers->[$i]->{remote_asn},
                    peer_ip    => $remote_peers->[$i]->{remote_ip},
                    status     => 'up',
                    ip_version => $remote_peers->[$i]->{ip_version}
                }
            );
            $peer->create(vrf_ep_id => $endpoint->vrf_endpoint_id);
            $endpoint->add_peer($peer);
        } else {
            $local_peers->[$i]->local_ip($remote_peers->[$i]->{local_ip});
            $local_peers->[$i]->peer_asn($remote_peers->[$i]->{remote_asn});
            $local_peers->[$i]->peer_ip($remote_peers->[$i]->{remote_ip});
            $local_peers->[$i]->ip_version($remote_peers->[$i]->{ip_version});
            $local_peers->[$i]->update;
        }

        $i++;
    }

    while ($i < @$local_peers) {
        # While more local_peers than remote_peers remove one
        $local_peers->[$i]->decom;
        $i++;
    }
    
    return;
}

=head2 update_remote_peers

update_remote_peers sets the peers of an Oracle VirtualCircuit to the values
saved within the OESS database.

=cut
sub update_remote_peers {
    my $self = shift;
    my $args = {
        vrf_id    => undef,
        vrf_ep_id => undef,
        @_
    };
    
    my $vrf = new OESS::VRF(db => $self->{db}, vrf_id => $args->{vrf_id});
    $vrf->load_endpoints;

    my $endpoint;
    foreach my $ep (@{$vrf->endpoints}) {
        if ($ep->vrf_ep_id == $args->{vrf_ep_id}) {
            $endpoint = $ep;
            last;
        }
    }
    $endpoint->load_peers;

    my $auth_key  = '';
    my $oess_ip   = undef;
    my $peer_ip   = undef;
    my $oess_ipv6 = undef;
    my $peer_ipv6 = undef;

    foreach my $peer (@{$endpoint->peers}) {
        # Auth key is assumed to be the same for all peers on a
        # given endpoint.
        $auth_key = (defined $peer->md5_key) ? $peer->md5_key : '';

        if ($peer->ip_version eq 'ipv4') {
            $oess_ip = $peer->local_ip;
            $peer_ip = $peer->peer_ip;
        } else {
            $oess_ipv6 = $peer->local_ip;
            $peer_ipv6 = $peer->peer_ip;
        }
    }

    return $self->{oracle}->update_virtual_circuit(
        ocid      => $endpoint->cloud_account_id,
        name      => $vrf->name,
        type      => 'l3',
        bandwidth => $endpoint->bandwidth,
        auth_key  => $auth_key,
        mtu       => $endpoint->mtu,
        oess_asn  => $self->{config}->local_as,
        oess_ip   => $oess_ip,
        peer_ip   => $peer_ip,
        oess_ipv6 => $oess_ipv6,
        peer_ipv6 => $oess_ipv6,
        vlan      => $endpoint->tag
    );
}

=head2 fetch_oracle_endpoints_from_oess

    my ($endpoints, $err) = $syncer->fetch_oracle_endpoints_from_oess();
    die $err if defined $err;

=cut
sub fetch_oracle_endpoints_from_oess {
    my $self = shift;
    my $args = {
        @_
    };
    
    my $db = new OESS::DB(config_obj => $self->{config});

    my ($eps, $eps_err) = OESS::DB::Endpoint::fetch_all(
        db => $db,
        cloud_interconnect_type => 'oracle-fast-connect'
    );
    return (undef, $eps_err) if defined $eps_err;

    my $result = [];
    foreach my $ep (@$eps) {
        my $obj = new OESS::Endpoint(db => $db, model => $ep);
        $obj->load_peers;
        push @$result, $obj;
    }

    return ($result, undef);
}

=head2 fetch_virtual_circuits_from_oracle

    my ($conns, $oracle_err) = $syncer->fetch_virtual_circuits_from_oracle();
    die $oracle_err if defined $oracle_err;

=cut
sub fetch_virtual_circuits_from_oracle {
    my $self = shift;
    my ($conns, $err) = $self->{oracle}->get_virtual_circuits();
    return (undef, $err) if defined $err;

    my $result = {};
    foreach my $conn (@$conns) {
        $result->{$conn->{id}} = $conn;
    }
    return ($result, undef);
}

return 1;
