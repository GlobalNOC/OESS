package OESS::NSO::ClientStub;

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
        @_
    };
    my $self = bless $args, $class;
    return $self;
}

=head2 create_l2connection

    my $err = create_l2connection($l2connection);

=cut
sub create_l2connection {
    my $self = shift;
    my $conn = shift; # OESS::L2Circuit
    return;
}

=head2 delete_l2connection

    my $err = delete_l2connection($l2connection_id);

=cut
sub delete_l2connection {
    my $self = shift;
    my $conn_id = shift; # OESS::L2Circuit->circuit_id
    return;
}

=head2 edit_l2connection

    my $err = edit_l2connection($l2connection);

=cut
sub edit_l2connection {
    my $self = shift;
    my $conn = shift; # OESS::L2Circuit
    return;
}

=head2 get_l2connections

    my ($connections, $err) = get_l2connections();

=cut
sub get_l2connections {
    my $self = shift;

    my $connections = [
        {
            'connection_id' => 4081,
            'directly-modified' => {
                'services' => [
                    '/i2-common:internal-services/sdp:sdp-attach[sdp:sdp=\'0\'][sdp:name=\'3000\']',
                    '/i2-common:internal-services/sdp:sdp-attach[sdp:sdp=\'1\'][sdp:name=\'3000\']'
                ],
                'devices' => [
                    'xr0'
                ]
            },
            'endpoint' => [
                {
                    'bandwidth' => 0,
                    'endpoint_id' => 1,
                    'interface' => 'GigabitEthernet0/0',
                    'tag' => 1,
                    'device' => 'xr0'
                },
                {
                    'bandwidth' => 0,
                    'endpoint_id' => 2,
                    'interface' => 'GigabitEthernet0/1',
                    'tag' => 1,
                    'device' => 'xr0'
                }
            ],
            'device-list' => [
                'xr0'
            ],
            'modified' => {
                'services' => [
                    '/i2-common:internal-services/sdp:sdp-attach[sdp:sdp=\'1\'][sdp:name=\'3000\']',
                    '/i2-common:internal-services/sdp:sdp-attach[sdp:sdp=\'0\'][sdp:name=\'3000\']'
                ],
                'devices' => [
                    'xr0'
                ]
            }
        }
    ];
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
    return;
}

=head2 delete_l3connection

    my $err = delete_l3connection($l3connection_id);

=cut
sub delete_l3connection {
    my $self = shift;
    my $conn_id = shift; # OESS::VRF->vrf_id
    return;
}

=head2 edit_l3connection

    my $err = edit_l3connection($l3connection);

=cut
sub edit_l3connection {
    my $self = shift;
    return;
}

=head2 get_l3connections

    my ($connections, $err) = get_l3connections();

=cut
sub get_l3connections {
    my $self = shift;

    my $connections = [
        {
            "connection_id" => 1,
            "endpoint" => [
                {
                    "endpoint_id" => 8,
                    "vars" => {
                        "pdp" => "CHIC-JJJ-0",
                        "ce_id" => 1,
                        "remote_ce_id" => 2
                    },
                    "device" => "Node 11",
                    "interface" => "e15/6",
                    "tag" => 300,
                    "bandwidth" => 200,
                    "peer" => [
                        {
                            "peer_id" => 1,
                            "local_asn" => 64600,
                            "local_ip" => "192.168.3.2/31",
                            "peer_asn" => 64001,
                            "peer_ip" => "192.168.3.3/31",
                            "bfd" => 1,
                            "ip_version" => "ipv4"
                        }
                    ]
                },
                {
                    "endpoint_id" => 2,
                    "vars" => {
                        "pdp" => "CHIC-JJJ-1",
                        "ce_id" => 2,
                        "remote_ce_id" => 1
                    },
                    "device" => "xr1",
                    "interface" => "GigabitEthernet0/1",
                    "tag" => 300,
                    "bandwidth" => 100,
                    "peer" => [
                        {
                            "peer_id" => 2,
                            "local_asn" => 64600,
                            "local_ip" => "192.168.2.2/31",
                            "peer_asn" => 64602,
                            "peer_ip" => "192.168.2.3/31",
                            "bfd" => 0,
                            "ip_version" => "ipv4"
                        }
                    ]
                }
            ]
        }
    ];
    return ($connections, undef);
}

1;
