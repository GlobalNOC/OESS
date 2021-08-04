#!/usr/bin/perl

use strict;
use warnings;

package OESS::Config;

use XML::Simple;

=head1 NAME

OESS::Config

=cut

=head1 VERSION

2.0.0

=cut

=head1 SYNOPSIS

use OESS::Config

my $config = OESS::Config->new();

my $local_as = $config->local_as();
my $db_creds = $config->db_credentials();
my $db_server = $config->db_server();

=cut

=head2 new

=cut
sub new {
    my $that  = shift;
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS.Config");

    my %args = (
        config_filename => '/etc/oess/database.xml' ,
        @_,
        );

    my $self = \%args;

    bless $self, $class;

    $self->{'logger'} = $logger;
    $self->{'config'} = XML::Simple::XMLin($self->{'config_filename'});

    return $self;
}

=head2 local_as

returns the configured local_as number

=cut
sub local_as {
    my $self = shift;

    return $self->{'config'}->{'local_as'};
}

=head2 db_credentials

=cut
sub db_credentials {
    my $self = shift;

    my $creds = $self->{'config'}->{'credentials'};
    my $database = $creds->{'database'};
    my $username = $creds->{'username'};
    my $password = $creds->{'password'};

    return {database => $database,
            username => $username,
            password => $password};
}

=head2 filename

=cut
sub filename {
    my $self = shift;
    return $self->{config_filename};
}

=head2 fwdctl_enabled

=cut
sub fwdctl_enabled {
    my $self = shift;
    return 1 if (!defined $self->{'config'}->{'process'}->{'fwdctl'});
    return ($self->{'config'}->{'process'}->{'fwdctl'}->{'status'} eq 'enabled') ? 1 : 0;
}

=head2 fvd_enabled

=cut
sub fvd_enabled {
    my $self = shift;
    return 1 if (!defined $self->{'config'}->{'process'}->{'fvd'});
    return ($self->{'config'}->{'process'}->{'fvd'}->{'status'} eq 'enabled') ? 1 : 0;
}

=head2 mpls_enabled

=cut
sub mpls_enabled {
    my $self = shift;
    return ($self->{'config'}->{'network_type'} eq 'vpn-mpls') ? 1 : 0;
}

=head2 mpls_fwdctl_enabled

=cut
sub mpls_fwdctl_enabled {
    my $self = shift;
    return 1 if (!defined $self->{'config'}->{'process'}->{'mpls_fwdctl'});
    return ($self->{'config'}->{'process'}->{'mpls_fwdctl'}->{'status'} eq 'enabled') ? 1 : 0;
}

=head2 mpls_discovery_enabled

=cut
sub mpls_discovery_enabled {
    my $self = shift;
    return 1 if (!defined $self->{'config'}->{'process'}->{'mpls_discovery'});
    return ($self->{'config'}->{'process'}->{'mpls_discovery'}->{'status'} eq 'enabled') ? 1 : 0;
}

=head2 network_type

Returns one of C<openflow>, C<vpn-mpls>, or C<evpn-vxlan>.

=cut
sub network_type {
    my $self = shift;
    if (!defined $self->{'config'}->{'network_type'}) {
        return 'vpn-mpls';
    }

    my $type = $self->{'config'}->{'network_type'};
    my $valid_types = ['openflow', 'vpn-mpls', 'evpn-vxlan', 'nso', 'nso+vpn-mpls'];
    foreach my $valid_type (@$valid_types) {
        if ($type eq $valid_type) {
            return $type;
        }
    }

    $self->{'logger'}->warn("Invalid network_type $type specified. Using 'vpn-mpls' instead.");
    return 'vpn-mpls';
}

=head2 notification_enabled

=cut
sub notification_enabled {
    my $self = shift;
    return 1 if (!defined $self->{'config'}->{'process'}->{'notification'});
    return ($self->{'config'}->{'process'}->{'notification'}->{'status'} eq 'enabled') ? 1 : 0;
}

=head2 nox_enabled

=cut
sub nox_enabled {
    my $self = shift;
    return 1 if (!defined $self->{'config'}->{'process'}->{'nox'});
    return ($self->{'config'}->{'process'}->{'nox'}->{'status'} eq 'enabled') ? 1 : 0;
}

=head2 nsi_enabled

=cut
sub nsi_enabled {
    my $self = shift;
    return 1 if (!defined $self->{'config'}->{'process'}->{'nsi'});
    return ($self->{'config'}->{'process'}->{'nsi'}->{'status'} eq 'enabled') ? 1 : 0;
}

=head2 openflow_enabled

=cut
sub openflow_enabled {
    my $self = shift;
    return ($self->{'config'}->{'network_type'} eq 'openflow') ? 1 : 0;
}

=head2 traceroute_enabled

=cut
sub traceroute_enabled {
    my $self = shift;
    return 1 if (!defined $self->{'config'}->{'process'}->{'traceroute'});
    return ($self->{'config'}->{'process'}->{'traceroute'}->{'status'} eq 'enabled') ? 1 : 0;
}

=head2 vlan_stats_enabled

=cut
sub vlan_stats_enabled {
    my $self = shift;
    return 1 if (!defined $self->{'config'}->{'process'}->{'vlan_stats'});
    return ($self->{'config'}->{'process'}->{'vlan_stats'}->{'status'} eq 'enabled') ? 1 : 0;
}

=head2 watchdog_enabled

=cut
sub watchdog_enabled {
    my $self = shift;
    return 1 if (!defined $self->{'config'}->{'process'}->{'watchdog'});
    return ($self->{'config'}->{'process'}->{'watchdog'}->{'status'} eq 'enabled') ? 1 : 0;
}

=head2 get_cloud_config

=cut
sub get_cloud_config {
    my $self = shift;
    return $self->{'config'}->{'cloud'};
}

=head2 base_url

=cut
sub base_url {
    my $self = shift;
    return $self->{'config'}->{'base_url'};
}

=head2 third_party_mgmt

=cut
sub third_party_mgmt {
    my $self = shift;
    return 'n' if (!defined $self->{'config'}->{'third_party_mgmt'});
    return $self->{'config'}->{'third_party_mgmt'};
}

=head2 nso_host

=cut
sub nso_host {
    my $self = shift;
    return if (!defined $self->{config}->{nso});
    return $self->{config}->{nso}->{host};
}

=head2 nso_password

=cut
sub nso_password {
    my $self = shift;
    return if (!defined $self->{config}->{nso});
    return $self->{config}->{nso}->{password};
}

=head2 nso_username

=cut
sub nso_username {
    my $self = shift;
    return if (!defined $self->{config}->{nso});
    return $self->{config}->{nso}->{username};
}

=head2 tsds_url

=cut
sub tsds_url {
    my $self = shift;
    return if (!defined $self->{config}->{tsds});
    return $self->{config}->{tsds}->{url};
}

=head2 tsds_password

=cut
sub tsds_password {
    my $self = shift;
    return if (!defined $self->{config}->{tsds});
    return $self->{config}->{tsds}->{password};
}

=head2 tsds_username

=cut
sub tsds_username {
    my $self = shift;
    return if (!defined $self->{config}->{tsds});
    return $self->{config}->{tsds}->{username};
}

=head2 tsds_realm

=cut
sub tsds_realm {
    my $self = shift;
    return if (!defined $self->{config}->{tsds});
    return $self->{config}->{tsds}->{realm};
}

1;
