#!/usr/bin/perl

use strict;
use warnings;

package OESS::DB::VRF;

use OESS::Endpoint;
use OESS::Peer;
use OESS::Interface;
use OESS::User;
use OESS::Workgroup;

use OESS::DB::Endpoint;

use Data::Dumper;
use JSON::XS;

my $logger = Log::Log4perl->get_logger("OESS.DB.VRF");

=head2 fetch

=cut
sub fetch {
    my %params = @_;
    my $db     = $params{'db'};
    my $status = $params{'status'} || 'active';
    my $vrf_id = $params{'vrf_id'};

    my $q = "
        select vrf.created_by as created_by_id, vrf.last_modified_by as last_modified_by_id, vrf.*
        from vrf where vrf_id = ?
    ";

    my $res = $db->execute_query($q, [$vrf_id]);
    if (!defined $res || !defined $res->[0]) {
        return;
    }
    my $details = $res->[0];

    # These are reserved for the VRF object after load_users is
    # called. Will be populated by OESS::User objects.
    delete $details->{created_by};
    delete $details->{last_modified_by};

    return $details;
}

=head2 update

=cut
sub update {
    my %params = @_;
    my $db = $params{'db'};
    my $vrf = $params{'vrf'};

    return if (!defined $vrf->{vrf_id});

    my $reqs = [];
    my $args = [];
    my $set = '';

    if (defined $vrf->{name}) {
        push @$reqs, 'name=?';
        push @$args, $vrf->{name};
    }
    if (defined $vrf->{description}) {
        push @$reqs, 'description=?';
        push @$args, $vrf->{description};
    }
    if (defined $vrf->{local_asn}) {
        push @$reqs, 'local_asn=?';
        push @$args, $vrf->{local_asn};
    }
    if (defined $vrf->{last_modified}) {
        push @$reqs, 'last_modified=?';
        push @$args, $vrf->{last_modified};
    }
    if (defined $vrf->{last_modified_by_id}) {
        push @$reqs, 'last_modified_by=?';
        push @$args, $vrf->{last_modified_by_id};
    }
    $set .= join(', ', @$reqs);
    push @$args, $vrf->{vrf_id};

    my $result = $db->execute_query(
        "UPDATE vrf SET $set WHERE vrf_id=?",
        $args
    );

    my $vrf_object = encode_json($vrf);
    my $vrf_inst_query = "insert into history (date, user_id, workgroup_id, event, state, type, object) values (unix_timestamp(now()), ?, ?, 'User requested connection edit', ?, 'VRF', ?)";
    my $history_id = $db->execute_query($vrf_inst_query, [$vrf->{last_modified_by_id}, $vrf->{workgroup_id}, $vrf->{state}, $vrf_object]);
    if (!defined $history_id) {
        return (undef, $db->get_error);
    }

    my $vrf_history = $db->execute_query("insert into vrf_history (vrf_id, history_id) values (?, ?)", [$vrf->{vrf_id}, $history_id]);

    return $result;
}

=head2 create

=cut
sub create{
    my %params = @_;
    my $db = $params{'db'};
    my $model = $params{'model'};

    my $vrf_id = $db->execute_query("insert into vrf (name, description, workgroup_id, local_asn, created, created_by, last_modified, last_modified_by, state) VALUES (?,?,?,?,unix_timestamp(now()), ?, unix_timestamp(now()), ?, 'active')", [$model->{'name'}, $model->{'description'},$model->{'workgroup_id'}, $model->{'local_asn'}, $model->{'created_by_id'}, $model->{'last_modified_by_id'}]);
    if (!defined $vrf_id) {
        return (undef, $db->get_error);
    }

    $model->{'vrf_id'} = $vrf_id;
    my $vrf_object = encode_json($model);
    my $history_id = $db->execute_query("insert into history (date, state, user_id, workgroup_id, event, type, object) values (unix_timestamp(now()), 'active', ?, ?, 'Connection Creation', 'VRF', ?)", [$model->{'last_modified_by_id'}, $model->{'workgroup_id'}, $vrf_object]);
    if (!defined $history_id) {
        return (undef, $db->get_error);
    }

    my $vrf_history_id = $db->execute_query("insert into vrf_history (history_id, vrf_id) values (?, ?)", [$history_id, $vrf_id]);
    if (!defined $vrf_history_id) {
        return (undef, $db->get_error);
    }

    return ($vrf_id, undef);
}

