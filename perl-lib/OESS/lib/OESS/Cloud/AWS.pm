package OESS::Cloud::AWS;

use strict;
use warnings;

use Data::Dumper;
use Log::Log4perl;
use Paws;
use XML::Simple;

sub new {
    my $class = shift;
    my $self  = {
        config => '/etc/oess/database.xml',
        logger => Log::Log4perl->get_logger('OESS.Cloud.AWS'),
        connection_region => 'us-east-2',
        vinterface_region => 'us-east-1',
        connection_interconnect => 'dxcon-ffnl10q5',
        vinterface_interconnect => 'dxcon-fgm77851',
        @_
    };
    bless $self, $class;

    $self->{creds} = XML::Simple::XMLin($self->{config});

    return $self;
}

=head2 allocate_connection
=cut
sub allocate_connection {
    my $self = shift;
    my $connection_name = shift;
    my $owner_account = shift;
    my $tag = shift;
    my $bandwidth = shift;

    $ENV{'AWS_ACCESS_KEY'} = $self->{creds}->{aws}->{conn_access_key};
    $ENV{'AWS_SECRET_KEY'} = $self->{creds}->{aws}->{conn_secret_key};

    my $dc = Paws->service(
        'DirectConnect',
        region => $self->{connection_region}
    );
    my $resp = $dc->AllocateHostedConnection(
        Bandwidth => $bandwidth,
        ConnectionId => $self->{connection_interconnect},
        ConnectionName => $connection_name,
        OwnerAccount => $owner_account,
        Vlan => $tag
    );

    # TODO: Find failure modes and log as error
    warn Dumper($resp);

    $self->{logger}->info("Allocated AWS Connection $resp->{ConnectionId} on $self->{connection_region} for $resp->{OwnerAccount} with VLAN $resp->{Vlan}.");
    return $resp;
}

=head2 delete_connection
=cut
sub delete_connection {
    my $self = shift;
    my $connection_id = shift;

    $ENV{'AWS_ACCESS_KEY'} = $self->{creds}->{aws}->{conn_access_key};
    $ENV{'AWS_SECRET_KEY'} = $self->{creds}->{aws}->{conn_secret_key};

    my $dc = Paws->service(
        'DirectConnect',
        region => $self->{connection_region}
    );
    my $resp = $dc->DeleteConnection(
        ConnectionId => $connection_id
    );

    warn Dumper($resp);

    $self->{logger}->info("Removed AWS Connection $resp->{ConnectionId} on $self->{connection_region} for $resp->{OwnerAccount} with VLAN $resp->{Vlan}.");
    return $resp;
}

=head2 allocate_vinterface
=cut
sub allocate_vinterface {
    my $self = shift;
    my $owner_account = shift;
    my $addr_family = shift;
    my $amazon_addr = shift;
    my $asn = shift;
    my $auth_key = shift;
    my $customer_addr = shift;
    my $vinterface_name = shift;
    my $tag = shift;

    $ENV{'AWS_ACCESS_KEY'} = $self->{creds}->{aws}->{vint_access_key};
    $ENV{'AWS_SECRET_KEY'} = $self->{creds}->{aws}->{vint_secret_key};

    my $dc = Paws->service(
        'DirectConnect',
        region => $self->{vinterface_region}
    );
    my $resp = $dc->AllocatePrivateVirtualInterface(
        ConnectionId => $self->{vinterface_interconnect},
        OwnerAccount => $owner_account,
        NewPrivateVirtualInterfaceAllocation => {
            AddressFamily => $addr_family,
            AmazonAddress => $amazon_addr,
            Asn => $asn,
            AuthKey => $auth_key,
            CustomerAddress => $customer_addr,
            VirtualInterfaceName => $vinterface_name,
            Vlan => $tag
        }
    );

    # TODO: Find failure modes and log as error
    warn Dumper($resp);

    $self->{logger}->info("Allocated AWS Virtual Interface $resp->{ConnectionId} on $self->{vinterface_region} for $resp->{OwnerAccount} with VLAN $resp->{Vlan}.");
    return $resp;
}

=head2 delete_vinterface
=cut
sub delete_vinterface {
    my $self = shift;
    my $vinterface_id = shift;

    $ENV{'AWS_ACCESS_KEY'} = $self->{creds}->{aws}->{vint_access_key};
    $ENV{'AWS_SECRET_KEY'} = $self->{creds}->{aws}->{vint_secret_key};

    my $dc = Paws->service(
        'DirectConnect',
        region => $self->{vinterface_region}
    );
    my $resp = $dc->DeleteVirtualInterface(
        VirtualInterfaceId => $vinterface_id
    );

    warn Dumper($resp);

    $self->{logger}->info("Removed AWS Virtual Interface $resp->{ConnectionId} on $self->{vinterface_region} for $resp->{OwnerAccount} with VLAN $resp->{Vlan}.");
    return $resp;
}

1;
