package OESS::NSO::Client;

use Data::Dumper;
use HTTP::Request::Common;
use JSON;
use Log::Log4perl;
use LWP::UserAgent;
use XML::LibXML;

=head1 OESS::NSO::Client

OESS::NSO::Client provides a perl interface to the NSO web api.

=cut

=head2 new

=cut
sub new {
    my $class = shift;
    my $args  = {
        config_obj      => undef,
        config_filename => '/etc/oess/database.xml',
        logger          => Log::Log4perl->get_logger('OESS.NSO.Client'),
        local_asn       => undef,
        @_
    };
    my $self = bless $args, $class;

    if (!defined $self->{config_obj}) {
        $self->{config_obj} = new OESS::Config(config_filename => $self->{config_filename});
    }
    $self->{local_asn} = $self->{config_obj}->local_as;

    $self->{www} = new LWP::UserAgent;
    my $host = $self->{config_obj}->nso_host;
    $host =~ s/http(s){0,1}:\/\///g; # Strip http:// or https:// from string
    $self->{www}->credentials($host, "restconf", $self->{config_obj}->nso_username, $self->{config_obj}->nso_password);

    return $self;
}

=head2 create_l2connection

    my $err = create_l2connection($l2connection);

=cut
sub create_l2connection {
    my $self = shift;
    my $conn = shift; # OESS::L2Circuit

    my $eps = [];
    foreach my $ep (@{$conn->endpoints}) {
        my $obj = {
            endpoint_id => $ep->circuit_ep_id,
            bandwidth   => $ep->bandwidth,
            device      => $ep->node,
            interface   => $ep->interface,
            unit        => $ep->unit,
            tag         => $ep->tag
        };
        if (defined $ep->inner_tag) {
            $obj->{inner_tag} = $ep->inner_tag;
        }
        push(@$eps, $obj);
    }

    my $payload = {
        "oess-l2connection:oess-l2connection" => [
            {
                "connection_id" => $conn->circuit_id,
                "endpoint" => $eps
            }
        ]
    };

    eval {
        my $res = $self->{www}->post(
            $self->{config_obj}->nso_host . "/restconf/data/tailf-ncs:services/?unhide=oess",
            'Content-type' => 'application/yang-data+json',
            'Content'      => encode_json($payload)
        );
        return if ($res->content eq ''); # Empty payload indicates success

        my $result = decode_json($res->content);
        my $err = $self->get_json_errors($result);
        die $err if defined $err;
    };
    if ($@) {
        my $err = $@;
        warn $err;
        return $err;
    }
    return;
}

=head2 delete_l2connection

    my $err = delete_l2connection($l2connection_id);

=cut
sub delete_l2connection {
    my $self = shift;
    my $conn_id = shift; # OESS::L2Circuit->circuit_id

    eval {
        my $res = $self->{www}->delete(
            $self->{config_obj}->nso_host . "/restconf/data/tailf-ncs:services/oess-l2connection:oess-l2connection=$conn_id?unhide=oess",
            'Content-type' => 'application/yang-data+json'
        );
        return if ($res->content eq ''); # Empty payload indicates success

        my $result = decode_json($res->content);
        my $err = $self->get_json_errors($result);
        die $err if defined $err;
    };
    if ($@) {
        my $err = $@;
        return $err;
    }
    return;
}

=head2 edit_l2connection

    my $err = edit_l2connection($l2connection);

=cut
sub edit_l2connection {
    my $self = shift;
    my $conn = shift; # OESS::L2Circuit

    my $eps = [];
    foreach my $ep (@{$conn->endpoints}) {
        my $obj = {
            endpoint_id => $ep->circuit_ep_id,
            bandwidth   => $ep->bandwidth,
            device      => $ep->node,
            interface   => $ep->interface,
            unit        => $ep->unit,
            tag         => $ep->tag
        };
        if (defined $ep->inner_tag) {
            $obj->{inner_tag} = $ep->inner_tag;
        }
        push(@$eps, $obj);
    }

    my $conn_id = $conn->circuit_id;
    my $payload = {
        "oess-l2connection:oess-l2connection" => [
            {
                "connection_id" => $conn_id,
                "endpoint" => $eps
            }
        ]
    };

    eval {
        my $res = $self->{www}->put(
            $self->{config_obj}->nso_host . "/restconf/data/tailf-ncs:services/oess-l2connection:oess-l2connection=$conn_id?unhide=oess",
            'Content-type' => 'application/yang-data+json',
            'Content'      => encode_json($payload)
        );
        return if ($res->content eq ''); # Empty payload indicates success

        my $result = decode_json($res->content);
        my $err = $self->get_json_errors($result);
        die $err if defined $err;
    };
    if ($@) {
        my $err = $@;
        warn $err;
        return $err;
    }
    return;
}

