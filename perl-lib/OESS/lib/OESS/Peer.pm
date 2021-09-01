use strict;
use warnings;

package OESS::Peer;

use Data::Dumper;

use OESS::DB::Peer;


=head1 OESS::Peer

    use OESS::Peer;

=cut

=head2 new

    my $peer = new OESS::Peer(
        db             => $db,
        vrf_ep_peer_id => 100
    );

    # or

    my $peer = new OESS::Peer(
        model => {
            circuit_ep_id => 7,                # Optional
            vrf_ep_id     => 7,                # Optional
            local_ip      => '192.168.1.2/31',
            peer_asn      => 1200
            peer_ip       => '192.168.1.3/31',
            md5_key       => undef,
            status        => 'up',             # Actually operational_state
            bfd           => 0
        }
    );

=cut
sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $self = {
        vrf_ep_peer_id => undef,
        db          => undef,
        model       => undef,
        logger      => Log::Log4perl->get_logger("OESS.Peer"),
        @_
    };

    bless $self, $class;

    if (defined $self->{db} && defined $self->{vrf_ep_peer_id} && $self->{vrf_ep_peer_id} != -1) {
        $self->{model} = OESS::DB::VRF::fetch_peer(
            db => $self->{db},
            vrf_ep_peer_id => $self->{vrf_ep_peer_id}
        );
    }

    if (!defined $self->{model}) {
        $self->{logger}->error("Couldn't load peer from model or database.");
        return;
    }

    $self->from_hash($self->{model});
    return $self;
}

=head2 from_hash

=cut
sub from_hash{
    my $self = shift;
    my $hash = shift;

    $self->{'vrf_ep_peer_id'} = $hash->{'vrf_ep_peer_id'};
    $self->{'peer_ip'} = $hash->{'peer_ip'};
    $self->{'peer_asn'} = $hash->{'peer_asn'};
    $self->{'vrf_ep_id'} = $hash->{'vrf_ep_id'};
    $self->{'md5_key'} = (!defined $hash->{'md5_key'}) ? '' : $hash->{'md5_key'};
    $self->{'local_ip'} = $hash->{'local_ip'};

    if (!defined $hash->{'ip_version'}) {
        if ($self->{'local_ip'} =~ /^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/([0-9]|[1-2][0-9]|3[0-2]))$/) {
            $hash->{'ip_version'} = 'ipv4';
        } else {
            $hash->{'ip_version'} = 'ipv6';
        }
    }
    $self->{'ip_version'} = $hash->{'ip_version'};

    $self->{'operational_state'} = $hash->{'operational_state'};
    $self->{'bfd'} = $hash->{'bfd'};
}

=head2 to_hash

=cut
sub to_hash{
    my $self = shift;

    my $obj;
    $obj->{'vrf_ep_peer_id'} = $self->{'vrf_ep_peer_id'};
    $obj->{'peer_ip'} = $self->{'peer_ip'};
    $obj->{'peer_asn'} = $self->{'peer_asn'};
    $obj->{'vrf_ep_id'} = $self->{'vrf_ep_id'};
    $obj->{'md5_key'} = $self->{'md5_key'};
    $obj->{'local_ip'} = $self->{'local_ip'};
    $obj->{'ip_version'} = $self->{'ip_version'};
    $obj->{'operational_state'} = $self->{'operational_state'};
    $obj->{'bfd'} = $self->{'bfd'};
    return $obj;
}

=head2 peer_ip

=cut
sub peer_ip{
    my $self = shift;
    my $ip = shift;
    if (defined $ip) {
        $self->{'peer_ip'} = $ip;
    }
    return $self->{'peer_ip'};
}

=head2 local_ip

=cut
sub local_ip{
    my $self = shift;
    my $ip = shift;
    if (defined $ip) {
        $self->{'local_ip'} = $ip;
    }
    return $self->{'local_ip'};
}

=head2 ip_version

=cut
sub ip_version{
    my $self = shift;
    return $self->{'ip_version'};
}

=head2 peer_asn

=cut
sub peer_asn{
    my $self = shift;
    my $value = shift;
    if (defined $value) {
        $self->{peer_asn} = $value;
    }
    return $self->{peer_asn};
}

=head2 md5_key

=cut
sub md5_key{
    my $self = shift;
    my $md5_key = shift;
    if (defined $md5_key) {
        $self->{md5_key} = $md5_key;
    }
    return $self->{md5_key};
}

=head2 vrf_ep_id

=cut
sub vrf_ep_id{
    my $self = shift;
    return $self->{'vrf_ep_id'};
}

=head2 vrf_ep_peer_id

=cut
sub vrf_ep_peer_id{
    my $self = shift;
    return $self->{'vrf_ep_peer_id'};
}

=head2 operational_state

=cut
sub operational_state{
    my $self = shift;
    return $self->{'operational_state'};
}

=head2 bfd

=cut
sub bfd{
    my $self = shift;
    my $value = shift;
    if (defined $value) {
        $self->{'bfd'} = $value;
    }
    return $self->{'bfd'};
}

=head2 decom

=cut
sub decom{
    my $self = shift;

    my $res = OESS::DB::VRF::decom_peer(db => $self->{'db'}, vrf_ep_peer_id => $self->vrf_ep_peer_id());
    return $res;
}

=head2 create

    $db->start_transaction;
    my ($id, $err) = $peer->create(
        circuit_ep_id => 100, # Optional
        vrf_ep_id     => 100  # Optional
    );
    if (defined $err) {
        $db->rollback;
        warn $err;
    }

create saves this Peer to the database. This method B<must> be wrapped
in a transaction and B<shall> only be used to create a new Peer.

=cut
sub create {
    my $self = shift;
    my $args = {
        circuit_ep_id  => undef,
        vrf_ep_id      => undef,
        @_
    };

    if (!defined $self->{db}) {
        $self->{'logger'}->error("Couldn't create Peer: DB handle is missing.");
        return (undef, "Couldn't create Peer: DB handle is missing.");
    }

    my $model = $self->to_hash;
    $model->{vrf_ep_id} = $args->{vrf_ep_id};
    my ($id, $err) = OESS::DB::Peer::create(
        db => $self->{db},
        model => $model
    );
    $self->{vrf_ep_peer_id} = $id;

    return ($id, $err);
}

=head2 update

    my $err = $peer->update;
    $db->rollback if defined $err;

update saves any changes made to this Peer.

=cut
sub update {
    my $self = shift;

    if (!defined $self->{db}) {
        $self->{'logger'}->error('Unable to write db; Handle is missing.');
    }

    return OESS::DB::Peer::update(
        db => $self->{db},
        peer => $self->to_hash
    );
}

1;
