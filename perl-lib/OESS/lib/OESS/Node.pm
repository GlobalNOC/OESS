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
        db         => undef,
        logger     => Log::Log4perl->get_logger("OESS.Node"),
        name       => undef,
        node_id    => undef,
        short_name => undef,
        @_
    );

    my $self = \%args;
    bless $self, $class;

    if (defined $self->{db} && (defined $self->{name} || defined $self->{short_name} || defined $self->{node_id})) {
        $self->{model} = OESS::DB::Node::fetch_v2(
            db         => $self->{db},
            name       => $self->{name},
            node_id    => $self->{node_id},
            short_name => $self->{short_name}
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
    $self->{name} = $hash->{name};
    $self->{latitude} = $hash->{latitude};
    $self->{longitude} = $hash->{longitude};
    $self->{vlan_tag_range} = $hash->{vlan_range};
    $self->{operational_state_mpls} = $hash->{operational_state_mpls} || 'up';
    $self->{pending_diff} = $hash->{pending_diff} || 0;
    $self->{admin_state} = $hash->{admin_state} || 'active';
    $self->{short_name} = $hash->{short_name};
    $self->{make} = $hash->{make};
    $self->{model} = $hash->{model};
    $self->{sw_version} = $hash->{sw_version};
    $self->{ip_address} = $hash->{ip_address};
    $self->{loopback_address} = $hash->{loopback_address};
    $self->{tcp_port} = $hash->{tcp_port} || 830;

    return 1;
}

=head2 to_hash

=cut
sub to_hash {
    my $self = shift;
    my $obj = {
        node_id => $self->{'node_id'},
        controller => $self->{'controller'},
        name => $self->{'name'},
        latitude => $self->{'latitude'},
        longitude => $self->{'longitude'},
        vlan_range => $self->{vlan_tag_range},
        operational_state_mpls => $self->{operational_state_mpls},
        pending_diff => $self->{pending_diff},
        admin_state => $self->{admin_state},
        short_name => $self->{short_name},
        make => $self->{make},
        model => $self->{model},
        sw_version => $self->{sw_version},
        ip_address => $self->{ip_address},
        loopback_address => $self->{loopback_address},
        tcp_port => $self->{tcp_port}
    };
    return $obj;
}

=head2 create

    my $err = $node->create;

=cut
sub create {
    my $self = shift;

    if (!defined $self->{db}) {
        return "Couldn't create Node. Database handle is missing.";
    }

    my ($id, $err) = OESS::DB::Node::create(
        db    => $self->{db},
        model => $self->to_hash
    );
    $self->{node_id} = $id;
    return $err;
}

=head2 update

=cut
sub update {
    my $self = shift;
    # If set assume higher lvl abstraction is handling the transaction
    my $in_transaction = shift;

    if (!defined $self->{db}) {
        $self->{'logger'}->error("Could not update Node: No database object specified.");
        return;
    }

    $self->{db}->start_transaction if !defined $in_transaction;
    my $err = OESS::DB::Node::update(
        db => $self->{db},
        node => $self->to_hash
    );
    if (defined $err) {
        $self->{db}->rollback;
        warn "Could not update Node: $err";
        $self->{'logger'}->error("Could not update Node: $err");
        return;
    }
    $self->{db}->commit if !defined $in_transaction;

    return 1;
}

=head2 node_id

=cut
sub node_id {
    my $self = shift;
    return $self->{'node_id'};
}

=head2 interfaces

=cut
sub interfaces {
    my $self = shift;
    my $interfaces = shift;
    
    if(defined($interfaces)){

    }else{
       
        if(!defined($self->{'interfaces'})){
            my $interfaces = OESS::DB::Node::get_node_interfaces(db => $self->{'db'}, node_id => $self->{'node_id'});
            $self->{'interfaces'} = $interfaces;
        }
        
        return $self->{'interfaces'};
    }
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

=head2 pending_diff

=cut
sub pending_diff {
    my $self = shift;
    my $pending_diff = shift;

    if (defined $pending_diff) {
         $self->{pending_diff} = $pending_diff;
    }
    return $self->{pending_diff};
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

=head2 vlan_range

=cut
sub vlan_range {
    my $self = shift;
    my $vlan_tag_range = shift;

    if (defined $vlan_tag_range) {
         $self->{vlan_tag_range} = $vlan_tag_range;
    }
    return $self->{vlan_tag_range};
}

=head2 operational_state_mpls

=cut
sub operational_state_mpls {
    my $self = shift;
    my $operational_state_mpls = shift;

    if (defined $operational_state_mpls) {
         $self->{operational_state_mpls} = $operational_state_mpls;
    }
    return $self->{operational_state_mpls};
}

1;