=head2 get_l2connections

    my ($connections, $err) = get_l2connections();

=cut
sub get_l2connections {
    my $self = shift;

    my $connections;
    eval {
        my $res = $self->{www}->get(
            $self->{config_obj}->nso_host . "/restconf/data/tailf-ncs:services/oess-l2connection:oess-l2connection/?unhide=oess",
            'Content-type' => 'application/yang-data+json'
        );
        if ($res->content eq '') { # Empty payload indicates success
            $connections = [];
        } else {
            my $result = decode_json($res->content);
            my $err = $self->get_json_errors($result);
            die $err if defined $err;
            $connections = $result->{"oess-l2connection:oess-l2connection"};
        }
    };
    if ($@) {
        my $err = $@;
        return (undef, $err);
    }
    return ($connections, undef);
}

=head2 get_json_errors

get_json_errors is a helper method to extract errors returned from nso's rest
api.

Response code:
- 201 on success
- 204 on success no content
- 400 on error
- 409 on error conflict

Response body:

    {
      "errors": {
        "error": [
          {
            "error-message": "object already exists: /oess-l2connection:oess-l2connection[oess-l2connection:connection_id='124']",
            "error-path": "",
            "error-tag": "data-exists",
            "error-type": "application"
          }
        ]
      }
    }

or

    {
      "ietf-restconf:errors": {
        "error": [
            {
            "error-type": "application",
            "error-tag": "invalid-value",
            "error-message": "uri keypath not found"
          }
        ]
      }
    }

=cut
sub get_json_errors {
    my $self = shift;
    my $resp = shift;

    my $errs;
    if (defined $resp->{errors}) {
        $errs = $resp->{errors};
    }
    if (defined $resp->{'ietf-restconf:errors'}) {
        $errs = $resp->{'ietf-restconf:errors'};
    }
    return if !defined $errs;

    my $errors = [];
    foreach my $err (@{$errs->{error}}) {
        push(@$errors, $err->{'error-message'});
    }

    my $r = join(". ", @$errors);
    return $r;
}

=head2 create_l3connection

=cut
sub create_l3connection {
    my $self = shift;
    my $conn = shift; # OESS::VRF

    my $eps = [];
    foreach my $ep (@{$conn->endpoints}) {
        my $obj = {
            endpoint_id => $ep->vrf_endpoint_id,
            bandwidth   => $ep->bandwidth,
            device      => $ep->node,
            interface   => $ep->interface,
            unit        => $ep->unit,
            tag         => $ep->tag,
            mtu         => $ep->mtu,
            peer        => []
        };
        if (defined $ep->inner_tag) {
            $obj->{inner_tag} = $ep->inner_tag;
        }

        foreach my $peer (@{$ep->peers}) {
            my @peer_ip = split('/', $peer->peer_ip);

            my $peer_obj = {
                peer_id    => $peer->vrf_ep_peer_id,
                local_asn  => $self->{local_asn},
                local_ip   => $peer->local_ip,
                peer_asn   => $peer->peer_asn,
                peer_ip    => $peer_ip[0],
                bfd        => $peer->bfd,
                md5_key    => $peer->md5_key,
                ip_version => $peer->ip_version
            };
            push @{$obj->{peer}}, $peer_obj;
        }

        push(@$eps, $obj);
    }

    my $payload = {
        "oess-l3connection:oess-l3connection" => [
            {
                "connection_id" => $conn->vrf_id,
                "endpoint" => $eps
            }
        ]
    };

    eval {
        my $res = $self->{www}->post(
            $self->{config_obj}->nso_host . "/restconf/data/tailf-ncs:services/?unhide=oess",
            'Content-type' => 'application/yang-data+json',
            'Content'      => encode_json($payload)
        );
        return if ($res->content eq ''); # Empty payload indicates success

        my $result = decode_json($res->content);
        my $err = $self->get_json_errors($result);
        die $err if defined $err;
    };
    if ($@) {
        my $err = $@;
        warn $err;
        return $err;
    }
    return;
}

=head2 delete_l3connection

    my $err = delete_l3connection($l3connection_id);

