package OESS::Cloud::Oracle;

use strict;
use warnings;

use Crypt::OpenSSL::RSA;
use Data::Dumper;
use Digest::SHA qw(sha256_base64);
use HTTP::Date;
use HTTP::Request;
use JSON::XS;
use Log::Log4perl;
use LWP::UserAgent;
use MIME::Base64;
use OESS::Config;


=head1 OESS::Cloud::Oracle

    use OESS::Cloud::Oracle

=cut


=head2 new

    my $oracle = new OESS::Cloud::Oracle();

=cut
sub new {
    my $class = shift;
    my $args  = {
        config => "/etc/oess/database.xml",
        logger => Log::Log4perl->get_logger("OESS.Cloud.Oracle"),
        @_
    };
    my $self = bless $args, $class;

    if (!defined $self->{config_obj}) {
        $self->{config_obj} = new OESS::Config(config_filename => $self->{config});
    }

    # We intercept and sign every request sent using $self->{conn} via the
    # request_send handler. https://metacpan.org/pod/LWP::UserAgent#add_handler
    #
    # TODO Create a conn per interconnect. This probably isn't required, but
    # it should be done to be consistant with how we handled auth for the
    # other cloud providers.
    $self->{conn} = LWP::UserAgent->new();
    $self->{conn}->add_handler(request_send => sub {
        my($request, $ua, $handler) = @_;

        my $signing_headers = join(" ", @{$self->_get_signing_headers($request)});
        my $signature = $self->_compute_signature($request);

        my $config = $self->{config_obj}->oracle()->{CrossConnect1};
        my $key_id = "$config->{tenancy}/$config->{user}/$config->{fingerprint}";

        my $header = "Signature version=\"1\",headers=\"$signing_headers\",keyId=\"$key_id\",algorithm=\"rsa-sha256\",signature=\"$signature\"";

        $request->header('Content-Type' => 'application/json; charset=UTF-8');
        $request->header(Authorization => $header);

        return;
    });

    return $self;
}

=head2 _get_signing_headers

Returns list of headers for the HTTP method defined under Required Headers at
https://docs.oracle.com/en-us/iaas/Content/API/Concepts/signingrequests.htm

=cut
sub _get_signing_headers {
    my $self = shift;
    my $req  = shift;

    # Ref: https://github.com/oracle/oci-go-sdk/blob/master/common/http_signer.go#L46-L52
    if ($req->{_method} eq 'POST' || $req->{_method} eq 'PUT' || $req->{_method} eq 'PATCH') {
        return ["date", "(request-target)", "host", "content-length", "content-type", "x-content-sha256"];
    } else {
        return ["date", "(request-target)", "host"];
    }
}

=head2 _get_signing_string

Returns string to sign composed of headers defined under Required Headers at
https://docs.oracle.com/en-us/iaas/Content/API/Concepts/signingrequests.htm

    date: Wed, 27 Apr 2022 16:10:45 GMT\n(request-target): get /20160918/virtualCircuits?key=value\nhost: iaas.us-ashburn-1.oraclecloud.com

=cut
sub _get_signing_string {
    my $self = shift;
    my $req  = shift;

    my $signing_headers = $self->_get_signing_headers($req);
    my $signing_parts = [];

    foreach my $part (@$signing_headers) {
        my $value;
        if ($part eq '(request-target)') {
            my $method = lc($req->{_method});
            $req->uri =~ m/\.com(.*)/;
            $value = "$method $1"; # Ex: get /20160918/virtualCircuits
        }
        elsif ($part eq 'host') {
            $value = 'iaas.us-ashburn-1.oraclecloud.com';
        }
        elsif ($part eq 'date') {
            $value = time2str(time);
            $req->header(date => $value); # Must be in request headers
        }
        elsif ($part eq 'content-type') {
            $value = 'application/json';
            $req->header('content-type' => $value);
        }
        elsif ($part eq 'content-length') {
            $value = length($req->content);
            $req->header('content-length' => $value);
        }
        elsif ($part eq 'x-content-sha256') {
            $value = sha256_base64($req->content);
            # Add required padding
            # https://perldoc.perl.org/Digest::SHA#PADDING-OF-BASE64-DIGESTS
            while (length($value) % 4) {
                $value .= '=';
            }
            $req->header('x-content-sha256' => $value);
        }
        else {
            $value = $req->header($part);
        }
        push @$signing_parts, "$part: $value";
    }
    my $signing_string = join('\n', @$signing_parts);

    return $signing_string;
}

