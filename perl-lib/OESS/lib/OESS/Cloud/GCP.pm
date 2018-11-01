package OESS::Cloud::GCP;

use strict;
use warnings;

use GRNOC::Log;
use HTML::Entities;
use JSON;
use JSON::WebToken;
use LWP::UserAgent;


sub new {
    my $class = shift;
    my %params = @_;

    my $logger = GRNOC::Log->new(config => "/etc/oess/logging.conf", watch => 5);

    my $self = bless {
        path => $params{path} || '/etc/oess/gapi.conf',
        logger => $logger->get_logger("VCE.Database.Connection"),
        config => undef
    }, $class;

    my $json = do {
        open(my $json_fh, "<:encoding(UTF-8)", $self->{path})
            or die("Can't open \$self->{path}\": $!\n");
        local $/;
        <$json_fh>
    };

    my $coder = JSON->new;
    $self->{config} = $coder->decode($json);

    my $time = time;
    my $jwt = JSON::WebToken->encode(
        {
            iss => $self->{config}->{client_email},
            scope => 'https://www.googleapis.com/auth/compute',
            aud => $self->{config}->{token_uri},
            exp => $time + 3600,
            iat => $time,
            prn => $self->{config}->{client_email}
        },
        $self->{config}->{private_key},
        'RS256',
        { typ => 'JWT' }
    );

    my $ua = LWP::UserAgent->new();
    my $response = $ua->post(
        $self->{config}->{token_uri},
        {
            grant_type => encode_entities('urn:ietf:params:oauth:grant-type:jwt-bearer'),
            assertion => $jwt
        }
    );

    if (!$response->is_success()) {
        $self->{logger}->error($response->content);
    } else {
        my $data = decode_json($response->content);
        $self->{http} = LWP::UserAgent->new();
        $self->{http}->default_header(Authorization => "Bearer $data->{access_token}");
    }

    return $self;
}

sub get_interconnect_attachments {
    my $self = shift;

    my $project = $self->{config}->{project_id};
    my $region = "us-east1";
    my $api_response = $self->{http}->get("https://www.googleapis.com/compute/v1/projects/$project/regions/$region/interconnectAttachments");
    if (!$api_response->is_success) {
        print "Error:\n";
        print "Code was ", $api_response->code, "\n";
        print "Msg: ", $api_response->message, "\n";
        print $api_response->content, "\n";
        die;
    }

    my $api_data = decode_json($api_response->content);
    return $api_data;
}

sub get_interconnects {
    my $self = shift;

    my $project = $self->{config}->{project_id};
    my $api_response = $self->{http}->get("https://www.googleapis.com/compute/v1/projects/$project/global/interconnects");
    if (!$api_response->is_success) {
        print "Error:\n";
        print "Code was ", $api_response->code, "\n";
        print "Msg: ", $api_response->message, "\n";
        print $api_response->content, "\n";
        die;
    }

    my $api_data = decode_json($api_response->content);
    return $api_data;
}

=head2 insert_interconnect_attachment

    my $resp = insert_interconnect_attachment(
        cloud_interconnect_id   => "https://www.googleapis.com/...",
        cloud_interconnect_name => "rtsw.chic.net.internet2.edu - xe-7/0/1",
        bandwidth   => "BPS_50M",
        name        => "GCP L3VPN 1",
        pairing_key => "00000000-0000-0000-0000-000000000000/us-east1/1",
        portal_url  => "https://al2s.net.internet2.edu/...",                 # Optional
        vlan        => 300
    );

insert_interconnect_attachment creates a new GCP interconnect
attachment under project C<$self->{config}->{project_id}> that's
associated with the customers C<pairing_key>.

After a small period of time, the information required to configure a
BGP peering will be available via C<get_interconnect_attachement>.

Once the BGP peering has been configured by OESS and the customer
approves the interconnect attachement created by this method traffic
can be forwarded.

=cut
sub insert_interconnect_attachment {
    my $self = shift;
    my %params = @_;

    my $cloud_interconnect_id   = $params{cloud_interconnect_id};
    my $cloud_interconnect_name = $params{cloud_interconnect_name};
    my $bandwidth   = $params{bandwidth};
    my $name        = $params{name};
    my $pairing_key = $params{pairing_key};
    my $portal_url  = $params{portal_url} || "https://al2s.net.internet2.edu/oess/";
    my $vlan        = $params{vlan};

    my $project = $self->{config}->{project_id};
    my $region = "us-east1"; # TODO Make configurable

    my $payload = {
        name            => $name,
        interconnect    => $cloud_interconnect_id,
        type            => "PARTNER_PROVIDER",
        pairingKey      => $pairing_key,
        vlanTag8021q    => $vlan,
        bandwidth       => $bandwidth,
        partnerAsn      => 55038,
        partnerMetadata => {
            partnerName      => "Internet2",
            interconnectName => $cloud_interconnect_name,
            portalUrl        => $portal_url
        }
    };

    my $req = HTTP::Request->new("POST", "https://www.googleapis.com/compute/v1/projects/$project/regions/$region/interconnectAttachments");
    $req->header("Content-Type" => "application/json");
    $req->content( encode_json($payload) );

    my $api_response = $self->{http}->request($req);
    if (!$api_response->is_success) {
        print "Error:\n";
        print "Code was ", $api_response->code, "\n";
        print "Msg: ", $api_response->message, "\n";
        print $api_response->content, "\n";
        die;
    }

    my $api_data = decode_json($api_response->content);
    return $api_data;
}

return 1;