=head2 delete_endpoints

=cut
sub delete_endpoints {
    my %params = @_;
    my $db = $params{'db'};
    my $vrf_id = $params{'vrf_id'};

    my $ok = $db->execute_query(
        "delete vrf_ep_peer
         from vrf_ep join vrf_ep_peer on vrf_ep.vrf_ep_id=vrf_ep_peer.vrf_ep_id
         where vrf_ep.vrf_id=?",
        [$vrf_id]
    );
    if (!$ok) {
        return $ok;
    }

    $ok = $db->execute_query(
        "delete from vrf_ep where vrf_id=?",
        [$vrf_id]
    );
    if (!$ok) {
        return $ok;
    }

    return $ok;
}

=head2 add_endpoint

=cut
sub add_endpoint{
    my %params = @_;

    my $db = $params{'db'};
    my $model = $params{'model'};
    my $vrf_id = $params{'vrf_id'};

    $logger->error('add_endpoint:' . Dumper($model));

    my $unit = OESS::DB::Endpoint::find_available_unit(
        db => $db,
        interface_id => $model->{'interface_id'},
        tag => $model->{'tag'},
        inner_tag => $model->{'inner_tag'}
    );
    if(!defined($unit)){
        my $error = $db->get_error();
        warn $error;
        $db->rollback();
        return;
    }

    my $vrf_ep_id = $db->execute_query("insert into vrf_ep (interface_id, tag, inner_tag, bandwidth, vrf_id, state, unit, mtu) VALUES (?,?,?,?,?,?,?,?)",[$model->{'interface_id'}, $model->{'tag'}, $model->{'inner_tag'}, $model->{'bandwidth'}, $vrf_id, 'active', $unit, $model->{'mtu'} || 9000]);
    if(!defined($vrf_ep_id)){
        my $error = $db->get_error();
        warn $error;
        $db->rollback();
        return;
    }

    if (defined $model->{cloud_account_id} && $model->{cloud_account_id} ne '') {
        $db->execute_query(
            "insert into cloud_connection_vrf_ep (vrf_ep_id, cloud_account_id, cloud_connection_id)
             values (?, ?, ?)",
            [$vrf_ep_id, $model->{cloud_account_id}, $model->{cloud_connection_id}]
        );
    }

    $logger->error('adding peers:' . Dumper($model->{'peers'}));

    foreach my $peer (@{$model->{'peers'}}){
        my $res = add_peer(db => $db, model => $peer, vrf_ep_id => $vrf_ep_id);
        if (!defined $res) {
            $logger->error('add_peer error: ' . $db->get_error);
            $db->rollback();
            return;
        }
        $logger->error('add_peer success: ' . Dumper($res));
    }

    return $vrf_ep_id;
}

=head2 add_peer

=cut
sub add_peer{
    my %params = @_;
    
    my $db = $params{'db'};
    my $model = $params{'model'};
    my $vrf_ep_id = $params{'vrf_ep_id'};

    $logger->error('add_peer model: ' . Dumper($model));

    eval {
        return $db->execute_query("insert into vrf_ep_peer (vrf_ep_id, peer_ip, local_ip, peer_asn, md5_key, state, operational_state) VALUES (?,?,?,?,?,?,?)",[$vrf_ep_id, $model->{'peer_ip'}, $model->{'local_ip'}, $model->{'peer_asn'}, $model->{'md5_key'}, 'active', 0]);
    };
    if ($@) {
        $logger->error("add_peer error: $@");
    }
}

=head2 fetch_endpoints

=cut
sub fetch_endpoints{
    my %params = @_;

    my $db = $params{'db'};
    my $vrf_id = $params{'vrf_id'};
    my $status = $params{'status'} || 'active';

    #find endpoints 
    my $res = $db->execute_query(
        "select vrf_ep.vrf_ep_id from vrf_ep
         left join cloud_connection_vrf_ep on vrf_ep.vrf_ep_id=cloud_connection_vrf_ep.vrf_ep_id
         where vrf_id = ? and state = ?", [$vrf_id, $status]
    );
    if(!defined($res) || !defined($res->[0])){
        return;
    }

    return $res;
}

