#!/usr/bin/perl

use strict;
use warnings;

package OESS::DB::VRF;

use OESS::Endpoint;
use OESS::Peer;
use OESS::Interface;
use OESS::User;
use OESS::Workgroup;

use Data::Dumper;

=head2 fetch

=cut
sub fetch{
    my %params = @_;
    my $db = $params{'db'};
    
    my $status = $params{'status'} || 'active';

    my $vrf_id = $params{'vrf_id'};

    my $details;

    my $res = $db->execute_query("select * from vrf where vrf_id = ?", [$vrf_id]);
    if(!defined($res) || !defined($res->[0])){
        return;
    }

    $details = $res->[0];
    
    my $created_by = OESS::User->new( db => $db, user_id => $details->{'created_by'});
    my $last_modified_by = OESS::User->new(db => $db, user_id => $details->{'last_modified_by'});
    my $workgroup = OESS::Workgroup->new( db => $db, workgroup_id => $details->{'workgroup_id'});

    $details->{'last_modified_by'} = $last_modified_by;
    $details->{'created_by'} = $created_by;
    $details->{'workgroup'} = $workgroup;
   

    my $ep_ids = OESS::DB::VRF::fetch_endpoints(db => $db, vrf_id => $vrf_id);
    
    foreach my $ep (@$ep_ids){
        push(@{$details->{'endpoints'}}, OESS::Endpoint->new(db => $db, type => 'vrf', vrf_endpoint_id => $ep->{'vrf_ep_id'}));
    }
    
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
    if (defined $vrf->{last_modified_by}->{user_id}) {
        push @$reqs, 'last_modified_by=?';
        push @$args, $vrf->{last_modified_by}->{user_id};
    }
    $set .= join(', ', @$reqs);
    push @$args, $vrf->{vrf_id};

    my $result = $db->execute_query(
        "UPDATE vrf SET $set WHERE vrf_id=?",
        $args
    );

    return $result;
}

=head2 create

=cut
sub create{
    my %params = @_;
    my $db = $params{'db'};
    my $model = $params{'model'};
    
    $db->start_transaction();
 
   
    my $vrf_id = $db->execute_query("insert into vrf (name, description, workgroup_id, local_asn, created, created_by, last_modified, last_modified_by, state) VALUES (?,?,?,?,unix_timestamp(now()), ?, unix_timestamp(now()), ?, 'active')", [$model->{'name'}, $model->{'description'},$model->{'workgroup'}->{'workgroup_id'}, $model->{'local_asn'}, $model->{'created_by'}->{'user_id'}, $model->{'last_modified_by'}->{'user_id'}]);
    if(!defined($vrf_id)){
        my $error = $db->get_error();
        $db->rollback();
        return;
    }
    
    foreach my $ep (@{$model->{'endpoints'}}){
        my $res = OESS::DB::VRF::add_endpoint(db => $db, model => $ep, vrf_id => $vrf_id);
        if(!defined($res)){
            $db->rollback();
            return;
        }
    }
    
    $db->commit();

    return $vrf_id;
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

=head2 find_available_unit

=cut
sub find_available_unit{
    my %params = @_;
    my $db = $params{'db'};
    my $interface_id = $params{'interface_id'};
    my $tag = $params{'tag'};
    my $inner_tag = $params{'inner_tag'};

    if(!defined($inner_tag)){
        return $tag;
    }

    #find available unit >= 5000
    my $used_vrf_units = $db->execute_query("select unit from vrf_ep where unit >= 5000 and state = 'active' and interface_id= ?",[$interface_id]);
    my $used_circuit_units = $db->execute_query("select unit from circuit_edge_interface_membership where interface_id = ? and end_epoch = -1 and circuit_id in (select circuit.circuit_id from circuit join circuit_instantiation on circuit.circuit_id = circuit_instantiation.circuit_id and circuit.circuit_state = 'active' and circuit_instantiation.circuit_state = 'active' and circuit_instantiation.end_epoch = -1)",[$interface_id]);

    my %used;

    foreach my $used_vrf_unit (@$used_vrf_units){
        $used{$used_vrf_unit->{'unit'}} = 1;
    }

    foreach my $used_circuit_units (@{$used_circuit_units}){
        $used{$used_circuit_units->{'unit'}} = 1;
    }

    
    for(my $i=5000;$i<16000;$i++){
        if(defined($used{$i}) && $used{$i} == 1){
            next;
        }
        return $i;
    }

}

=head2 add_endpoint

=cut
sub add_endpoint{
    my %params = @_;

    my $db = $params{'db'};
    my $model = $params{'model'};
    my $vrf_id = $params{'vrf_id'};

    my $unit = find_available_unit(db => $db, interface_id => $model->{'interface'}->{'interface_id'}, tag => $model->{'tag'}, inner_tag => $model->{'inner_tag'});
    if(!defined($unit)){
        $db->rollback();
        return;
    }   

    my $vrf_ep_id = $db->execute_query("insert into vrf_ep (interface_id, tag, inner_tag, bandwidth, vrf_id, state,unit) VALUES (?,?,?,?,?,?,?)",[$model->{'interface'}->{'interface_id'}, $model->{'tag'}, $model->{'inner_tag'}, $model->{'bandwidth'}, $vrf_id, 'active',$unit]);
    if(!defined($vrf_ep_id)){
        my $error = $db->get_error();
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

    foreach my $peer (@{$model->{'peers'}}){
        my $res = add_peer(db => $db, model => $peer, vrf_ep_id => $vrf_ep_id);
        if(!defined($res)){
            my $error = $db->get_error();
            $db->rollback();
            return;
        }
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

    my $res = $db->execute_query("insert into vrf_ep_peer (vrf_ep_id, peer_ip, local_ip, peer_asn, md5_key, state) VALUES (?,?,?,?,?,?)",[$vrf_ep_id, $model->{'peer_ip'}, $model->{'local_ip'}, $model->{'peer_asn'}, $model->{'md5_key'}, 'active']);

    if(!defined($res)){
        my $error = $db->get_error();
        return;
    }

    return $res;
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

    if(defined($params{'state'})){
        push(@where_val,$params{'state'});
        push(@where_str,"vrf.state = ?");
    }
    
    if(defined($params{'workgroup_id'})){
        push(@where_val, $params{'workgroup_id'});
        #now we need to find all interfaces OWNED by this workgroup and all VRFs on those endpoints!!!!!
        my $interfaces = OESS::DB::Interface::get_interfaces(db => $db, workgroup_id => $params{'workgroup_id'});
        push(@where_val, @$interfaces);
        my $vals = "";
        foreach my $int (@$interfaces){
            if($vals eq ''){
                $vals .= "?";
            }else{
                $vals .= ",?";
            }
        }
        if (!(scalar @$interfaces)) {
            push(@where_str, "(workgroup_id = ?)");
        } else {
            push(@where_str, "(workgroup_id = ? or vrf_ep.interface_id in ($vals))");
        }
    }

    my $where;
    foreach my $str (@where_str){
        if(!defined($where)){
            $where .= $str;
        }else{
            $where .= " and " . $str;
        }
    }

    my $query = "select distinct(vrf.vrf_id) from vrf join vrf_ep on vrf_ep.vrf_id = vrf.vrf_id where $where";

    my $vrfs = $db->execute_query($query,\@where_val);

    return $vrfs;
}

1;
