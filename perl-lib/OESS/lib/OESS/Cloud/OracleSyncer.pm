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
            md5_key    => $cc->{bgpMd5AuthKey} || '',
        };

        if (defined $cc->{oracleBgpPeeringIpv6}) {
            push @$result, {
                ip_version => 'ipv6',
                local_ip   => $cc->{customerBgpPeeringIpv6},
                remote_asn => $conn->{oracleBgpAsn},
                remote_ip  => $cc->{oracleBgpPeeringIpv6},
                md5_key    => $cc->{bgpMd5AuthKey} || '',
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
                    md5_key    => $remote_peers->[$i]->{md5_key},
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
            $local_peers->[$i]->md5_key($remote_peers->[$i]->{md5_key});
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
stored in the provided endpoints. An update will only be preformed if a diff is
detected between peering addresses due to the following:

> If the virtual circuit is working and in the PROVISIONED state, updating
> any of the network-related properties (such as the DRG being used, the BGP
> ASN, and so on) will cause the virtual circuit's state to switch to
> PROVISIONING and the related BGP session to go down.

=cut
sub update_remote_peers {
    my $self = shift;
    my $args = {
        virtual_circuit => undef,
        endpoints => undef,
        @_
    };

    my $change_required = 0;
    my $cross_connect_mappings = [];
    my $mtu = 1500;
    
    foreach my $ccm (@{$args->{virtual_circuit}->{crossConnectMappings}}) {
        # If we don't have peering info for the specified endpoint move on
        next if !defined $args->{endpoints}->{$ccm->{crossConnectOrCrossConnectGroupId}};

        my $ep = $args->{endpoints}->{$ccm->{crossConnectOrCrossConnectGroupId}};
        $ep->load_peers;

        my $staged_change = {
            oracleBgpPeeringIpv6 => undef,
            customerBgpPeeringIpv6 => undef,
            customerBgpPeeringIp => undef,
            vlan => int($ep->tag),
            crossConnectOrCrossConnectGroupId => $ep->cloud_interconnect_id,
            bgpMd5AuthKey => undef,
            oracleBgpPeeringIp => undef
        };
        foreach my $peer (@{$ep->peers}) {
            $staged_change->{bgpMd5AuthKey} = (defined $peer->md5_key && $peer->md5_key ne '') ? $peer->md5_key : undef;

            if ($peer->ip_version eq 'ipv4') {
                $staged_change->{customerBgpPeeringIp} = $peer->local_ip;
                $staged_change->{oracleBgpPeeringIp} = $peer->peer_ip;
            } else {
                $staged_change->{customerBgpPeeringIpv6} = $peer->local_ip;
                $staged_change->{oracleBgpPeeringIpv6} = $peer->peer_ip;
            }
        }

        $change_required = 1 if $staged_change->{bgpMd5AuthKey} ne $ccm->{bgpMd5AuthKey};
        $change_required = 1 if $staged_change->{crossConnectOrCrossConnectGroupId} ne $ccm->{crossConnectOrCrossConnectGroupId};
        $change_required = 1 if !$self->_ip_eq($staged_change->{customerBgpPeeringIp}, $ccm->{customerBgpPeeringIp});
        $change_required = 1 if !$self->_ip_eq($staged_change->{customerBgpPeeringIpv6}, $ccm->{customerBgpPeeringIpv6});
        $change_required = 1 if !$self->_ip_eq($staged_change->{oracleBgpPeeringIp}, $ccm->{oracleBgpPeeringIp});
        $change_required = 1 if !$self->_ip_eq($staged_change->{oracleBgpPeeringIpv6}, $ccm->{oracleBgpPeeringIpv6});
        $change_required = 1 if $staged_change->{vlan} != $ccm->{vlan};

        $mtu = $ep->mtu;

        push @$cross_connect_mappings, {
            auth_key  => $staged_change->{bgpMd5AuthKey},
            ocid      => $staged_change->{crossConnectOrCrossConnectGroupId},
            oess_ip   => $staged_change->{customerBgpPeeringIp},
            peer_ip   => $staged_change->{oracleBgpPeeringIp},
            oess_ipv6 => $staged_change->{customerBgpPeeringIpv6},
            peer_ipv6 => $staged_change->{oracleBgpPeeringIpv6},
            vlan      => $staged_change->{vlan},
        };
    }

    if (!$change_required) {
        # Updating a connection will reprovision on the Oracle side
        # causing a network disruption. Therefore if no change is
        # required we do nothing.
        return;
    }

    print "Updating VirtualCircuit $args->{virtual_circuit}->{id}\n";
    $self->{logger}->info("Updating VirtualCircuit $args->{virtual_circuit}->{id}");

    my ($virtual_circuit, $err) = $self->{oracle}->update_virtual_circuit(
        virtual_circuit_id     => $args->{virtual_circuit}->{id},
        bandwidth              => $args->{virtual_circuit}->{bandwidthShapeName},
        bfd                    => 0,
        mtu                    => $mtu,
        oess_asn               => $self->{config}->local_as,
        name                   => $args->{virtual_circuit}->{displayName},
        type                   => 'l3',
        cross_connect_mappings => $cross_connect_mappings
    );
    return $err;
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

=head2 _ip_eq

_ip_eq converts the CIDR IPs into Net::IP objects so they may be
compared regardless of formatting. This is helpful for IPv6 addresses
specifically as they may be presented in either expanded or compressed
form.

=cut
sub _ip_eq {
    my $self = shift;
    my $ip_a = shift;
    my $ip_b = shift;

    my @parts_a = split('/', $ip_a);
    my $ipstr_a = $parts_a[0];
    my $maskbits_a = $parts_a[1];

    my @parts_b = split('/', $ip_b);
    my $ipstr_b = $parts_b[0];
    my $maskbits_b = $parts_b[1];

    my $nip_a = new Net::IP($ipstr_a);
    my $nip_b = new Net::IP($ipstr_b);

    if ($nip_a->ip eq $nip_b->ip && $maskbits_a eq $maskbits_b) {
        return 1;
    } else {
        return 0;
    }
}

return 1;