=head2 fetch_endpoints_on_interface

=cut
sub fetch_endpoints_on_interface{
    my %params = @_;
    my $db = $params{'db'};
    my $interface_id = $params{'interface_id'};
    my $state = $params{'state'} || 'active';

    my $res = $db->execute_query(
        "select vrf_ep.vrf_ep_id from vrf_ep ".
        "left join cloud_connection_vrf_ep on vrf_ep.vrf_ep_id=cloud_connection_vrf_ep.vrf_ep_id ".
        "where interface_id = ? and state = ?", [$interface_id, $state]);
    if(!defined($res)) {
        return;
    }
    return $res;
}

=head2 fetch_endpoint

=cut
sub fetch_endpoint{
    my %params = @_;

    my $db = $params{'db'};
    my $vrf_ep_id = $params{'vrf_endpoint_id'};
    my $status = $params{'status'} || 'active';

    my $vrf_ep = $db->execute_query(
        "select * from vrf_ep
         left join cloud_connection_vrf_ep on vrf_ep.vrf_ep_id=cloud_connection_vrf_ep.vrf_ep_id
         where vrf_ep.vrf_ep_id = ?", [$vrf_ep_id]
    );
    
    if(!defined($vrf_ep) || !defined($vrf_ep->[0])){
        return;
    }

    $vrf_ep = $vrf_ep->[0];

    my $interface = OESS::Interface->new(db => $db, interface_id => $vrf_ep->{'interface_id'});
    my $peers = OESS::DB::VRF::fetch_endpoint_peers(db => $db, vrf_ep_id => $vrf_ep_id);

    my @peers;
    foreach my $peer (@$peers){
        push(@peers, OESS::Peer->new( vrf_ep_peer_id => $peer->{'vrf_ep_peer_id'}, db => $db));
    }

    $vrf_ep->{'peers'} = \@peers;
    $vrf_ep->{'interface'} = $interface;

    return $vrf_ep;    
}

=head2 update_endpoint

    my $err = OESS::DB::VRF::update_endpoint(
        db       => $db,
        endpoint => {
            vrf_ep_id => 1,
            mtu       => 1500, # Optional
        }
    );
    if (defined $err) {
        warn $err;
    }

=cut
sub update_endpoint {
    my $args = {
        db       => undef,
        endpoint => {},
        @_
    };

    return 'Required argument `db` is missing.' if !defined $args->{db};
    return 'Required argument `endpoint.vrf_ep_id` is missing.' if !defined $args->{endpoint}->{vrf_ep_id};

    my $params = [];
    my $values = [];

    if (defined $args->{endpoint}->{mtu}) {
        push @$params, 'mtu=?';
        push @$values, $args->{endpoint}->{mtu};
    }

    my $fields = join(', ', @$params);
    push @$values, $args->{endpoint}->{vrf_ep_id};

    my $result = $args->{db}->execute_query(
        "UPDATE vrf_ep SET $fields WHERE vrf_ep.vrf_ep_id=?",
        $values
    );
    if (!$result) {
        return 'Error updating vrf_ep: ' . $args->{db}->get_error;
    }

    return undef;
}

=head2 fetch_endpoint_peers

=cut
sub fetch_endpoint_peers{
    my %params = @_;
    
    my $db = $params{'db'};
    my $vrf_ep_id = $params{'vrf_ep_id'};
    my $status = 'active';

    my $bgp_res = $db->execute_query("select vrf_ep_peer_id from vrf_ep_peer where vrf_ep_id = ? and state = ?",[$vrf_ep_id, $status]);
    
    return $bgp_res;
     
}

=head2 fetch_peer

=cut
sub fetch_peer{
    my %params = @_;
    
    my $db = $params{'db'};
    my $vrf_ep_peer_id = $params{'vrf_ep_peer_id'};

    my $peer = $db->execute_query("select * from vrf_ep_peer where vrf_ep_peer_id = ?",[$vrf_ep_peer_id]);

    if(!defined($peer) || !defined($peer->[0])){
        return;
    }

    $peer = $peer->[0];
    return $peer;


}

