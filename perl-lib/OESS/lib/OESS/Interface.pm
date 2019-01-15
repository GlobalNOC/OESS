#!/usr/bin/perl

use strict;
use warnings;

package OESS::Interface;

use OESS::DB::Interface;

=head2 new

=cut
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

=head2 from_hash

=cut
sub from_hash{
    my $self = shift;
    my $hash = shift;
    
    $self->{'name'} = $hash->{'name'};
    $self->{'interface_id'} = $hash->{'interface_id'};
    $self->{'node'} = $hash->{'node'};
    $self->{'cloud_interconnect_id'} = $hash->{'cloud_interconnect_id'};
    $self->{'cloud_interconnect_type'} = $hash->{'cloud_interconnect_type'};
    $self->{'description'} = $hash->{'description'};
    $self->{'acls'} = $hash->{'acls'};
    $self->{'mpls_vlan_tag_range'} = $hash->{'mpls_vlan_tag_range'};
    $self->{'used_vlans'} = $hash->{'used_vlans'};
    $self->{'operational_state'} = $hash->{'operational_state'};

    return 1;
}

=head2 to_hash

=cut
sub to_hash{
    my $self = shift;

    my $res = { name => $self->name(),
                cloud_interconnect_id => $self->cloud_interconnect_id(),
                cloud_interconnect_type => $self->cloud_interconnect_type(),
                description => $self->description(),
                interface_id => $self->interface_id(),
                node_id => $self->node()->node_id(),
                node => $self->node()->name(),
                acls => $self->acls()->to_hash(),
                operational_state => $self->{'operational_state'} };
    
    return $res;
}

=head2 _fetch_from_db

=cut
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

=head2 update_db

=cut
sub update_db{
    my $self = shift;

}

=head2 operational_state

=cut
sub operational_state{
    my $self = shift;
    return $self->{'operational_state'};
}

=head2 interface_id

=cut
sub interface_id{
    my $self = shift;
    return $self->{'interface_id'};
}

=head2 name

=cut
sub name{
    my $self = shift;
    return $self->{'name'};
}

=head2 cloud_interconnect_id

=cut
sub cloud_interconnect_id{
    my $self = shift;
    return $self->{'cloud_interconnect_id'};
}

=head2 cloud_interconnect_type

=cut
sub cloud_interconnect_type{
    my $self = shift;
    return $self->{'cloud_interconnect_type'};
}

=head2 description

=cut
sub description{
    my $self = shift;
    return $self->{'description'};
}

=head2 port_number

=cut
sub port_number{

}

=head2 acls

=cut
sub acls{
    my $self = shift;
    return $self->{'acls'};
}

=head2 role

=cut
sub role{

}

=head2 node

=cut
sub node{
    my $self = shift;
    return $self->{'node'};
}

=head2 workgroup

=cut
sub workgroup{
    
}

=head2 vlan_tag_range

=cut
sub vlan_tag_range{

}

=head2 mpls_vlan_tag_range

=cut
sub mpls_vlan_tag_range{
    my $self = shift;
    return $self->{'mpls_vlan_tag_range'};
}

=head2 used_vlans

=cut
sub used_vlans{
    my $self = shift;

    return $self->{'used_vlans'};
}

=head2 vlan_in_use

=cut
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

=head2 _process_mpls_vlan_tag

=cut
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

=head2 mpls_range

=cut
sub mpls_range{
    my $self = shift;
    if(!defined($self->{'mpls_range'})){
        $self->_process_mpls_vlan_tag();
    }
    return $self->{'mpls_range'};
}


=head2 vlan_valid

=cut
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

=head2 is_bandwidth_valid

     my $ok = is_bandwidth_valid(bandwidth => 100);

is_bandwidth_valid returns C<1> if C<bandwidth> can be set on this
interface as this interface's max capacity, otherwise we return C<0>.

=cut
sub is_bandwidth_valid {
    my $self   = shift;
    my %params = @_;

    my $bandwidth = $params{bandwidth};

    my $aws_conn = { 50 => 1, 100 => 1, 200 => 1, 300 => 1, 400 => 1, 500 => 1 };
    my $default  = { 0 => 1 };
    my $gcp_part = { 50 => 1, 100 => 1, 200 => 1, 300 => 1, 400 => 1, 500 => 1, 1000 => 1, 2000 => 1, 5000 => 1, 10000 => 1 };

    if ($self->cloud_interconnect_type eq 'aws-hosted-connection') {
        if (defined $aws_conn->{$bandwidth}) { return 1; } else { return 0; }
    } elsif ($self->cloud_interconnect_type eq 'gcp-partner-interconnect') {
        if (defined $gcp_part->{$bandwidth}) { return 1; } else { return 0; }
    } else {
        if (defined $default->{$bandwidth}) { return 1; } else { return 0; }
    }
}

1;