=cut
sub delete_l3connection {
    my $self = shift;
    my $conn_id = shift; # OESS::VRF->vrf_id

    eval {
        my $res = $self->{www}->delete(
            $self->{config_obj}->nso_host . "/restconf/data/tailf-ncs:services/oess-l3connection:oess-l3connection=$conn_id?unhide=oess",
            'Content-type' => 'application/yang-data+json'
        );
        return if ($res->content eq ''); # Empty payload indicates success

        my $result = decode_json($res->content);
        my $err = $self->get_json_errors($result);
        die $err if defined $err;
    };
    if ($@) {
        my $err = $@;
        return $err;
    }
    return;
}

=head2 edit_l3connection

    my $err = edit_l3connection($l3connection);

=cut
sub edit_l3connection {
    my $self = shift;
    my $conn = shift; # OESS::VRF

    my $eps = [];
    foreach my $ep (@{$conn->endpoints}) {
        my $obj = {
            endpoint_id => $ep->vrf_endpoint_id,
            bandwidth   => $ep->bandwidth,
            device      => $ep->node,
            interface   => $ep->interface,
            unit        => $ep->unit,
            tag         => $ep->tag,
            mtu         => $ep->mtu,
            peer        => []
        };
        if (defined $ep->inner_tag) {
            $obj->{inner_tag} = $ep->inner_tag;
        }

        foreach my $peer (@{$ep->peers}) {
            my @peer_ip = split('/', $peer->peer_ip);

            my $peer_obj = {
                peer_id    => $peer->vrf_ep_peer_id,
                local_asn  => $self->{local_asn},
                local_ip   => $peer->local_ip,
                peer_asn   => $peer->peer_asn,
                peer_ip    => $peer_ip[0],
                bfd        => $peer->bfd,
                md5_key    => $peer->md5_key,
                ip_version => $peer->ip_version
            };
            push @{$obj->{peer}}, $peer_obj;
        }

        push(@$eps, $obj);
    }

    my $conn_id = $conn->vrf_id;
    my $payload = {
        "oess-l3connection:oess-l3connection" => [
            {
                "connection_id" => $conn->vrf_id,
                "endpoint" => $eps
            }
        ]
    };

    eval {
        my $res = $self->{www}->put(
            $self->{config_obj}->nso_host . "/restconf/data/tailf-ncs:services/oess-l3connection:oess-l3connection=$conn_id?unhide=oess",
            'Content-type' => 'application/yang-data+json',
            'Content'      => encode_json($payload)
        );
        return if ($res->content eq ''); # Empty payload indicates success

        my $result = decode_json($res->content);
        my $err = $self->get_json_errors($result);
        die $err if defined $err;
    };
    if ($@) {
        my $err = $@;
        warn $err;
        return $err;
    }
    return;
}

=head2 get_l3connections

    my ($connections, $err) = get_l3connections();

=cut
sub get_l3connections {
    my $self = shift;

    my $connections;
    eval {
        my $res = $self->{www}->get(
            $self->{config_obj}->nso_host . "/restconf/data/tailf-ncs:services/oess-l3connection:oess-l3connection/?unhide=oess",
            'Content-type' => 'application/yang-data+json'
        );
        if ($res->content eq '') { # Empty payload indicates success
            $connections = [];
        } else {
            my $result = decode_json($res->content);
            my $err = $self->get_json_errors($result);
            die $err if defined $err;
            $connections = $result->{"oess-l3connection:oess-l3connection"};
        }
    };
    if ($@) {
        my $err = $@;
        return (undef, $err);
    }
    return ($connections, undef);
}

=head2 get_backbones

    my ($backbones, $err) = get_backbones();

