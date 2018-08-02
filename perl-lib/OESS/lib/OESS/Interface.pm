#!/usr/bin/perl

use strict;
use warnings;

package OESS::Interface;

use OESS::DB::Interface;


sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS.Interface");

    my %args = (
        interface_id => undef,
        db => undef,
        @_
        );

    my $self = \%args;

    bless $self, $class;

    $self->{'logger'} = $logger;

    if(!defined($self->{'db'})){
        $self->{'logger'}->error("No Database Object specified");
        return;
    }

    my $ok = $self->_fetch_from_db();
    if (!$ok) {
        return;
    }

    return $self;
}

sub from_hash{
    my $self = shift;
    my $hash = shift;
    
    $self->{'name'} = $hash->{'name'};
    $self->{'interface_id'} = $hash->{'interface_id'};
    $self->{'node'} = $hash->{'node'};
    $self->{'description'} = $hash->{'description'};
    $self->{'acls'} = $hash->{'acls'};
    $self->{'mpls_vlan_tag_range'} = $hash->{'mpls_vlan_tag_range'};
    $self->{'used_vlans'} = $hash->{'used_vlans'};
    $self->{'operational_state'} = $hash->{'operational_state'};

    return 1;
}

sub to_hash{
    my $self = shift;

    my $res = { name => $self->name(),
                description => $self->description(),
                interface_id => $self->interface_id(),
                node_id => $self->node()->node_id(),
                node => $self->node()->name(),
                acls => $self->acls()->to_hash(),
                operational_state => $self->{'operational_state'} };
    
    return $res;
}

sub _fetch_from_db{
    my $self = shift;

    if (!defined $self->{'interface_id'}) {
        if (defined $self->{'name'} && defined $self->{'node'}) {
            my $interface_id = OESS::DB::Interface::get_interface(db => $self->{'db'}, interface => $self->{'name'}, node => $self->{'node'});
            if (!defined $interface_id) {
                $self->{'logger'}->error("Unable to fetch interface $self->{name} on $self->{node} from the db!");
                return;
            }
            $self->{'interface_id'} = $interface_id;
        } else {
	    $self->{'logger'}->error("Unable to fetch interface $self->{name} on $self->{node} from the db!");
	    return;
	}
    }

    my $info = OESS::DB::Interface::fetch(db => $self->{'db'}, interface_id => $self->{'interface_id'});
    if (!defined $info) {
        $self->{'logger'}->error("Unable to fetch interface $self->{interface_id} from the db!");
        return;
    }

    return $self->from_hash($info);
}

sub update_db{
    my $self = shift;

}

sub operational_state{
    my $self = shift;
    return $self->{'operational_state'};
}

sub interface_id{
    my $self = shift;
    return $self->{'interface_id'};
}

sub name{
    my $self = shift;
    return $self->{'name'};
}

sub description{
    my $self = shift;
    return $self->{'description'};
    
}

sub port_number{

}

sub acls{
    my $self = shift;
    return $self->{'acls'};
}

sub role{

}

sub node{
    my $self = shift;
    return $self->{'node'};
}

sub workgroup{
    
}

sub vlan_tag_range{

}

sub mpls_vlan_tag_range{
    my $self = shift;
    return $self->{'mpls_vlan_tag_range'};
}

sub used_vlans{
    my $self = shift;

    return $self->{'used_vlans'};
}

sub vlan_in_use{
    my $self = shift;
    my $vlan = shift;

    #check and see if the specified VLAN tag is already in use

    if(!defined($self->{'mpls_range'})){
        $self->_process_mpls_vlan_tag();
    }

    foreach my $used (@{$self->used_vlans()}){
        if($used == $vlan){
            return 1;
        }
    }

    return 0;

}

sub _process_mpls_vlan_tag{
    my $self = shift;
    
    
    my %range;
    my @range = split(',',$self->mpls_vlan_tag_range());
    foreach my $range (@range){
        if($range =~ /-/){
            my ($start,$end) = split('-',$range);
            for(my $i=$start; $i<=$end;$i++){
                $range{$i} = 1;
            }
        }else{
            #single value
            $range{$range} = 1;
        }
    }
    $self->{'mpls_range'} = \%range;
}

sub mpls_range{
    my $self = shift;
    if(!defined($self->{'mpls_range'})){
        $self->_process_mpls_vlan_tag();
    }
    return $self->{'mpls_range'};
}

sub vlan_valid{
    my $self = shift;
    my %params = @_;
    my $vlan = $params{'vlan'};
    my $workgroup_id = $params{'workgroup_id'};

    #first check for valid range
    if($vlan < 1 || $vlan > 4095){
        return 0;
    }

    #first check and make sure the VLAN tag is not in use
    if($self->vlan_in_use($vlan)){
        return 0;
    }

    if(!$self->acls()->vlan_allowed( vlan => $vlan, workgroup_id => $workgroup_id)){
        return 0;
    }
    
    if(!defined($self->mpls_range()->{$vlan})){
        return 0;
    }

    #ok we got this far... its allowed
    return 1;
}

1;

