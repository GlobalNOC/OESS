package OESS::Cloud;

use strict;
use warnings;

use Exporter;

use OESS::Cloud::AWS;


=head2 setup_endpoints

setup_endpoints configures cloud services for any interface in
C<$endpoints> with a configured cloud interconnect id. Once complete,
any information related to new cloud services is recorded in the
resulting endpoint list. The resulting endpoint list should be used as
a replacement for the parent VRF's endpoints.

    my $setup_endpoints = Cloud::setup_endpoints('vrf1', $vrf->endpoints, 123456789);
    $vrf->endpoints($setup_endpoints);
    $vrf->update_db();

=cut
sub setup_endpoints {
    my $vrf_name   = shift;
    my $endpoints  = shift;
    my $result     = [];

    foreach my $ep (@$endpoints) {
        if (!$ep->interface()->cloud_interconnect_id) {
            push @$result, $ep;
            next;
        }

        warn "oooooooooooo AWS oooooooooooo";
        my $aws = OESS::Cloud::AWS->new();

        if ($ep->interface()->cloud_interconnect_type eq 'aws-hosted-connection') {
            my $res = $aws->allocate_connection(
                $vrf_name,
                $ep->cloud_account_id,
                $ep->tag,
                $ep->bandwidth . 'Mbps'
            );
            $ep->cloud_account_id($ep->cloud_account_id);
            $ep->cloud_connection_id($res->{ConnectionId});
            push @$result, $ep;

        } elsif ($ep->interface()->cloud_interconnect_type eq 'aws-hosted-vinterface') {
            my $peer = $ep->peers()->[0];

            my $ip_version = 'ipv4';
            if ($peer->local_ip !~ /^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/([0-9]|[1-2][0-9]|3[0-2]))$/) {
                $ip_version = 'ipv6';
            }

            my $res = $aws->allocate_vinterface(
                $ep->cloud_account_id,
                $ip_version,
                $peer->peer_ip,
                $peer->peer_asn || 55038,
                $peer->md5_key || '6f5902ac237024bdd0c176cb93063dc4',
                $peer->local_ip,
                $vrf_name,
                $ep->tag
            );
            $ep->cloud_account_id($ep->cloud_account_id);
            $ep->cloud_connection_id($res->{VirtualInterfaceId});
            push @$result, $ep;

        } else {
            warn "Cloud interconnect type is not supported.";
            push @$result, $ep;
        }
    }

    return $result;
}

=head2 cleanup_endpoints

cleanup_endpoints removes cloud services for any interface in
C<$endpoints> with a configured cloud interconnect id.

    my $ok = Cloud::cleanup_endpoints($vrf->endpoints);

=cut
sub cleanup_endpoints {
    my $endpoints = shift;

    foreach my $ep (@$endpoints) {
        if (!$ep->interface()->cloud_interconnect_id) {
            next;
        }

        warn "oooooooooooo AWS oooooooooooo";
        my $aws = OESS::Cloud::AWS->new();

        if ($ep->interface()->cloud_interconnect_type eq 'aws-hosted-connection') {
            my $aws_account = $ep->cloud_account_id;
            my $aws_connection = $ep->cloud_connection_id;
            warn "Removing aws conn $aws_connection from $aws_account";
            $aws->delete_connection($aws_connection);

        } elsif ($ep->interface()->cloud_interconnect_type eq 'aws-hosted-vinterface') {
            my $aws_account = $ep->cloud_account_id;
            my $aws_connection = $ep->cloud_connection_id;
            warn "Removing aws vint $aws_connection from $aws_account";
            $aws->delete_vinterface($aws_connection);

        } else {
            warn "Cloud interconnect type is not supported.";
        }
    }

    return 1;
}

return 1;
