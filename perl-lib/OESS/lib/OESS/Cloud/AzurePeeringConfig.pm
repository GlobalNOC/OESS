package OESS::Cloud::AzurePeeringConfig;

use strict;
use warnings;

use Data::Dumper;
use Log::Log4perl;
use Net::IP;

use OESS::DB::Endpoint;
use OESS::Endpoint;

=head1 OESS::Cloud::AzurePeeringConfig

Loads the peering information required to provision an ExpressRoute
CrossConnection from the OESS database.


    {
        '000-0000-000' => {
            'ipv4' => {
                'primary'   => '192.168.100.248/30',
                'secondary' => '192.168.100.252/30',
            'ipv6' => {
                primary   => "3FFE:FFFF:0:CD30::0/126",
                secondary => "3FFE:FFFF:0:CD30::4/126",
            }
        }
    }

=cut

=head2 new

    my $config = new OESS::Cloud::AzurePeeringConfig(
        db     => $db,
        vrf_id => $conn->vrf_id # Optional
    );

=cut
sub new {
    my $class = shift;
    my $args  = {
        db     => undef,
        logger => Log::Log4perl->get_logger('OESS.Cloud.AzurePeeringConfig'),
        @_
    };
    my $self = bless $args, $class;

    die "Argument 'db' was not passed to AzurePeeringConfig" if !defined $self->{db};

    $self->{prefixes} = {};

    $self->{next_v4_prefix} = $self->_prefix_from_address('192.168.100.250/30');
    $self->{next_v6_prefix} = $self->_prefix_from_address('3FFE:FFFF:0:CD30::2/126');

    return $self;
}

=head2 load

    my $ok = $config->load(123);

=cut
sub load {
    my $self   = shift;
    my $vrf_id = shift;

    die "Argument 'vrf_id' was not passed to AzurePeeringConfig" if !defined $vrf_id;

    my ($models, $err) = OESS::DB::Endpoint::fetch_all(
        db     => $self->{db},
        vrf_id => $vrf_id
    );
    warn $err if defined $err;

    foreach my $model (@$models) {
        next if !defined $model->{cloud_interconnect_type} || $model->{cloud_interconnect_type} ne 'azure-express-route';

        my $ep = new OESS::Endpoint(db => $self->{db}, vrf_endpoint_id => $model->{vrf_ep_id});
        $ep->load_peers;

        foreach my $peer (@{$ep->peers}) {
            my $v = ($peer->ip_version eq 'ipv4') ? 4 : 6;

            my $prefix = $self->_prefix_from_address($peer->local_ip);
            if ($ep->cloud_interconnect_id =~ /PRI/) {
                $self->{prefixes}->{$ep->cloud_account_id}->{$v}->{primary} = $prefix;
            } else {
                $self->{prefixes}->{$ep->cloud_account_id}->{$v}->{secondary} = $prefix;
            }

            # TODO Validate next_v*_prefixes not already in use. Handles case where subnet
            # set from azure side. As prefixes set on Azure side override those stored in
            # OESS db, conflicts should only last a short period of time.

            # Prefixes are selected starting from a pre-defined subnet; If we find a
            # prefix larger than this subnet, set the next prefix to the subnet
            # directly after the larger one.
            if ($v == 4) {
                if ($prefix->bincomp('ge', $self->{next_v4_prefix})) {
                    $self->{next_v4_prefix} = $self->_next_prefix($prefix);
                } else {
                    $self->{next_v4_prefix} = $self->_next_prefix($self->{next_v4_prefix});
                }
            } else {
                if ($prefix->bincomp('ge', $self->{next_v6_prefix})) {
                    $self->{next_v6_prefix} = $self->_next_prefix($prefix);
                } else {
                    $self->{next_v6_prefix} = $self->_next_prefix($self->{next_v6_prefix});
                }
            }
        }
    }

    return 1;
}

=head2 primary_prefix

    my $prefix = $config->primary_prefix($service_id, $peer->ip_version);

primary_prefix returns the primary prefix to be used with $service_id as a
string.

Example:

    192.168.100.248/30

=cut
sub primary_prefix {
    my $self    = shift;
    my $service = shift;
    my $version = shift;

    my $v = ($version eq 'ipv4') ? 4 : 6;

    if (!defined $self->{prefixes}->{$service}) {
        $self->{prefixes}->{$service} = {
            4 => { primary => undef, secondary => undef },
            6 => { primary => undef, secondary => undef },
        };
    }

    if (!defined $self->{prefixes}->{$service}->{$v}->{primary}) {
        if ($v == 4) {
            $self->{prefixes}->{$service}->{$v}->{primary} = $self->{next_v4_prefix};
            $self->{next_v4_prefix} = $self->_next_prefix($self->{next_v4_prefix});
        } else {
            $self->{prefixes}->{$service}->{$v}->{primary} = $self->{next_v6_prefix};
            $self->{next_v6_prefix} = $self->_next_prefix($self->{next_v6_prefix});
        }
    }

    return $self->{prefixes}->{$service}->{$v}->{primary}->ip . '/' . $self->{prefixes}->{$service}->{$v}->{primary}->prefixlen;
}

=head2 secondary_prefix

    my $prefix = $config->secondary_prefix($service_id, $peer->ip_version);

secondary_prefix returns the secondary prefix to be used with $service_id as a
string.

Example:

    192.168.100.248/30

=cut
sub secondary_prefix {
    my $self    = shift;
    my $service = shift;
    my $version = shift;

    my $v = ($version eq 'ipv4') ? 4 : 6;

    if (!defined $self->{prefixes}->{$service}) {
        $self->{prefixes}->{$service} = {
            4 => { primary => undef, secondary => undef },
            6 => { primary => undef, secondary => undef },
        };
    }

    if (!defined $self->{prefixes}->{$service}->{$v}->{secondary}) {
        if ($v == 4) {
            $self->{prefixes}->{$service}->{$v}->{secondary} = $self->{next_v4_prefix};
            $self->{next_v4_prefix} = $self->_next_prefix($self->{next_v4_prefix});
        } else {
            $self->{prefixes}->{$service}->{$v}->{secondary} = $self->{next_v6_prefix};
            $self->{next_v6_prefix} = $self->_next_prefix($self->{next_v6_prefix});
        }
    }

    return $self->{prefixes}->{$service}->{$v}->{secondary}->ip . '/' . $self->{prefixes}->{$service}->{$v}->{secondary}->prefixlen;
}

=head2 cross_connection_peering

The result of cross_connection_peering is used as the argument for peering in
set_cross_connection_state_to_provisioned.

Example:
    {
        primaryPeerAddressPrefix   => '192.168.100.0/30'
        secondaryPeerAddressPrefix => '192.168.100.4/30',
        ipv6PeeringConfig => {
            primaryPeerAddressPrefix   => "3FFE:FFFF:0:CD30::0/126",
            secondaryPeerAddressPrefix => "3FFE:FFFF:0:CD30::4/126"
        }
    }

=cut
sub cross_connection_peering {
    my $self = shift;
    my $service = shift;

    my $result = {};
    if (!defined $self->{prefixes}->{$service}) {
        return $result;
    }

    my $v4 = $self->{prefixes}->{$service}->{4};
    my $v6 = $self->{prefixes}->{$service}->{6};

    if (defined $v4->{primary} || defined $v4->{secondary}) {
        # If only one prefix is passed, provisioning doesn't appear to work. So
        # we send both regardless of usage.
        $result->{primaryPeerAddressPrefix} = $self->primary_prefix($service, 'ipv4');
        $result->{secondaryPeerAddressPrefix} = $self->secondary_prefix($service, 'ipv4');
        $result->{state} = 'Enabled';
        $result->{peeringType} = 'AzurePrivatePeering';
    }

    # NOTE: I thought IPv6 support was added, but it doesn't seem to apply to
    # newly provisioned connections. Instead the user must add their IPv6
    # prefixes via the Azure Portal. The syncer script will pull the Ipv6
    # prefix in. If support for IPv6 is ever added uncomment the below section.
    #
    # if (defined $v6->{primary} || defined $v6->{secondary}) {
    #     $result->{ipv6PeeringConfig} = {
    #         primaryPeerAddressPrefix => $self->primary_prefix($service, 'ipv6'),
    #         secondaryPeerAddressPrefix => $self->secondary_prefix($service, 'ipv6'),
    #         state => 'Enabled'
    #     };
    # }

    return $result;
}

=head2 nth_address

Returns the nth IP Address of the provided subnet. An $increment of zero will
return the network address.

Examples:

    my $ipv6 = get_nth_ip("2001:db8:85a3::8a2e:370:7334/126", 1);
    # $ipv6 will equal "2001:db8:85a3::8a2e:370:7335/126"

    my $ipv4 = get_nth_ip("192.168.100.248/30", 1);
    # $ipv4 will equal "192.168.100.249/30"

=cut
sub nth_address {
    my $self = shift;
    my $prefix = shift;
    my $increment = shift;

    my $ip = new Net::IP($prefix);
    my $mask = $ip->prefixlen();

    my $new_ip   = $ip + $increment;
    my $new_addr = $new_ip->ip . "/$mask";

    return $new_addr;
}

=head2 _next_prefix

_next_prefix finds the next available /30 or /126 based on which prefixes are
currently recorded in this object.

=cut
sub _next_prefix {
    my $self = shift;
    my $prefix = shift;

    my $one;
    if ($prefix->version == 4) {
        $one = new Net::IP('0.0.0.1');
    } else {
        $one = new Net::IP('::1');
    }
    my $new = new Net::IP($prefix->last_ip);
    $new = $new->binadd($one);

    $new->set($new->ip . "/" . $prefix->prefixlen);
    return $new;
}

=head2 _prefix_from_address

_prefix_from_address determines the network for the given address. For
example, the network for 192.168.1.100/24 is 192.168.1.0/24.

=cut
sub _prefix_from_address {
    my $self = shift;
    my $addr = shift;

    my @parts = split('/', $addr);
    my $ipstr = $parts[0];
    my $maskbits = $parts[1];

    my $ip = new Net::IP($ipstr);
    my $mask = Net::IP::ip_get_mask($maskbits, $ip->version);

    my $netbin = $self->_ip_binand($ip->binip, $mask);
    my $net = Net::IP::ip_bintoip($netbin, $ip->version);

    return new Net::IP("$net/$maskbits");
}

=head2 _prefix_from_ip

=cut
sub _prefix_from_ip {
    my $self = shift;
    my $ip   = shift;
    return $ip->ip . '/' . $ip->prefixlen;
}

=head2 _ip_binand

Performs a binary and of the two binary string addresses.

=cut
sub _ip_binand {
    my $self = shift;
    my $a = shift;
    my $b = shift;

    if (length($a) ne length($b)) {
        die  "Unequal length of addresses";
    }

    my $result = "";
    for (0 .. length($a) - 1) {
        if (substr($a, $_, 1) eq "1" && substr($b, $_, 1) eq "1") {
            $result .= "1";
        } else {
            $result .= "0";
        }
    }
    return $result;
}

return 1;