=head2 _compute_signature

=cut
sub _compute_signature {
    my $self = shift;
    my $req  = shift;

    my $signing_string = $self->_get_signing_string($req);

    # This method doesn't work, but I don't know why.
    #
    # my $filename = '/etc/oess/oracle_rsa';
    # open my $fh, '<', $filename or die "error opening $filename: $!";
    # my $key = do { local $/; <$fh> };
    
    # my $rsa = Crypt::OpenSSL::RSA->new_private_key($key);
    # $rsa->use_sha256_hash;
    # my $signature = $rsa->sign($signing_string);
    # return encode_base64($signature);

    return `printf '%b' "$signing_string" | openssl dgst -sha256 -sign /etc/oess/oracle_rsa | openssl enc -e -base64 | tr -d '\n'`;
}

=head2 get_virtual_circuit

    my ($virtual_circuit, $err) = $oracle->get_virtual_circuit($virtual_circuit_id);
    die $err if defined $err;

Returns

    {
        "id" =>  "UniqueVirtualCircuitId123",
        "displayName" => "ProviderTestVirtualCircuit",
        "providerName" => "AlexanderGrahamBell",
        "providerServiceName" => "Layer2 Service",
        "providerServiceId" => "ocid1.providerservice.oc1.eu-frankfurt-1.abcd",
        "serviceType" => "LAYER2",
        "bgpManagement" => "CUSTOMER_MANAGED",
        "bandwidthShapeName" => "5Gbps",
        "oracleBgpAsn" => "561",
        "customerBgpAsn" => "1234",
        "crossConnectMappings" => [{
            "oracleBgpPeeringIp" => "10.0.0.19/31",
            "customerBgpPeeringIp" => "10.0.0.18/31",
        }],
        "lifecycleState" => "PENDING_PROVIDER",
        "providerState" => "INACTIVE",
        "bgpSessionState" => "DOWN",
        "region" => "IAD"
    }

=cut
sub get_virtual_circuit {
    my $self = shift;
    my $virtual_circuit_id = shift;

    my $req = new HTTP::Request(GET => "https://iaas.us-ashburn-1.oraclecloud.com/20160918/virtualCircuits/$virtual_circuit_id");
    my $res = $self->{conn}->request($req);
    if ($res->code < 200 || $res->code > 299) {
        my $code  = $res->code;
        my $error = decode_json($res->content);
        return (undef, "[$code] $error->{code}: $error->{message}");
    }

    my $results = decode_json($res->content);
    return ($results, undef);
}

=head2 get_virtual_circuits

    my ($virtual_circuits, $err) = $oracle->get_virtual_circuits();
    die $err if defined $err;

Returns:

    [
        {
            "id" =>  "UniqueVirtualCircuitId123",
            "displayName" => "ProviderTestVirtualCircuit",
            "providerName" => "AlexanderGrahamBell",
            "providerServiceName" => "Layer2 Service",
            "providerServiceId" => "ocid1.providerservice.oc1.eu-frankfurt-1.abcd",
            "serviceType" => "LAYER2",
            "bgpManagement" => "CUSTOMER_MANAGED",
            "bandwidthShapeName" => "5Gbps",
            "oracleBgpAsn" => "561",
            "customerBgpAsn" => "1234",
            "crossConnectMappings" => [{
                "oracleBgpPeeringIp" => "10.0.0.19/31",
                "customerBgpPeeringIp" => "10.0.0.18/31",
            }],
            "lifecycleState" => "PENDING_PROVIDER",
            "providerState" => "INACTIVE",
            "bgpSessionState" => "DOWN",
            "region" => "IAD"
        }
    ]

