package OESS::NSO::ConnectionCache;

=head1 OESS::NSO::ConnectionCache

An in memory connection cache:

    {
        "node-id-1": {
            "conn-id-1": { "eps" : [ "node-id-1", "node-id-2" ] }
        },
        "node-id-2": {
            "conn-id-1": { "eps" : [ "node-id-1", "node-id-2" ] }
        }
    }

This implies that a connection is stored under each node. This allows us to
query all connections associated with a single node. Additionally this helps us
track large changes that may effect multiple connections on a single node.

=cut

=head2 new

=cut
sub new {
    my $class = shift;
    my $args  = { @_ };
    my $self  = bless $args, $class;

    $self->{cache}         = {};
    $self->{l3_cache}      = {};
    $self->{flat_cache}    = {};
    $self->{l3_flat_cache} = {};

    return $self;
}

sub get_included_nodes {
    my $self = shift;

    my $id_index = {};
    foreach my $node_id (keys %{$self->{cache}}) {
        $id_index->{$node_id} = 1;
    }
    foreach my $node_id (keys %{$self->{l3_cache}}) {
        $id_index->{$node_id} = 1;
    }

    my @ids = keys %{$id_index};
    return \@ids;
}

sub get_connections_by_node {
    my $self = shift;
    my $node_id = shift;
    my $type = shift;

    my $cache = 'cache';
    my $flat_cache = 'flat_cache';
    if ($type eq 'l3') {
        $cache = 'l3_cache';
        $flat_cache = 'l3_flat_cache';
    }

    my $result = [];
    foreach my $conn_id (keys %{$self->{$cache}->{$node_id}}) {
        push @$result, $self->{$cache}->{$node_id}->{$conn_id};
    }
    return $result;
};

sub add_connection {
    my $self = shift;
    my $conn = shift;
    my $type = shift;

    my $cache = 'cache';
    my $conn_id = undef;
    my $flat_cache = 'flat_cache';
    if ($type eq 'l3') {
        $cache = 'l3_cache';
        $conn_id = $conn->vrf_id;
        $flat_cache = 'l3_flat_cache';
    } else {
        $conn_id = $conn->circuit_id;
    }

    # Handle case where connection has no endpoints or a connection
    # created with an empty model.
    my $endpoints = $conn->endpoints || [];

    foreach my $ep (@{$endpoints}) {
        if (!defined $self->{$cache}->{$ep->node_id}) {
            $self->{$cache}->{$ep->node_id} = {};
        }
        $self->{$cache}->{$ep->node_id}->{$conn_id} = $conn;
    }
    $self->{$flat_cache}->{$conn_id} = $conn;

    return 1;
}

sub remove_connection {
    my $self = shift;
    my $conn = shift;
    my $type = shift;

    my $cache = 'cache';
    my $conn_id = undef;
    my $flat_cache = 'flat_cache';
    if ($type eq 'l3') {
        $cache = 'l3_cache';
        $conn_id = $conn->vrf_id;
        $flat_cache = 'l3_flat_cache';
    } else {
        $conn_id = $conn->circuit_id;
    }

    foreach my $ep (@{$conn->endpoints}) {
        if (!defined $self->{$cache}->{$ep->node_id}) {
            next;
        }
        delete $self->{$cache}->{$ep->node_id}->{$conn_id};
    }
    delete $self->{$flat_cache}->{$conn_id};

    return 1;
}

return 1;
