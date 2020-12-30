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
        config          => undef,
        config_filename => '/etc/oess/database.xml',
        logger          => Log::Log4perl->get_logger('OESS.NSO.Client'),
        @_
    };
    my $self = bless $args, $class;

    if (!defined $self->{config}) {
        $self->{config} = new OESS::Config(config_filename => $self->{config_filename});
    }

    $self->{www} = new LWP::UserAgent;
    my $host = $self->{config}->nso_host;
    $host =~ s/http(s){0,1}:\/\///g; # Strip http:// or https:// from string
    $self->{www}->credentials($host, "restconf", $self->{config}->nso_username, $self->{config}->nso_password);

    return $self;
}

=head2 create_l2connection

    my $err = create_l2connection($l2connection);

=cut
sub create_l2connection {
    my $self = shift;
    my $conn = shift; # OESS::L2Circuit
    warn Dumper($conn->to_hash);

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
        "internet2-l2connection:internet2-l2connection" => [
            {
                "connection_id" => $conn->circuit_id,
                "endpoint" => $eps
            }
        ]
    };

    eval {
        my $res = $self->{www}->post(
            $self->{config}->nso_host . "/restconf/data/",
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
            $self->{config}->nso_host . "/restconf/data/internet2-l2connection:internet2-l2connection=$conn_id",
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
    warn Dumper($conn->to_hash);

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
        "internet2-l2connection:internet2-l2connection" => [
            {
                "connection_id" => $conn_id,
                "endpoint" => $eps
            }
        ]
    };

    eval {
        my $res = $self->{www}->put(
            $self->{config}->nso_host . "/restconf/data/internet2-l2connection:internet2-l2connection=$conn_id",
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

=head2 get_json_errors

get_json_errors is a helper method to extract errors returned from nso's rest
api.

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

1;
