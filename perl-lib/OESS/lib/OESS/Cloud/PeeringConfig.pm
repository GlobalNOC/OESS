package OESS::Cloud::PeeringConfig;

use strict;
use warnings;

use Data::Dumper;
use Log::Log4perl;
use Net::IP;

use OESS::DB::Endpoint;
use OESS::Endpoint;

=head1 OESS::Cloud::PeeringConfig

Loads the peering information required to provision an Endpoint from the OESS
database. Assumes at most one ipv4 and one ipv6 address.


    {
        '000-0000-000' => {
            'ipv4' => {
                '123' => '172.30.0.0/30',
                '456' => '172.30.0.4/30',
            'ipv6' => {
                '123' => 'fd28:221e:28fa:61d3::0/126',
                '456' => 'fd28:221e:28fa:61d3::4/126',
            }
        }
    }

=cut

=head2 new

    my $config = new OESS::Cloud::PeeringConfig(
        db     => $db,
        vrf_id => $conn->vrf_id # Optional
    );

=cut

sub new {
    my $class = shift;
    my $args  = {
        db     => undef,
        logger => Log::Log4perl->get_logger('OESS.Cloud.PeeringConfig'),
        @_
    };
    my $self = bless $args, $class;

    die "Argument 'db' was not passed to PeeringConfig" if !defined $self->{db};

    $self->{prefixes} = {};

    $self->{next_v4_prefix} = $self->_prefix_from_address('172.30.0.0/30');
    $self->{next_v6_prefix} = $self->_prefix_from_address('fd28:221e:28fa:61d3::0/126');

    return $self;
}

=head2 load

    my $err = $config->load(123);

=cut

sub load {
    my $self   = shift;
    my $vrf_id = shift;

    die "Argument 'vrf_id' was not passed to PeeringConfig" if !defined $vrf_id;

    my ($models, $err) = OESS::DB::Endpoint::fetch_all(
        db     => $self->{db},
        vrf_id => $vrf_id
    );
    return $err if defined $err;

    foreach my $model (@$models) {
        my $ep = new OESS::Endpoint(db => $self->{db}, vrf_endpoint_id => $model->{vrf_ep_id});
        $ep->load_peers;

        foreach my $peer (@{$ep->peers}) {
            my $v = ($peer->ip_version eq 'ipv4') ? 4 : 6;

            $self->{prefixes}->{$ep->cloud_account_id}->{$v}->{$ep->interface_id} = $self->_prefix_from_address($peer->local_ip);

            # Prefixes are selected starting from a pre-defined subnet. So long as we
            # increment the subnet once for every subnet already in use, out next
            # subnet will have a unique prefix.
            if ($v == 4) {
                $self->{next_v4_prefix} = $self->_next_prefix($self->{next_v4_prefix});
            } else {
                $self->{next_v6_prefix} = $self->_next_prefix($self->{next_v6_prefix});
            }
        }
    }

    return;
}

=head2 prefix

    my $prefix = $config->prefix($ep->cloud_account_id, $ep->interface_id, $peer->ip_version);

prefix returns the primary prefix to be used with $cloud_account_id on 

Example:

    192.168.100.248/30

=cut

sub prefix {
    my $self = shift;
    my $cloud_account_id = shift;
    my $interface_id = shift;
    my $version = shift;

    my $v = ($version eq 'ipv4') ? 4 : 6;

    if (!defined $self->{prefixes}->{$cloud_account_id}) {
        $self->{prefixes}->{$cloud_account_id} = { 4 => {}, 6 => {} };
        $self->{prefixes}->{$cloud_account_id}->{4}->{$interface_id} = undef;
        $self->{prefixes}->{$cloud_account_id}->{6}->{$interface_id} = undef;
    }

    if (!defined $self->{prefixes}->{$cloud_account_id}->{$v}->{$interface_id}) {
        if ($v == 4) {
            $self->{prefixes}->{$cloud_account_id}->{$v}->{$interface_id} = $self->{next_v4_prefix};
            $self->{next_v4_prefix} = $self->_next_prefix($self->{next_v4_prefix});
        } else {
            $self->{prefixes}->{$cloud_account_id}->{$v}->{$interface_id} = $self->{next_v6_prefix};
            $self->{next_v6_prefix} = $self->_next_prefix($self->{next_v6_prefix});
        }
    }

    return $self->{prefixes}->{$cloud_account_id}->{$v}->{$interface_id}->ip . '/' . $self->{prefixes}->{$cloud_account_id}->{$v}->{$interface_id}->prefixlen;
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
