#!/usr/bin/perl

package OESS::DB::VRF;

sub fetch{
    my %params = @_;
    my $db = $params{'db'};
    
    my $status = $params{'status'} || 'active';

    my $vrf_id = $self->{'vrf_id'};

    my $details;

    my $res = $db->_execute_query("select * from vrf where vrf_id = ?", [$vrf_id]);
    if(!defined($res) || !defined($res->[0])){
        $self->{'logger'}->error("Error fetching VRF from database");
        return;
    }

    $details = $res->[0];
    
    my $user = $db->get_user_by_id( user_id => $details->{'created_by'});
    
    my $workgroup = $self->db->get_workgroup_by_id( workgroup_id => $details->{'workgroup_id'} );

    $details->{'created_by'} = $user;
    $details->{'workgroup'} = $workgroup;
    
    #find endpoints 
    $res = $db->_execute_query("select vrf_ep.*, node.name as node, interface.name as int_name from vrf_ep join interface on interface.interface_id = vrf_ep.interface_id join node on node.node_id = interface.node_id where vrf_id = ? and state = ?", [$vrf_id, $status]);
    if(!defined($res) || !defined($res->[0])){
        $logger->error("Error fetching VRF endpoints");
        return;
    }
    
    $details->{'endpoints'} = ();

    foreach my $ep (@$res){
        my $bgp_res = $db->_execute_query("select * from vrf_ep_peer where vrf_ep_id = ? and state = ?",[$ep->{'vrf_ep_id'}, $status]);
        if(!defined($bgp_res) || !defined($bgp_res->[0])){
            $bgp_res = ();
        }
        
        my @bgp;

        foreach my $bgp (@{$bgp_res}){
            push(@bgp, $bgp);
        }


        my $int = $db->get_interface( interface_id => $ep->{'interface_id'});
        
        $int->{'tag'} = $ep->{'tag'};
        $int->{'node'} = $ep->{'node'};
        $int->{'node_id'} = $ep->{'node_id'};
        $int->{'bandwidth'} = $ep->{'bandwidth'};
        $int->{'state'} = $ep->{'state'};
        $int->{'vrf_ep_id'} = $ep->{'vrf_ep_id'};
        $int->{'peers'} = \@bgp;
        
        push(@{$details->{'endpoints'}}, $int);
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
 
   
    my $vrf_id = $db->_execute_query("insert into vrf (name, description, workgroup_id, created, created_by, last_modified, last_modified_by, state) VALUES (?,?,?,unix_timestamp(now()), ?, unix_timestamp(now()), ?, 'active')", [$model->{'name'}, $model->{'description'},$model->{'workgroup_id'}, $model->{'user_id'}, $model->{'user_id'}]);
    if(!defined($vrf_id)){
        my $error = $db->get_error();
        $method->set_error("Unable to create VRF: " . $error);
        $db->_rollback();
        return;
    }
    
    foreach my $ep (@{$model->{'endpoints'}}){
        my $interface_id = $db->get_interface_id_by_names( interface => $ep->{'interface'}, node => $ep->{'node'} );
        
        if(!defined($interface_id)){
            $db->_rollback();
            $method->set_error("Unable to find interface: " . $ep->{'interface'} . " on node " . $ep->{'node'});
            return;
        }
        
        if(!defined($ep->{'tag'}) || !defined($ep->{'bandwidth'})){
            $db->_rollback();
            $method->set_error("VRF Endpoints require both VLAN and Bandwidth fields to be specified");
            return;
        }
        
        
        my $vrf_ep_id = $db->_execute_query("insert into vrf_ep (interface_id, tag, bandwidth, vrf_id, state) VALUES (?,?,?,?,?)",[$interface_id, $ep->{'tag'}, $ep->{'bandwidth'}, $vrf_id, 'active']);
        if(!defined($vrf_ep_id)){
            my $error = $db->get_error();
            $method->set_error("Unable to add VRF Endpoint: " . $error);
            $db->_rollback();
            return;
        }
        
        foreach my $bgp (@{$ep->{'peerings'}}){
            warn Dumper($bgp);
            my $res = $db->_execute_query("insert into vrf_ep_peer (vrf_ep_id, peer_ip, local_ip, peer_asn, md5_key, state) VALUES (?,?,?,?,?,?)",[$vrf_ep_id, $bgp->{'peer_ip'}, $bgp->{'local_ip'}, $bgp->{'asn'}, $bgp->{'key'}, 'active']);
            if(!defined($res)){
                my $error = $db->get_error();
                $method->set_error("Uanble to add VRF Endpoint peer: " . $error);
                $db->_rollback();
                return;
            }
        }
    }
    
    $db->_commit();
    
}

sub _update_vrf{
        
        
}
    
    1;