=cut
sub get_virtual_circuits {
    my $self = shift;

    my $req = new HTTP::Request(GET => "https://iaas.us-ashburn-1.oraclecloud.com/20160918/virtualCircuits?compartmentId=ocid1.compartment.oc1..aaaaaaaamw3ulplxrs5rb6uwzx33grbvf7kitprgyclrfejpepm43k2zuiaa");
    my $res = $self->{conn}->request($req);
    if ($res->code < 200 || $res->code > 299) {
        my $code  = $res->code;
        my $error = decode_json($res->content);
        return (undef, "[$code] $error->{code}: $error->{message}");
    }

    my $results = decode_json($res->content);
    return ($results, undef);
}

=head2 update_virtual_circuit

    my ($virtual_circuit, $err) = $oracle->get_virtual_circuit(
        ocid      => undef, # Oracle Cloud Identifier
        name      => '',    # User-friendly name. Not unique. Changeable. No confidential info.
        type      => 'l2',  # l2 or l3
        bandwidth => 50,    # Converted from int to something like 2Gbps
        auth_key  => '',    # Empty or Null disables BGP Auth
        mtu       => 1500,  # Coverted from int to MTU_1500 or MTU_9000
        oess_asn  => undef,
        oess_ip   => undef, # /31
        peer_ip   => undef, # /31
        oess_ipv6 => undef, # /127
        peer_ipv6 => undef, # /127
        vlan      => undef,
    );
    die $err if defined $err;

Returns:

    {
        "id" =>  "UniqueVirtualCircuitId123",
        "displayName" => "ProviderTestVirtualCircuit",
        "providerName" => "AlexanderGrahamBell",
        "providerServiceName" => "Layer2 Service",
        "providerServiceId" => "ocid1.providerservice.oc1.eu-frankfurt-1.abcd",
        "serviceType" => "LAYER2",
        "bgpManagement" => "CUSTOMER_MANAGED",
        "bandwidthShapeName" => "5Gbps",
        "oracleBgpAsn" => "561",
        "customerBgpAsn" => "1234",
        "crossConnectMappings" => [{
            "oracleBgpPeeringIp" => "10.0.0.19/31",
            "customerBgpPeeringIp" => "10.0.0.18/31",
        }],
        "lifecycleState" => "PENDING_PROVIDER",
        "providerState" => "INACTIVE",
        "bgpSessionState" => "DOWN",
        "region" => "IAD"
    }

