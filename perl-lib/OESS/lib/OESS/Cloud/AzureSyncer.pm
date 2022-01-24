package OESS::Cloud::AzureSyncer;

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

=head1 OESS::Cloud::AzureSyncer

    my $endpoints = $syncer->fetch_azure_endpoints_from_oess();
    my $conns = $syncer->fetch_cross_connections_from_azure();

    foreach my $ep (@$endpoints) {
        my $conn = $conns->{$ep->cloud_connection_id};
        next if !defined $conn;

        # ipv4 will end in '/30' and ipv6 will end in '/126'
        # should return:
        # {
        #     ipv4 => { ip_version => 'ipv4', remote_ip => '', local_ip => '' }
        #     ipv6 => { ip_version => 'ipv6', remote_ip => '', local_ip => '' }
        # }
        my $subnets = $syncer->get_peering_addresses_from_azure($conn, $ep->cloud_interconnect_id);

        # Azure connection may have only one peering for both ipv4 and ipv6
        $ep->load_peers;
        foreach my $peer (@{$ep->peers}) {
            if ($peer->ip_version eq 'ipv4') {
                $peer->remote_ip($subnet->{ipv4}->{remote_ip});
                $peer->local_ip($subnet->{ipv4}->{local_ip});
            } else {
                $peer->remote_ip($subnet->{ipv6}->{remote_ip});
                $peer->local_ip($subnet->{ipv6}->{local_ip});
            }
            $peer->update;
        }

        if ($conn->{bandwidthInMbps} != $ep->bandwidth) {
            $ep->bandwidth($conn->{bandwidthInMbps});
            $ep->update;
        }
    }


=cut


=head2 new

    my $azure = new OESS::Cloud::AzureSyncer(
        config => new OESS::Config,
        azure  => new OESS::Cloud::Azure, # OESS::Cloud::AzureStub for testing
    );

=cut
sub new {
    my $class = shift;
    my $args  = {
        azure       => undef,
        config      => undef,
        config_file => "/etc/oess/database.xml",
        logger      => Log::Log4perl->get_logger("OESS.Cloud.AzureSyncer"),
        @_
    };
    my $self = bless $args, $class;

    return $self;
}


=head2 fetch_cross_connections_from_azure

    my ($conns, $err) = $syncer->fetch_cross_connections_from_azure();

=cut
sub fetch_cross_connections_from_azure {
    my $self = shift;

    my $configs = [];
    my $result  = {};

    # 1. Get a list of all configured Azure account creds
    my $accounts = $self->{config}->get_cloud_config();
    if (ref $accounts->{connection} ne 'ARRAY') {
        $accounts->{connection} = [ $accounts->{connection} ];
    }

    foreach my $account (@{$accounts->{connection}}) {
        if ($account->{interconnect_type} ne 'azure-express-route') {
            next;
        }
        push @$configs, $account;
    }

    # 2. Create and return a hash from Azure connection id
    # (cloud_connection_id) to the full Azure CrossConnection object which
    # includes its peering information.
    foreach my $config (@$configs) {
        my $connectionsWithNoPeering = ($self->{azure}->expressRouteCrossConnections($config->{interconnect_id}));
        foreach my $conn (@$connectionsWithNoPeering) {
            my $connWithPeering = $self->{azure}->expressRouteCrossConnection($config->{interconnect_id}, $conn->{name});
            $connWithPeering->{interconnect_id} = $config->{interconnect_id}; # I'm not sure if this is needed later on or not
            $result->{$conn->{id}} = $connWithPeering;
        }
    }

    return ($result, undef);
}

=head2 fetch_azure_endpoints_from_oess

=cut
sub fetch_azure_endpoints_from_oess {
    my $self = shift;

    my $db = new OESS::DB(config_obj => $self->{config});

    my ($eps, $eps_err) = OESS::DB::Endpoint::fetch_all(
        db => $db,
        cloud_interconnect_type => 'azure-express-route'
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


=head2 get_peering_addresses_from_azure

get_peering_addresses_from_azure gets the peering addresses from the subnet
associated with $interconnect_id from $conn.

Returns
    {
        ipv4 => { ip_version => 'ipv4', remote_ip => '', local_ip => '' }
        ipv6 => { ip_version => 'ipv6', remote_ip => '', local_ip => '' }
    }

=cut
sub get_peering_addresses_from_azure {
    my $self = shift;
    my $conn = shift;
    my $interconnect_id = shift;

    # my $result = {
    #     ipv4 => { ip_version => 'ipv4', remote_ip => '', local_ip => '' },
    #     ipv6 => { ip_version => 'ipv6', remote_ip => '', local_ip => '' },
    # };
    my $result = { ipv4 => undef, ipv6 => undef };

    foreach my $peering (@{$conn->{properties}->{peerings}}) {
        next if $peering->{properties}->{peeringType} ne "AzurePrivatePeering";

        # primaryPeerAddressPrefix is defined when v4 prefix is assigned
        if (defined $peering->{properties}->{primaryPeerAddressPrefix}) {
            my $prefix;
            if ($interconnect_id eq $conn->{properties}->{primaryAzurePort}) {
                $prefix = $peering->{properties}->{primaryPeerAddressPrefix};
            } else {
                $prefix = $peering->{properties}->{secondaryPeerAddressPrefix};
            }

            my $ip = new Net::IP($prefix);
            $result->{ipv4}->{local_ip}   = get_nth_ip($ip, 1);
            $result->{ipv4}->{remote_ip}  = get_nth_ip($ip, 2);
            $result->{ipv4}->{remote_asn} = $peering->{properties}->{azureASN};
        }

        # ipv6PeeringConfig is defined when v6 prefix is assigned
        if (defined $peering->{properties}->{ipv6PeeringConfig}) {
            my $prefix;
            if ($interconnect_id eq $conn->{properties}->{primaryAzurePort}) {
                $prefix = $peering->{properties}->{ipv6PeeringConfig}->{primaryPeerAddressPrefix};
            } else {
                $prefix = $peering->{properties}->{ipv6PeeringConfig}->{secondaryPeerAddressPrefix};
            }
            my $ipv6 = new Net::IP($prefix);
            $result->{ipv6}->{local_ip}   = get_nth_ip($ipv6, 1);
            $result->{ipv6}->{remote_ip}  = get_nth_ip($ipv6, 2);
            $result->{ipv6}->{remote_asn} = $peering->{properties}->{azureASN};
        }
    }

    return $result;
}

=head2 get_nth_ip

Returns the nth IP Address of the provided subnet. An $increment of zero will
return the network address.

Examples:

    my $ipv6 = get_nth_ip(new Net::IP("2001:db8:85a3::8a2e:370:7334/126"), 1);
    # $ipv6 will equal "2001:db8:85a3::8a2e:370:7335/126"

    my $ipv4 = get_nth_ip(new Net::IP("192.168.100.248/30"), 1);
    # $ipv4 will equal "192.168.100.249/30"

=cut
sub get_nth_ip {
    my $ip = shift;
    my $increment = shift;

    # my $ip = new Net::IP($addr);
    my $mask = $ip->prefixlen();

    my $new_ip   = $ip + $increment;
    my $new_addr = $new_ip->ip . "/$mask";

    return $new_addr;
}

return 1;
