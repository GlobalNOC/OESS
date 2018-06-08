#!/usr/bin/perl

use strict;
use warnings;

use OESS::Endpoint;

package OESS::DB::VRF;

use Data::Dumper;


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
    
    #my $user = $db->get_user_by_id( user_id => $details->{'created_by'});
    
    #my $workgroup = $db->get_workgroup_by_id( workgroup_id => $details->{'workgroup_id'} );

    #$details->{'created_by'} = $user;
    #$details->{'workgroup'} = $workgroup;
    
    my $ep_ids = OESS::DB::VRF::fetch_endpoints(db => $db, vrf_id => $vrf_id);

    warn Dumper($ep_ids);
    
    foreach my $ep (@$ep_ids){
        warn Dumper($ep);
        push(@{$details->{'endpoints'}}, OESS::Endpoint->new(db => $db, type => 'vrf', vrf_endpoint_id => $ep->{'vrf_ep_id'}));
    }
    
    return $details;
}

sub update{
    my %params = @_;
    
    if(!defined($params{'vrf_id'}) || $params{'vrf_id'} == -1){
        return _create_vrf(\%params);
    }else{
        return _update_vrf(\%params);
    }
    
}

sub _create_vrf{
    my %params = @_;
    my $db = $params{'db'};
    my $model = $params{'model'};
    
    $db->_start_transaction();
 
   
    my $vrf_id = $db->execute_query("insert into vrf (name, description, workgroup_id, created, created_by, last_modified, last_modified_by, state) VALUES (?,?,?,unix_timestamp(now()), ?, unix_timestamp(now()), ?, 'active')", [$model->{'name'}, $model->{'description'},$model->{'workgroup_id'}, $model->{'user_id'}, $model->{'user_id'}]);
    if(!defined($vrf_id)){
        my $error = $db->get_error();
        $db->_rollback();
        return;
    }
    
    foreach my $ep (@{$model->{'endpoints'}}){
        my $interface_id = $db->get_interface_id_by_names( interface => $ep->{'interface'}, node => $ep->{'node'} );
        
        if(!defined($interface_id)){
            $db->_rollback();
            return;
        }
        
        if(!defined($ep->{'tag'}) || !defined($ep->{'bandwidth'})){
            $db->_rollback();
            return;
        }
        
        
        my $vrf_ep_id = $db->execute_query("insert into vrf_ep (interface_id, tag, bandwidth, vrf_id, state) VALUES (?,?,?,?,?)",[$interface_id, $ep->{'tag'}, $ep->{'bandwidth'}, $vrf_id, 'active']);
        if(!defined($vrf_ep_id)){
            my $error = $db->get_error();
            $db->_rollback();
            return;
        }
        
        foreach my $bgp (@{$ep->{'peerings'}}){
            warn Dumper($bgp);
            my $res = $db->execute_query("insert into vrf_ep_peer (vrf_ep_id, peer_ip, local_ip, peer_asn, md5_key, state) VALUES (?,?,?,?,?,?)",[$vrf_ep_id, $bgp->{'peer_ip'}, $bgp->{'local_ip'}, $bgp->{'asn'}, $bgp->{'key'}, 'active']);
            if(!defined($res)){
                my $error = $db->get_error();
                $db->_rollback();
                return;
            }
        }
    }
    
    $db->_commit();
    
}

sub fetch_endpoints{
    my %params = @_;

    my $db = $params{'db'};
    my $vrf_id = $params{'vrf_id'};
    my $status = $params{'status'} || 'active';

    #find endpoints 
    my $res = $db->execute_query("select vrf_ep.vrf_ep_id from vrf_ep where vrf_id = ? and state = ?", [$vrf_id, $status]);
    warn Dumper($res);
    if(!defined($res) || !defined($res->[0])){
        return;
    }

    return $res;

}

sub fetch_endpoint{
    my %params = @_;

    my $db = $params{'db'};
    my $vrf_ep_id = $params{'vrf_endpoint_id'};
    my $status = $params{'status'} || 'active';

    my $vrf_ep = $db->execute_query("select * from vrf_ep where vrf_ep_id = ?", [$vrf_ep_id]);
    
    if(!defined($vrf_ep) || !defined($vrf_ep->[0])){
        return;
    }

    $vrf_ep = $vrf_ep->[0];

    my $interface = OESS::Interface->new(db => $db, interface_id => $vrf_ep->{'interface_id'});
    my $peers = OESS::DB::VRF::fetch_endpoint_peers(db => $db, vrf_ep_id => $vrf_ep_id);

    my @peers;
    foreach my $peer (@$peers){
        warn "Creating Peer: " . Dumper($peer);
        push(@peers, OESS::Peer->new( vrf_ep_peer_id => $peer->{'vrf_ep_peer_id'}, db => $db));
    }

    $vrf_ep->{'peers'} = \@peers;
    $vrf_ep->{'interface'} = $interface;

    return $vrf_ep;    
}


sub fetch_endpoint_peers{
    my %params = @_;
    
    my $db = $params{'db'};
    my $vrf_ep_id = $params{'vrf_ep_id'};
    my $status = 'active';

    my $bgp_res = $db->execute_query("select vrf_ep_peer_id from vrf_ep_peer where vrf_ep_id = ? and state = ?",[$vrf_ep_id, $status]);
    
    return $bgp_res;
     
}

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

sub _update_vrf{
        
        
}
    
    1;