=cut
sub update_virtual_circuit {
    my $self = shift;
    my $args = {
        ocid      => undef, # Oracle Cloud Identifier
        name      => '',    # User-friendly name. Not unique. Changeable. No confidential info.
        type      => 'l2',  # l2 or l3
        bandwidth => 50,    # Converted from int to something like 2Gbps
        auth_key  => '',    # Empty or Null disables BGP Auth
        mtu       => 1500,  # Coverted from int to MTU_1500 or MTU_9000
        oess_asn  => undef,
        oess_ip   => undef, # /31
        peer_ip   => undef, # /31
        oess_ipv6 => undef, # /127
        peer_ipv6 => undef, # /127
        vlan      => undef,
        @_
    };

    my $bandwidth;
    my $mtu;

    # TODO bandwidth and mtu must be converted to the proper ENUMs
    $bandwidth = $args->{bandwidth};
    $mtu = ($args->{mtu} == 1500) ? 'MTU_1500' : 'MTU_9000';

    my $l2_payload = {
        crossConnectMappings => [
            {
                crossConnectOrCrossConnectGroupId => $args->{ocid},
                vlan => $args->{vlan},
            }
        ],
        providerState => 'ACTIVE',
        bandwidthShapeName => $bandwidth,
        displayName => $args->{name} 
    };

    my $l3_payload = {
        crossConnectMappings => [
            {
                bgpMd5AuthKey => $args->{auth_key},
                crossConnectOrCrossConnectGroupId => $args->{ocid},
                customerBgpPeeringIp => $args->{oess_ip},
                oracleBgpPeeringIp => $args->{peer_ip},
                customerBgpPeeringIpv6 => $args->{oess_ipv6},
                oracleBgpPeeringIpv6 => $args->{peer_ipv6},
                vlan => $args->{vlan},
            }
        ],
        providerState => 'ACTIVE',
        bandwidthShapeName => $bandwidth,
        customerBgpAsn => $args->{oess_asn},
        displayName => $args->{name}, # A user-friendly name. Not unique and changeable. Avoid confidential information.
        ipMtu => $mtu
    };


    my $req = new HTTP::Request(PUT => "https://iaas.us-ashburn-1.oraclecloud.com/20160918/virtualCircuits/$args->{ocid}");
    my $payload = ($args->{type} eq 'l2') ? $l2_payload : $l3_payload;
    $req->content(encode_json($payload));

    my $res = $self->{conn}->request($req);
    if ($res->code < 200 || $res->code > 299) {
        my $code  = $res->code;
        my $error = decode_json($res->content);
        return (undef, "[$code] $error->{code}: $error->{message}");
    }
    my $results = decode_json($res->content);

    return ($results, undef);
}

=head2 delete_virtual_circuit

    my ($virtual_circuit, $err) = $oracle->get_virtual_circuit($virtual_circuit_id);
    die $err if defined $err;

Returns:

    {
        "id" =>  "UniqueVirtualCircuitId456",
        "displayName" => "ProviderTestVirtualCircuit",
        "providerName" => "AlexanderGrahamBell",
        "providerServiceName" => "Layer2 Service",
        "providerServiceId" => "ocid1.providerservice.oc1.eu-frankfurt-1.abcd",
        "serviceType" => "LAYER3",
        "bgpManagement" => "PROVIDER_MANAGED",
        "bandwidthShapeName" => "5Gbps",
        "oracleBgpAsn" => "561",
        "customerBgpAsn" => "1234",
        "crossConnectMappings" => [{
            "crossConnectOrCrossConnectGroupId" => "CrossConnect1",
            "vlan" => 1234,
            "oracleBgpPeeringIp" => "10.0.0.19/31",
            "customerBgpPeeringIp" => "10.0.0.18/31",
        }],
        "lifecycleState" => "TERMINATING",
        "providerState" => "ACTIVE",
        "bgpSessionState" => "UP",
        "region" => "IAD",
        "type" => "PRIVATE"
    }

=cut
sub delete_virtual_circuit {
    my $self = shift;
    my $virtual_circuit_id = shift;

    my $req = new HTTP::Request(GET => "https://iaas.us-ashburn-1.oraclecloud.com/20160918/virtualCircuits/$virtual_circuit_id");
    my $res = $self->{conn}->request($req);
    if ($res->code < 200 || $res->code > 299) {
        my $code  = $res->code;
        my $error = decode_json($res->content);
        return (undef, "[$code] $error->{code}: $error->{message}");
    }
    my $results = decode_json($res->content);

    $req = new HTTP::Request(DELETE => "https://iaas.us-ashburn-1.oraclecloud.com/20160918/virtualCircuits/$virtual_circuit_id");
    $res = $self->{conn}->request($req);
    if ($res->code < 200 || $res->code > 299) {
        my $code  = $res->code;
        my $error = decode_json($res->content);
        return (undef, "[$code] $error->{code}: $error->{message}");
    }

    return ($results, undef);
}

return 1;
