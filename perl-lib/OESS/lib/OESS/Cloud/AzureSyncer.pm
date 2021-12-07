package OESS::Cloud::AzureSyncer;

use strict;
use warnings;

use Data::Dumper;
use JSON::XS;
use Log::Log4perl;

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
        foreach $peer (@{$ep->peers}) {
            my $subnet = $subnets->{peer->ip_version};
            if ($subnet->{remote_ip} ne $peer->remote_ip || $subnet->{local_ip} ne $peer->local_ip) {
                $peer->remote_ip($subnet->{remote_ip});
                $peer->local_ip($subnet->{local_ip});
                $peer->update;
            }
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
        config      => undef,
        config_file => "/etc/oess/database.xml",
        logger      => Log::Log4perl->get_logger("OESS.Cloud.AzureSyncer"),
        @_
    };
    my $self = bless $args, $class;

    return $self;
}


=head2 fetch_cross_connections_from_azure

    my $conns = $syncer->fetch_cross_connections_from_azure();

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
        if ($cloud->{interconnect_type} ne 'azure-express-route') {
            next;
        }
        push @$configs, $account;
    }

    # 2. Create and return a hash from Azure connection id
    # (cloud_connection_id) to the full Azure CrossConnection object which
    # includes its peering information.
    foreach my $config (@$configs) {
        my $connectionsWithNoPeering = ($azure->expressRouteCrossConnections($config->{interconnect_id}));
        foreach my $conn (@$connectionsWithNoPeering) {
            my $connWithPeering = $azure->expressRouteCrossConnection($config->{interconnect_id}, $conn->{name});
            $connWithPeering->{interconnect_id} = $config->{interconnect_id}; # I'm not sure if this is needed later on or not
            $result->{$conn->{id}} = $connWithPeering;
        }
    }

    return $result;
}


=head2 get_peering_addresses_from_azure

=cut
sub get_peering_addresses_from_azure {
    my $self = shift;

    return { ipv4 => undef, ipv6 => undef };
}

return 1;
