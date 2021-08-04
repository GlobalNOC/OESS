package OESS::Cloud::BandwidthValidator;

use strict;
use warnings;

use Data::Dumper;

use GRNOC::Config;

use OESS::DB::Endpoint;
use OESS::DB::Interface;

=head1 OESS::Cloud::BandwidthValidator

BandwidthValidator loads an xml configuration containing a list of
interface-selectors. When matched against a connection's endpoint,
these interface-selectors define the set of valid bandwidth speeds
which may be reserved for the connection.

    <config>
        <interface-selector min_bandwidth="100" max_bandwidth="10000" cloud_interconnect_type="azure-express-route">
            <speed rate="100" />
            <speed rate="500" />
            <speed rate="1000" />
        </interface-selector>
    </config>

=cut

=head2 new

=cut
sub new {
    my $class = shift;
    my $args  = {
        config_path => '/etc/oess/interface-speed-config.xml', # String
        interface   => undef, # OESS::Interface
        logger      => Log::Log4perl->get_logger("OESS.Cloud.BandwidthValidator"),
        @_
    };
    my $self = bless $args, $class;

    $self->{config} = undef;

    return $self;
}

=head2 load

=cut
sub load {
    my $self = shift;

    my $config = new GRNOC::Config(config_file => $self->{config_path}, force_array => 1);
    my $selectors = $config->get("/config/interface-selector");
    $self->{interface_selectors} = $selectors;
}

=head2 is_bandwidth_valid

The arguments passsed to C<is_bandwidth_valid> are checked against
each configured endpoint-selector. If a match is made,
C<is_bandwidth_valid> checks that the requested speed is allowed to
be:

1. Set by the requesting user
2. Used on the specified interface

=cut
sub is_bandwidth_valid {
    my $self = shift;
    my $args = {
        bandwidth => undef,
        is_admin => undef,
        @_
    };

    my $active_selector;
    foreach my $selector (@{$self->{interface_selectors}}) {
        if ($self->{interface}->cloud_interconnect_type ne $selector->{cloud_interconnect_type}) {
            next;
        }
        # 1. Matched on interface interconnect type

        if ($self->{interface}->{'bandwidth'} > $selector->{max_bandwidth} || $self->{interface}->{'bandwidth'} < $selector->{min_bandwidth}) {
            next;
        }
        # 2. Matched on interface speed

        $active_selector = $selector;
        last;
    }

    foreach my $check (@{$active_selector->{speed}}) {
        if ($check->{rate} != $args->{bandwidth}) {
            next;
        }

        if (defined $check->{admin_only} && $check->{admin_only} eq "1" && $args->{is_admin} != 1) {
            next;
        }

        return 1;
    }

    return 0;
}

return 1;
