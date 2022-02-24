package OESS::Cloud::AzureInterfaceSelector;

use strict;
use warnings;

use Data::Dumper;

use OESS::DB::Endpoint;
use OESS::DB::Interface;

=head1 OESS::Cloud::AzureInterfaceSelector

=cut

=head2 new

=cut
sub new {
    my $class = shift;
    my $args  = {
        azure       => undef, # OESS::Cloud::Azure
        db          => undef, # OESS::DB
        entity      => undef, # OESS::Entity
        logger      => Log::Log4perl->get_logger("OESS.Cloud.AzureInterfaceSelector"),
        service_key => undef, # String
        @_
    };
    my $self = bless $args, $class;

    # selected_interfaces is an in-memory record of interfaces
    # selected by this object. This allows successive invocations of
    # select to return the next available interface without additional
    # database queries.
    $self->{selected_interfaces} = {};

    return $self;
}

=head2 select_interface

=cut
sub select_interface {
    my $self = shift;

    my $intfs = $self->{entity}->interfaces;
    if (!$intfs) {
        $self->{logger}->error("Cloudn't find interfaces on entity $self->{entity}->{name}.");
        return;
    }

    my $interface_index = {};
    my $interconnect_id;
    foreach my $intf (@$intfs) {
        if ($intf->cloud_interconnect_type eq 'azure-express-route') {
            $interconnect_id = $intf->cloud_interconnect_id;
            $interface_index->{$intf->interface_id} = $intf;
        }
    }
    if (!$interconnect_id) {
        $self->{logger}->error("Cloudn't find azure interconnect on entity $self->{entity}->{name}.");
        return;
    }

    my ($eps, $err) = OESS::DB::Endpoint::fetch_all(
        db => $self->{db},
        cloud_account_id => $self->{service_key}
    );
    if (defined $err) {
        $self->{logger}->error($err);
        return;
    }
    foreach my $ep (@$eps) {
        $self->{selected_interfaces}->{$ep->{interface_id}} = 1;
    }

    my $conn = $self->{azure}->expressRouteCrossConnection($interconnect_id, $self->{service_key});
    if (defined $conn->{error}) {
        $self->{logger}->error($conn->{error}->{message});
        return;
    }
    my $primary_id = $conn->{properties}->{primaryAzurePort};
    my $secondary_id = $conn->{properties}->{secondaryAzurePort};

    my $pri = OESS::DB::Interface::fetch(
        db => $self->{db},
        cloud_interconnect_id => $primary_id
    );
    if (!defined $pri) {
        $self->{logger}->error("Couldn't find primary azure interconnect $primary_id.");
    }
    elsif (!defined $self->{selected_interfaces}->{$pri->{interface_id}}) {
        $self->{selected_interfaces}->{$pri->{interface_id}} = 1;
        $self->{logger}->info("Selected primary azure interface $pri->{interface_id}.");
        return $interface_index->{$pri->{interface_id}};
    }

    my $sec = OESS::DB::Interface::fetch(
        db => $self->{db},
        cloud_interconnect_id => $secondary_id
    );
    if (!defined $sec) {
        $self->{logger}->error("Couldn't find secondary azure interconnect $secondary_id.");
    }
    elsif (!defined $self->{selected_interfaces}->{$sec->{interface_id}}) {
        $self->{selected_interfaces}->{$sec->{interface_id}} = 1;
        $self->{logger}->info("Selected secondary azure interface $pri->{interface_id}.");
        return $interface_index->{$sec->{interface_id}};
    }

    return;
}

return 1;
