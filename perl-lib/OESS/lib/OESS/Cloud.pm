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
                $ep->interface()->cloud_interconnect_id,
                $vrf_name,
                $ep->cloud_account_id,
                $ep->tag,
                $ep->bandwidth . 'Mbps'
            );
            $ep->cloud_account_id($ep->cloud_account_id);
            $ep->cloud_connection_id($res->{ConnectionId});
            push @$result, $ep;

        } elsif ($ep->interface()->cloud_interconnect_type eq 'aws-hosted-vinterface') {
            my $amazon_addr   = undef;
            my $asn           = 55038;
            my $auth_key      = undef;
            my $customer_addr = undef;
            my $ip_version    = 'ipv6';

            my $peer = $ep->peers()->[0];
            if (defined $peer) {
                $amazon_addr   = $peer->peer_ip;
                $auth_key      = $peer->md5_key;
                $customer_addr = $peer->local_ip;

                if ($peer->local_ip =~ /^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/([0-9]|[1-2][0-9]|3[0-2]))$/) {
                    $ip_version = 'ipv4';
                }
            }

            my $res = $aws->allocate_vinterface(
                $ep->interface()->cloud_interconnect_id,
                $ep->cloud_account_id,
                $ip_version,
                $amazon_addr,
                $asn,
                $auth_key,
                $customer_addr,
                $vrf_name,
                $ep->tag
            );
            $ep->cloud_account_id($ep->cloud_account_id);
            $ep->cloud_connection_id($res->{VirtualInterfaceId});
            $peer->peer_asn($res->{AmazonSideAsn});
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
            $aws->delete_connection($ep->interface()->cloud_interconnect_id, $aws_connection);

        } elsif ($ep->interface()->cloud_interconnect_type eq 'aws-hosted-vinterface') {
            my $aws_account = $ep->cloud_account_id;
            my $aws_connection = $ep->cloud_connection_id;
            warn "Removing aws vint $aws_connection from $aws_account";
            $aws->delete_vinterface($ep->interface()->cloud_interconnect_id, $aws_connection);

        } else {
            warn "Cloud interconnect type is not supported.";
        }
    }

    return 1;
}

return 1;
