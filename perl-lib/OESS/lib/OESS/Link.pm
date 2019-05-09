use strict;
use warnings;

package OESS::Link;

use Data::Dumper;

use OESS::DB::Link;


=head1 OESS::Link

    use OESS::Link;

=cut

=head2 new

    my $link = new OESS::Link(
        db      => $db,
        link_id => 100
    );

    # or

    my $link = new OESS::Link(
        model => {
            link_id        => 12,
            name           => 'node-a-to-node-b',
            remote_urn     => undef,
            status         => 'up',
            metric         => 1,
            interface_a_id => 1,
            ip_a           => '192.168.1.2',
            interface_z_id => 2,
            ip_z           => '192.168.1.3'
        }
    );

=cut
sub new {
    my $that  = shift;
    my $class = ref($that) || $that;

    my $self = {
        db => undef,
        link_id => undef,
        logger => Log::Log4perl->get_logger("OESS.Link"),
        @_
    };
    bless $self, $class;

    if (!defined $self->{db} && !defined $self->{model}) {
        $self->{logger}->error("Couldn't create Link: Arguments `db` and `model` are both missing.");
        return;
    }

    if (defined $self->{db} && defined $self->{link_id}) {
        eval {
            $self->{model} = OESS::DB::Link::fetch(
                db => $self->{db},
                link_id => $self->{link_id}
            );
        };
        if ($@) {
            $self->{logger}->error("Couldn't create Link: $@");
            return;
        }
    }

    if (!defined $self->{model}) {
        $self->{logger}->error("Couldn't create Link.");
        return;
    }
    $self->from_hash($self->{model});

    return $self;
}

=head2 from_hash

=cut
sub from_hash {
    my $self = shift;
    my $hash = shift;

    $self->{link_id} = $hash->{link_id};
    $self->{name} = $hash->{name};
    $self->{remote_urn} = $hash->{remote_urn};
    $self->{status} = $hash->{status};
    $self->{metric} = $hash->{metric};
    $self->{interface_a_id} = $hash->{interface_a_id};
    $self->{ip_a} = $hash->{ip_a};
    $self->{interface_z_id} = $hash->{interface_z_id};
    $self->{ip_z} = $hash->{ip_z};
    return 1;
}

=head2 to_hash

=cut
sub to_hash {
    my $self = shift;

    my $hash = {
        link_id => $self->link_id,
        name => $self->name,
        remote_urn => $self->remote_urn,
        status => $self->status,
        metric => $self->metric,
        interface_a_id => $self->interface_a_id,
        ip_a => $self->ip_a,
        interface_z_id => $self->interface_z_id,
        ip_z => $self->ip_z
    };
    return $hash;
}

=head2 link_id

=cut
sub link_id {
    my $self = shift;
    return $self->{link_id};
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

=head2 remote_urn

=cut
sub remote_urn {
    my $self = shift;
    my $remote_urn = shift;
    if (defined $remote_urn) {
        $self->{remote_urn} = $remote_urn;
    }
    return $self->{remote_urn};
}

=head2 status

=cut
sub status {
    my $self = shift;
    my $status = shift;
    if (defined $status) {
        $self->{status} = $status;
    }
    return $self->{status};
}

=head2 metric

=cut
sub metric {
    my $self = shift;
    my $metric = shift;
    if (defined $metric) {
        $self->{metric} = $metric;
    }
    return $self->{metric};
}

=head2 interface_a_id

=cut
sub interface_a_id {
    my $self = shift;
    my $interface_a_id = shift;
    if (defined $interface_a_id) {
        $self->{interface_a_id} = $interface_a_id;
    }
    return $self->{interface_a_id};
}

=head2 ip_a

=cut
sub ip_a {
    my $self = shift;
    my $ip_a = shift;
    if (defined $ip_a) {
        $self->{ip_a} = $ip_a;
    }
    return $self->{ip_a};
}

=head2 interface_z_id

=cut
sub interface_z_id {
    my $self = shift;
    my $interface_z_id = shift;
    if (defined $interface_z_id) {
        $self->{interface_z_id} = $interface_z_id;
    }
    return $self->{interface_z_id};
}

=head2 ip_z

=cut
sub ip_z {
    my $self = shift;
    my $ip_z = shift;
    if (defined $ip_z) {
        $self->{ip_z} = $ip_z;
    }
    return $self->{ip_z};
}

1;