=head2 decom

=cut
sub decom{
    my %params = @_;
    my $db = $params{'db'};
    my $vrf_id = $params{'vrf_id'};
    my $user = $params{'user_id'};

    my $res = $db->execute_query("update vrf set state = 'decom', last_modified_by = ?, last_modified = unix_timestamp(now()) where vrf_id = ?",[$user, $vrf_id]);

    my $vrf_inst_id = $db->execute_query("insert into history (date, state, user_id, event, type, object) values (unix_timestamp(now()), 'decom', ?, 'Connection Deletion', 'VRF', '')", [$user]);
    if (!defined $vrf_inst_id) {
        return (undef, $db->get_error);
    }

    return $res;

}

=head2 decom_endpoint

=cut
sub decom_endpoint{
    my %params = @_;
    my $db = $params{'db'};
    my $vrf_ep_id = $params{'vrf_endpoint_id'};
    
    my $res = $db->execute_query("update vrf_ep set state = 'decom' where vrf_ep_id = ?",[$vrf_ep_id]);
    return $res;

}

=head2 decom_peer

=cut
sub decom_peer{
    my %params = @_;
    my $db = $params{'db'};
    my $vrf_ep_peer_id = $params{'vrf_ep_peer_id'};

    my $res = $db->execute_query("update vrf_ep_peer set state = 'decom' where vrf_ep_peer_id = ?",[$vrf_ep_peer_id]);
    return $res;
}

=head2 get_vrfs

=cut
sub get_vrfs{
    my %params = @_;
    my $db = $params{'db'};

    my @where_str;
    my @where_val;

    if (defined $params{'vrf_id'}) {
        push @where_val, $params{'vrf_id'};
        push @where_str, "vrf.vrf_id=?";
    }
    if (defined $params{'state'}) {
        push @where_val, $params{'state'};
        push @where_str, "vrf.state=?";
    }
    if (defined $params{'interface_id'}) {
        push @where_val, $params{'interface_id'};
        push @where_str, "interface.interface_id=?";
    }
    if (defined $params{'node_id'}) {
        push @where_val, $params{'node_id'};
        push @where_str, "interface.node_id=?";
    }
    if(defined($params{'workgroup_id'})){
        push(@where_val, $params{'workgroup_id'});
        push(@where_val, $params{'workgroup_id'});
        push(@where_str, "(vrf.workgroup_id=? or interface.workgroup_id=?)");
    }

    my $where = (@where_str > 0) ? 'WHERE ' . join(' AND ', @where_str) : '';

    my $vrfs = $db->execute_query(
        "SELECT vrf.vrf_id
         FROM vrf
         JOIN vrf_ep on vrf_ep.vrf_id=vrf.vrf_id
         JOIN interface on interface.interface_id=vrf_ep.interface_id
         JOIN node on node.node_id=interface.node_id
         $where
         GROUP BY vrf.vrf_id",
        \@where_val
    );

    return $vrfs;
}

=head2 get_vrf_history

=cut
sub get_vrf_history{
    my %params = @_;
    my $events;
    my $vrf_id = $params{'vrf_id'};
    my $db = $params{'db'};

    my $results = $db->execute_query(
        "select remote_auth.auth_name, concat(user.given_names, ' ', user.family_name) as full_name, history.event,
         from_unixtime(history.date) as last_updated
         from vrf
         join vrf_history on vrf.vrf_id = vrf_history.vrf_id
         join history on vrf_history.history_id = history.history_id
         join user on user.user_id = history.user_id
         left join remote_auth on remote_auth.user_id = user.user_id
         where vrf.vrf_id = ? order by history.date DESC",
    [$vrf_id]);

    foreach my $row (@$results){
	push (@$events, {"username"  => $row->{'auth_name'},
            "fullname"  => $row->{'full_name'},
            "scheduled" => -1,
            "activated" => $row->{'last_updated'},
            "layout"    => "",
            "reason"    => $row->{'event'}
	      }
	    );
    }

    return $events;
}

1;
