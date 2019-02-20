#!/usr/bin/perl

use strict;
use warnings;

package OESS::Peer;

use Data::Dumper;

=head2 new

=cut
sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS.Endpoint");

    my %args = (
        vrf_peer_id => undef,
        db => undef,
        just_display => 0,
        link_status => undef,
        @_
        );

    my $self = \%args;

    bless $self, $class;

    $self->{'logger'} = $logger;

    if(!defined($self->{'db'})){
        $self->{'logger'}->error("No Database Object specified");
        return;
    }

    if(!defined($self->{'vrf_ep_peer_id'}) || $self->{'vrf_ep_peer_id'} == -1){
        $self->_build_from_model();
    }else{
        $self->_fetch_from_db();
    }

    return $self;
}

=head2 _build_from_model

=cut
sub _build_from_model{
    my $self = shift;

    $self->{'peer_ip'} = $self->{'model'}->{'peer_ip'};
    $self->{'peer_asn'} = $self->{'model'}->{'asn'};
    $self->{'md5_key'} = $self->{'model'}->{'key'};
    $self->{'local_ip'} = $self->{'model'}->{'local_ip'};
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
    $self->{'md5_key'} = $hash->{'md5_key'};
    $self->{'state'} = $hash->{'state'};
    $self->{'local_ip'} = $hash->{'local_ip'};

    if ($self->{'local_ip'} =~ /^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/([0-9]|[1-2][0-9]|3[0-2]))$/) {
        $self->{'ip_version'} = 4;
    } else {
        $self->{'ip_version'} = 6;
    }

    $self->{'operational_state'} = $hash->{'operational_state'};

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
    $obj->{'state'} = $self->{'state'};
    $obj->{'local_ip'} = $self->{'local_ip'};
    $obj->{'ip_version'} = $self->{'ip_version'};
    $obj->{'operational_state'} = $self->operational_state();
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
    return $self->{'md5_key'};
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
    if($self->{'operational_state'} == 1){
        return "up";
    }else{
        return "down"
    }
}

=head2 _fetch_from_db

=cut
sub _fetch_from_db{
    my $self = shift;
   
    my $db = $self->{'db'};
    my $vrf_ep_peer_id = $self->{'vrf_ep_peer_id'};

    my $hash = OESS::DB::VRF::fetch_peer(db => $db, vrf_ep_peer_id => $vrf_ep_peer_id);
    $self->from_hash($hash);
}

=head2 decom

=cut
sub decom{
    my $self = shift;

    my $res = OESS::DB::VRF::decom_peer(db => $self->{'db'}, vrf_ep_peer_id => $self->vrf_ep_peer_id());
    return $res;
}

1;
