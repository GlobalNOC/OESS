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
            $self->{config_obj}->nso_host . "/restconf/data/",
            'Content-type' => 'application/yang-data+json',
            'Content'      => encode_json($payload)
        );
        return if ($res->content eq ''); # Empty payload indicates success

        my $result = decode_json($res->content);
        die $self->get_json_errors($result->{errors}) if (defined $result->{errors});
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
            $self->{config_obj}->nso_host . "/restconf/data/oess-l2connection:oess-l2connection=$conn_id",
            'Content-type' => 'application/yang-data+json'
        );
        return if ($res->content eq ''); # Empty payload indicates success

        my $result = decode_json($res->content);
        die $self->get_json_errors($result->{errors}) if (defined $result->{errors});
    };
    if ($@) {
        my $err = $@;
        warn $err;
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
            $self->{config_obj}->nso_host . "/restconf/data/oess-l2connection:oess-l2connection=$conn_id",
            'Content-type' => 'application/yang-data+json',
            'Content'      => encode_json($payload)
        );
        return if ($res->content eq ''); # Empty payload indicates success

        my $result = decode_json($res->content);
        die $self->get_json_errors($result->{errors}) if (defined $result->{errors});
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
            $self->{config_obj}->nso_host . "/restconf/data/oess-l2connection:oess-l2connection",
            'Content-type' => 'application/yang-data+json'
        );
        if ($res->content eq '') { # Empty payload indicates success
            $connections = [];
        } else {
            my $result = decode_json($res->content);
            die $self->get_json_errors($result->{errors}) if (defined $result->{errors});
            $connections = $result->{"oess-l2connection:oess-l2connection"};
        }
    };
    if ($@) {
        my $err = $@;
        warn $err;
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

=cut
sub get_json_errors {
    my $self = shift;
    my $errs = shift;

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
            tag         => $ep->tag,
            peer        => []
        };
        if (defined $ep->inner_tag) {
            $obj->{inner_tag} = $ep->inner_tag;
        }

        foreach my $peer (@{$ep->peers}) {
            my $peer_obj = {
                peer_id    => $peer->vrf_ep_peer_id,
                local_asn  => $self->{local_asn},
                local_ip   => $peer->local_ip,
                peer_asn   => $peer->peer_asn,
                peer_ip    => $peer->peer_ip,
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
            $self->{config_obj}->nso_host . "/restconf/data/",
            'Content-type' => 'application/yang-data+json',
            'Content'      => encode_json($payload)
        );
        return if ($res->content eq ''); # Empty payload indicates success

        my $result = decode_json($res->content);
        die $self->get_json_errors($result->{errors}) if (defined $result->{errors});
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
            $self->{config_obj}->nso_host . "/restconf/data/oess-l3connection:oess-l3connection=$conn_id",
            'Content-type' => 'application/yang-data+json'
        );
        return if ($res->content eq ''); # Empty payload indicates success

        my $result = decode_json($res->content);
        die $self->get_json_errors($result->{errors}) if (defined $result->{errors});
    };
    if ($@) {
        my $err = $@;
        warn $err;
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
            tag         => $ep->tag,
            peer        => []
        };
        if (defined $ep->inner_tag) {
            $obj->{inner_tag} = $ep->inner_tag;
        }

        foreach my $peer (@{$ep->peers}) {
            my $peer_obj = {
                peer_id    => $peer->vrf_ep_peer_id,
                local_asn  => $self->{local_asn},
                local_ip   => $peer->local_ip,
                peer_asn   => $peer->peer_asn,
                peer_ip    => $peer->peer_ip,
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
        my $res = $self->{www}->put(
            $self->{config_obj}->nso_host . "/restconf/data/oess-l3connection:oess-l3connection=$conn_id",
            'Content-type' => 'application/yang-data+json',
            'Content'      => encode_json($payload)
        );
        return if ($res->content eq ''); # Empty payload indicates success

        my $result = decode_json($res->content);
        die $self->get_json_errors($result->{errors}) if (defined $result->{errors});
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
            $self->{config_obj}->nso_host . "/restconf/data/oess-l3connection:oess-l3connection",
            'Content-type' => 'application/yang-data+json'
        );
        if ($res->content eq '') { # Empty payload indicates success
            $connections = [];
        } else {
            my $result = decode_json($res->content);
            die $self->get_json_errors($result->{errors}) if (defined $result->{errors});
            $connections = $result->{"oess-l3connection:oess-l3connection"};
        }
    };
    if ($@) {
        my $err = $@;
        warn $err;
        return (undef, $err);
    }
    return ($connections, undef);
}

1;