Returns:

    [
      {
        "name": "POPA-POPB-00,
        "pdp":  [ { "name": "POPA-AAA-0" }, { "name": "POPB-AAA-0" },
        "summary": {
          "endpoint": [
            "device": "xr0",
            "if-full": "HundredGigE3/1",
            ...
          ],
          ...
        },
        ...
      }
    ]

=cut
sub get_backbones {
    my $self = shift;

    my $backbones;
    eval {
        my $res = $self->{www}->get(
            $self->{config_obj}->nso_host . "/restconf/data/tailf-ncs:services/backbone:backbone/",
            'Content-type' => 'application/yang-data+json'
        );
        if ($res->content eq '') { # Empty payload indicates success
            $backbones = [];
        } else {
            my $result = decode_json($res->content);
            my $err = $self->get_json_errors($result);
            die $err if defined $err;
            $backbones = $result->{"backbone:backbone"};
        }
    };
    if ($@) {
        my $err = $@;
        return (undef, $err);
    }
    return ($backbones, undef);
}

=head2 get_vrf_statistics

    my ($stats, $err) = get_vrf_statistics();

Returns:

    [
          {
            'messages_received' => '0',
            'prefixes_synced' => '0',
            'prefixes_advertised' => '0',
            'remote_ip' => '192.168.2.2',
            'bytes_read' => '0',
            'vrf_id' => '6000',
            'connection_state' => 'BGP_ST_ACTIVE',
            'prefixes_denied' => '0',
            'bytes_written' => '0',
            'prefixes_suppressed' => '0',
            'vrf_name' => 'OESS-VRF-6000',
            'node' => 'agg2.bldc',
            'messages_sent' => '0',
            'prefixes_accepted' => '0',
            'remote_as' => '2'
          },
          {
            'messages_received' => '1873',
            'prefixes_synced' => '0',
            'prefixes_advertised' => '0',
            'remote_ip' => '192.168.70.2',
            'bytes_read' => '85769',
            'vrf_id' => '6000',
            'connection_state' => 'BGP_ST_ACTIVE',
            'prefixes_denied' => '0',
            'bytes_written' => '102456',
            'prefixes_suppressed' => '0',
            'vrf_name' => 'OESS-VRF-6000',
            'node' => 'agg2.bldc',
            'messages_sent' => '2846',
            'prefixes_accepted' => '0',
            'remote_as' => '4200000700'
          }
    ]

=cut
sub get_vrf_statistics {
    my $self = shift;
    my $node = shift; # Name of node to query

    my $payload = {
        "input" => {
            "args" => "show operational BGP InstanceTable Instance/InstanceName=default InstanceActive VRFTable VRF/VRFName=* NeighborTable xml"
        }
    };

    my $response = [];
    eval {
        my $res = $self->{www}->post(
            $self->{config_obj}->nso_host . "/restconf/operations/tailf-ncs:devices/device=$node/live-status/exec/any",
            'Content-type' => 'application/yang-data+json',
            'Content'      => encode_json($payload)
        );
        if ($res->content eq '') {
            # Unlike other api endpoints. If this happens something must have gone wrong.
            return (undef, "Could't get valid response from get_vrf_statistisc for device $node.");
        } else {
            my $result = decode_json($res->content);
            my $err = $self->get_json_errors($result);
            die $err if defined $err;

            # Extract CLI payload from JSON response and strip leading
            # xml tag and ending cli prompt. This results in an XML
            # encoded string wrapped in the Response tag.
            my $raw_response = $result->{"tailf-ned-cisco-ios-xr-stats:output"}->{"result"};
            $raw_response =~ s/^.*<Response/<Response/s;
            $raw_response =~ s/<\/Response>.*\z/<\/Response>/s;
            # warn Dumper($raw_response);

            # Parse XMl string and extract statistics
            my $dom = XML::LibXML->load_xml(string => $raw_response);

            # Lookup Instance named 'default' and get VRFTable from inside
            my $instances = $dom->findnodes('//Response/Get/Operational/BGP/InstanceTable/Instance');
            my $instance  = undef;
            foreach my $context ($instances->get_nodelist) {

                my $instance_name = $context->findvalue('//Instance/Naming/InstanceName');
                $instance_name =~ s/\s+//g;
                next if $instance_name ne 'default';

                my $vrfs = $context->findnodes('//Instance/InstanceActive/VRFTable/VRF');
                foreach my $context ($vrfs->get_nodelist) {
                    my $ok = $context->exists('./Naming/VRFName');

                    # <VRF><Naming><VRFName>
                    my $vrf_name = $context->findvalue('./Naming/VRFName');
                    $vrf_name =~ s/\s+//g;
                    next if $vrf_name !~ /^OESS-VRF/;

                    $vrf_name =~ /OESS-VRF-(\d+)/;
                    $vrf_id = $1;

                    my $peers = $context->findnodes('./NeighborTable/Neighbor');
                    foreach my $context ($peers->get_nodelist) {
                        my $stat = {
                            vrf_name            => $vrf_name,
                            vrf_id              => $vrf_id,
                            node                => $node,
                            remote_ip           => undef,
                            connection_state    => undef,
                            bytes_read          => 0,
                            bytes_written       => 0,
                            messages_received   => 0,
                            messages_sent       => 0,
                            prefixes_accepted   => 0,
                            prefixes_denied     => 0,
                            prefixes_advertised => 0,
                            prefixes_suppressed => 0,
                            prefixes_synced     => 0,
                        };

                        # Neighbor addresses to associate with stats.
                        # <VRF><NeighborTable><Neighbor><Naming><NeighborAddress><IPV4Address>
                        # <VRF><NeighborTable><Neighbor><Naming><NeighborAddress><IPV6Address>
                        my $ipv4 = $context->exists('./Naming/NeighborAddress/IPV4Address');
                        if ($ipv4) {
                            $stat->{remote_ip} = $context->findvalue('./Naming/NeighborAddress/IPV4Address');
                        } else {
                            $stat->{remote_ip} = $context->findvalue('./Naming/NeighborAddress/IPV6Address');
                        }
                        $stat->{remote_ip} =~ s/\s+//g;

                        # <VRF><NeighborTable><Neighbor><RemoteASNumber>
                        $stat->{remote_as} = $context->findvalue('./RemoteASNumber');
                        $stat->{remote_as} =~ s/\s+//g;

                        # <VRF><NeighborTable><Neighbor><ConnectionState> (BGP_ST_ACTIVE|BGP_ST_ESTAB|BGP_ST_IDLE)
                        $stat->{connection_state} = $context->findvalue('./ConnectionState');
                        $stat->{connection_state} =~ s/\s+//g;

                        # <VRF><NeighborTable><Neighbor><PerformanceStatistics><DataBytesRead>
                        $stat->{bytes_read} = $context->findvalue('./PerformanceStatistics/DataBytesRead');
                        $stat->{bytes_read} =~ s/\s+//g;

                        # <VRF><NeighborTable><Neighbor><PerformanceStatistics><DataBytesWritten>
                        $stat->{bytes_written} = $context->findvalue('./PerformanceStatistics/DataBytesWritten');
                        $stat->{bytes_written} =~ s/\s+//g;

                        # <VRF><NeighborTable><Neighbor><MessagesReceived>
                        $stat->{messages_received} = $context->findvalue('./MessagesReceived');
                        $stat->{messages_received} =~ s/\s+//g;

                        # <VRF><NeighborTable><Neighbor><MessagesSent>
                        $stat->{messages_sent} = $context->findvalue('./MessagesSent');
                        $stat->{messages_sent} =~ s/\s+//g;

                        my $afdatas = $context->findnodes('./AFData/Entry');
                        foreach my $context ($afdatas->get_nodelist) {
                            # I'm assuming one entry per-neighbor. Hopefully always the same type.
                            # <VRF><NeighborTable><Neighbor><AFData><Entry><AFName>IPv4
                            # <VRF><NeighborTable><Neighbor><AFData><Entry><AFName>IPv6
                            my $ip_version = $context->findvalue('./AFName');
                            $ip_version =~ s/\s+//g;

                            # Only record v4 peering stats if neighbor is using ipv4
                            # Only record v6 peering stats if neighbor is using ipv6
                            next if $ipv4 && $ip_version eq 'IPv6';
                            next if !$ipv4 && $ip_version eq 'IPv4';

                            # <VRF><NeighborTable><Neighbor><AFData><Entry><PrefixesAccepted>
                            # <VRF><NeighborTable><Neighbor><AFData><Entry><PrefixesDenied>
                            # <VRF><NeighborTable><Neighbor><AFData><Entry><PrefixesAdvertised>
                            # <VRF><NeighborTable><Neighbor><AFData><Entry><PrefixesSuppressed>
                            # <VRF><NeighborTable><Neighbor><AFData><Entry><PrefixesSynced>
                            $stat->{prefixes_accepted} = $context->findvalue('./PrefixesAccepted');
                            $stat->{prefixes_accepted} =~ s/\s+//g;
                            $stat->{prefixes_denied} = $context->findvalue('./PrefixesDenied');
                            $stat->{prefixes_denied} =~ s/\s+//g;
                            $stat->{prefixes_advertised} = $context->findvalue('./PrefixesAdvertised');
                            $stat->{prefixes_advertised} =~ s/\s+//g;
                            $stat->{prefixes_suppressed} = $context->findvalue('./PrefixesSuppressed');
                            $stat->{prefixes_suppressed} =~ s/\s+//g;
                            $stat->{prefixes_synced} = $context->findvalue('./PrefixesSynced');
                            $stat->{prefixes_synced} =~ s/\s+//g;
                        }

                        push @$response, $stat;
                    }
                }
            }
        }
    };
    if ($@) {
        my $err = $@;
        return (undef, $err);
    }
    return ($response, undef);
}

1;
