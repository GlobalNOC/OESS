package OESS::Cloud::AzureSyncer;

use strict;
use warnings;

use Data::Dumper;
use JSON::XS;
use Log::Log4perl;

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
        foreach $peer (@{$ep->peers}) {
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

=cut
sub get_peering_addresses_from_azure {
    my $self = shift;
    my $conn = shift;
    my $interconnect_id = shift;

    my $result = {
        ipv4 => { ip_version => 'ipv4', remote_ip => '', local_ip => '' },
        ipv6 => { ip_version => 'ipv6', remote_ip => '', local_ip => '' },
    };

    foreach my $peering (@{$conn->{properties}->{peerings}}) {
        next if $peering->{properties}->{peeringType} ne "AzurePrivatePeering";

        my $prefix;
        if ($interconnect_id eq $conn->{properties}->{primaryAzurePort}) {
            $prefix = $peering->{properties}->{primaryPeerAddressPrefix};
        } else {
            $prefix = $peering->{properties}->{secondaryPeerAddressPrefix};
        }

        # if is_ipv4($prefix)
        warn $prefix;
        $result->{ipv4}->{local_ip}  = get_nth_ip($prefix, 1);
        $result->{ipv4}->{remote_ip} = get_nth_ip($prefix, 2);
        
        # if is_ipv6($prefix)
        # $result->{ipv6}->{local_ip}  = undef;
        # $result->{ipv6}->{remote_ip} = undef;
    }

    return $result;
}

=head2 get_nth_ip

=cut
sub get_nth_ip {
    my $ip = shift;
    my $increment = shift;

    $ip =~ m/^(\d\d?\d?)\.(\d\d?\d?)\.(\d\d?\d?)\.(\d\d?\d?)/;
    my $firstOctet = $1;
    my $secondOctet = $2;
    my $thirdOctet = $3;
    my $lastOctet = $4;

    $ip =~ m/\/(\d\d?)$/;
    my $subnet = $1;
    $lastOctet = int($lastOctet) + $increment;
    return "$firstOctet.$secondOctet.$thirdOctet.$lastOctet/$subnet";
}

return 1;
