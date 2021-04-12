package OESS::Node;

use strict;
use warnings;

use OESS::DB::Node;


=head2 new

=cut
sub new {
    my $that  = shift;
    my $class = ref($that) || $that;

    my %args = (
        node_id => undef,
        db      => undef,
        model   => undef,
        logger  => Log::Log4perl->get_logger("OESS.Node"),
        @_
    );

    my $self = \%args;
    bless $self, $class;

    if (defined $self->{db} && defined $self->{node_id}) {
        $self->{model} = OESS::DB::Node::fetch(
            db      => $self->{db},
            node_id => $self->{node_id}
        );
    }
    return if !defined $self->{model};

    $self->from_hash($self->{model});
    return $self;
}

=head2 from_hash

=cut
sub from_hash {
    my $self = shift;
    my $hash = shift;

    $self->{node_id} = $hash->{node_id};
    $self->{controller} = $hash->{controller};
    $self->{ip_address} = $hash->{ip_address};
    $self->{latitude} = $hash->{latitude};
    $self->{longitude} = $hash->{longitude};
    $self->{loopback_address} = $hash->{loopback_address};
    $self->{make} = $hash->{make};
    $self->{model} = $hash->{model};
    $self->{name} = $hash->{name};
    $self->{short_name} = $hash->{short_name};
    $self->{sw_version} = $hash->{sw_version};
    $self->{vlan_range} = $hash->{vlan_range};
    return 1;
}

=head2 to_hash

=cut
sub to_hash {
    my $self = shift;
    my $obj = {
        node_id          => $self->{node_id},
        controller       => $self->{controller},
        ip_address       => $self->{ip_address},
        latitude         => $self->{latitude},
        longitude        => $self->{longitude},
        loopback_address => $self->{loopback_address},
        make             => $self->{make},
        model            => $self->{model},
        name             => $self->{name},
        short_name       => $self->{short_name},
        sw_version       => $self->{sw_version},
        tcp_port         => $self->{tcp_port},
        vlan_range       => $self->{vlan_range}
    };
    return $obj;
}

=head2 create

    my $err = $node->create;

=cut
sub create {
    my $self = shift;

    if (!defined $self->{db}) {
        return (undef, "Couldn't create Node. Database handle is missing.");
    }

    my ($id, $err) = OESS::DB::Node::create(
        db    => $self->{db},
        model => $self->to_hash
    );
    $self->{node_id} = $id;
    return $err;
}

=head2 node_id

=cut
sub node_id {
    my $self = shift;
    return $self->{'node_id'};
}

=head2 controller

=cut
sub controller {
    my $self = shift;
    my $controller = shift;
    if (defined $controller) {
        $self->{controller} = $controller;
    }
    return $self->{controller};
}

=head2 ip_address

=cut
sub ip_address {
    my $self = shift;
    my $ip_address = shift;
    if (defined $ip_address) {
        $self->{ip_address} = $ip_address;
    }
    return $self->{ip_address};
}

=head2 latitude

=cut
sub latitude {
    my $self = shift;
    my $latitude = shift;
    if (defined $latitude) {
        $self->{latitude} = $latitude;
    }
    return $self->{latitude};
}

=head2 longitude

=cut
sub longitude {
    my $self = shift;
    my $longitude = shift;
    if (defined $longitude) {
        $self->{longitude} = $longitude;
    }
    return $self->{longitude};
}

=head2 loopback_address

=cut
sub loopback_address {
    my $self = shift;
    my $loopback_address = shift;
    if (defined $loopback_address) {
        $self->{loopback_address} = $loopback_address;
    }
    return $self->{loopback_address};
}

=head2 make

=cut
sub make {
    my $self = shift;
    my $make = shift;
    if (defined $make) {
        $self->{make} = $make;
    }
    return $self->{make};
}

=head2 model

=cut
sub model {
    my $self = shift;
    my $model = shift;
    if (defined $model) {
        $self->{model} = $model;
    }
    return $self->{model};
}

=head2 name

=cut
sub name {
    my $self = shift;
    my $name = shift;
    if (defined $name) {
        $self->{name} = $name;
    }
    return $self->{name};
}

=head2 short_name

=cut
sub short_name {
    my $self = shift;
    my $short_name = shift;
    if (defined $short_name) {
        $self->{short_name} = $short_name;
    }
    return $self->{short_name};
}

=head2 sw_version

=cut
sub sw_version {
    my $self = shift;
    my $sw_version = shift;
    if (defined $sw_version) {
        $self->{sw_version} = $sw_version;
    }
    return $self->{sw_version};
}

=head2 tcp_port

=cut
sub tcp_port {
    my $self = shift;
    my $tcp_port = shift;
    if (defined $tcp_port) {
        $self->{tcp_port} = $tcp_port;
    }
    return $self->{tcp_port};
}

=head2 vlan_range

=cut
sub vlan_range {
    my $self = shift;
    my $vlan_range = shift;
    if (defined $vlan_range) {
        $self->{vlan_range} = $vlan_range;
    }
    return $self->{vlan_range};
}

=head2 interfaces

=cut
sub interfaces {
    my $self = shift;
    my $interfaces = shift;
    
    if(defined($interfaces)){

    }else{
       
        if(!defined($self->{'interfaces'})){
            my $interfaces = OESS::DB::Node::get_interfaces(db => $self->{'db'}, node_id => $self->{'node_id'});
            $self->{'interfaces'} = $interfaces;
        }
        
        return $self->{'interfaces'};
    }
}

return 1;
