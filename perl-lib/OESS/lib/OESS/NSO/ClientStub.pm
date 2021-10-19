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
                    "unit" => 300,
                    "bandwidth" => 200,
                    "peer" => [
                        {
                            "peer_id" => 1,
                            "local_asn" => 64600,
                            "local_ip" => "192.168.3.2/31",
                            "peer_asn" => 64001,
                            "peer_ip" => "192.168.3.3",
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
                    "unit" => 300,
                    "bandwidth" => 100,
                    "peer" => [
                        {
                            "peer_id" => 2,
                            "local_asn" => 64600,
                            "local_ip" => "192.168.2.2/31",
                            "peer_asn" => 64602,
                            "peer_ip" => "192.168.2.3",
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

=head2 get_backbones

    my ($backbones, $err) = get_backbones();

=cut
sub get_backbones {
    my $backbones = [
        {
            "name" => "ALBA-ASHB-00",
            "modified" => {
                "devices" => ["rr0", "rr1"],
                "services" => ["/i2c:internal-services/pdp:sdp-attach[pdp:pdp='ASHB-JJJ-3'][pdp:name='ALBA-ASHB-00']", "/i2c:internal-services/pdp:sdp-attach[pdp:pdp='ALBA-JJJ-3'][pdp:name='ALBA-ASHB-00']", "/ncs:services/pdp:pdp[pdp:name='ASHB-JJJ-3']", "/ncs:services/pdp:pdp[pdp:name='ALBA-JJJ-3']"]
            },
            "directly-modified" => {
                "devices" => ["rr0", "rr1"],
                "services" => ["/ncs:services/pdp:pdp[pdp:name='ALBA-JJJ-3']", "/ncs:services/pdp:pdp[pdp:name='ASHB-JJJ-3']", "/i2c:internal-services/pdp:sdp-attach[pdp:pdp='ALBA-JJJ-3'][pdp:name='ALBA-ASHB-00']", "/i2c:internal-services/pdp:sdp-attach[pdp:pdp='ASHB-JJJ-3'][pdp:name='ALBA-ASHB-00']"]
            },
            "device-list" => ["rr0", "rr1"],
            "pdp" => [
                {
                    "name" => "ALBA-JJJ-3"
                },
                {
                    "name" => "ASHB-JJJ-3"
                }
            ],
            "metric-override" => 1,
            "admin-state" => "in-service",
            "summary" => {
                "circuit-id" => "",
                "endpoint" => [
                    {
                        "pdp" => "ALBA-JJJ-3",
                        "device" => "rr0",
                        "if-full" => "HundredGigE3/1",
                        "ipv4-address" => "192.0.2.2/31",
                        "ipv6-address" => "2001:db8::2/127"
                    },
                    {
                        "pdp" => "ASHB-JJJ-3",
                        "device" => "rr1",
                        "if-full" => "HundredGigE3/1",
                        "ipv4-address" => "192.0.2.3/31",
                        "ipv6-address" => "2001:db8::3/127"
                    }
                ]
            },
            "vars" => {
                "ipv4-prefix" => "192.0.2.2/31",
                "ipv6-prefix" => "2001:db8::2/127",
                "metric" => 1,
                "endpoint" => [
                    {
                        "pdp" => "ALBA-JJJ-3",
                        "ipv4-address" => "192.0.2.2/31",
                        "ipv6-address" => "2001:db8::2/127",
                        "if-full" => "HundredGigE3/1"
                    },
                    {
                        "pdp" => "ASHB-JJJ-3",
                        "ipv4-address" => "192.0.2.3/31",
                        "ipv6-address" => "2001:db8::3/127",
                        "if-full" => "HundredGigE3/1"
                    }
                ],
                "sdp-description" => "BACKBONE: RR0-RR1"
            }
        },
        {
            "name" => "CHIC-EQCH-00",
            "modified" => {
                "devices" => ["xr0", "xr1"],
                "services" => ["/i2c:internal-services/pdp:sdp-attach[pdp:pdp='EQCH-JJJ-2'][pdp:name='CHIC-EQCH-00']", "/i2c:internal-services/pdp:sdp-attach[pdp:pdp='CHIC-JJJ-2'][pdp:name='CHIC-EQCH-00']", "/ncs:services/pdp:pdp[pdp:name='EQCH-JJJ-2']", "/ncs:services/pdp:pdp[pdp:name='CHIC-JJJ-2']"]
            },
            "directly-modified" => {
                "devices" => ["xr0", "xr1"],
                "services" => ["/ncs:services/pdp:pdp[pdp:name='CHIC-JJJ-2']", "/ncs:services/pdp:pdp[pdp:name='EQCH-JJJ-2']", "/i2c:internal-services/pdp:sdp-attach[pdp:pdp='CHIC-JJJ-2'][pdp:name='CHIC-EQCH-00']", "/i2c:internal-services/pdp:sdp-attach[pdp:pdp='EQCH-JJJ-2'][pdp:name='CHIC-EQCH-00']"]
            },
            "device-list" => ["xr0", "xr1"],
            "pdp" => [
                {
                    "name" => "CHIC-JJJ-2"
                },
                {
                    "name" => "EQCH-JJJ-2"
                }
            ],
            "admin-state" => "in-service",
            "summary" => {
                "circuit-id" => "",
                "endpoint" => [
                    {
                        "pdp" => "CHIC-JJJ-2",
                        "device" => "xr0",
                        "if-full" => "HundredGigE3/0",
                        "ipv4-address" => "192.0.2.0/31",
                        "ipv6-address" => "2001:db8::/127"
                    },
                    {
                        "pdp" => "EQCH-JJJ-2",
                        "device" => "xr1",
                        "if-full" => "HundredGigE3/0",
                        "ipv4-address" => "192.0.2.1/31",
                        "ipv6-address" => "2001:db8::1/127"
                    }
                ]
            },
            "vars" => {
                "ipv4-prefix" => "192.0.2.0/31",
                "ipv6-prefix" => "2001:db8::/127",
                "metric" => 20,
                "srlg-name" => ["SRLG06"],
                "endpoint" => [
                    {
                        "pdp" => "CHIC-JJJ-2",
                        "ipv4-address" => "192.0.2.0/31",
                        "ipv6-address" => "2001:db8::/127",
                        "if-full" => "HundredGigE3/0"
                    },
                    {
                        "pdp" => "EQCH-JJJ-2",
                        "ipv4-address" => "192.0.2.1/31",
                        "ipv6-address" => "2001:db8::1/127",
                        "if-full" => "HundredGigE3/0"
                    }
                ],
                "sdp-description" => "BACKBONE: XR0-XR1"
            }
        }
    ];
    return ($backbones, undef);
}

=head2 get_platform

=cut
sub get_platform {
    my $self = shift;
    my $node = shift;
    my $sub  = shift;

    my $result = {
        'serial-number' => 'FOC22311UU1',
        'version' => '7.2.2',
        'model' => 'NCS-5500',
        'name' => 'ios-xr'
    };
    &$sub($result, undef);
}

1;
