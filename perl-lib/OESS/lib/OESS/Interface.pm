use strict;
use warnings;

package OESS::Interface;

use OESS::DB::Interface;
use OESS::Cloud::BandwidthValidator;

use Data::Dumper;
use Log::Log4perl;

=head1 OESS::Interface

    use OESS::Interface

=cut

=head2 new

=cut
sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my %args = (
        db           => undef,
        interface_id => undef,
        logger       => Log::Log4perl->get_logger("OESS.Interface"),
        model        => undef,
        bandwidth_validator_config => "/etc/oess/interface-speed-config.xml",
        @_
    );

    my $self = \%args;
    bless $self, $class;

    if (!defined $self->{'db'}) {
        $self->{'logger'}->warn("No Database Object specified");
    }

    my $can_lookup = (defined $self->{interface_id} || (defined $self->{name} && defined $self->{node}));
    if (defined $self->{'db'} && $can_lookup) {
        my $ok = $self->_fetch_from_db();
        if (!$ok) {
            return;
        }
    }

    if (defined $self->{model}) {
        $self->from_hash($self->{model});
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
    $self->{'node_id'} = $hash->{'node_id'};
    $self->{'node'} = $hash->{'node'};
    $self->{'cloud_interconnect_id'} = $hash->{'cloud_interconnect_id'};
    $self->{'cloud_interconnect_type'} = $hash->{'cloud_interconnect_type'};
    $self->{'description'} = $hash->{'description'};
    $self->{'acls'} = $hash->{'acls'};
    $self->{'mpls_vlan_tag_range'} = $hash->{'mpls_vlan_tag_range'};
    $self->{'used_vlans'} = $hash->{'used_vlans'};
    $self->{'admin_state'} = $hash->{'admin_state'};
    $self->{'operational_state'} = $hash->{'operational_state'};
    $self->{'workgroup_id'} = $hash->{'workgroup_id'};
    $self->{'utilized_bandwidth'} = $hash->{'utilized_bandwidth'} || 0;
    $self->{'bandwidth'} = $hash->{'bandwidth'} || 0;
    $self->{'provisionable_bandwidth'} = $hash->{'provisionable_bandwidth'};
    $self->{'role'} = $hash->{'role'} || 'unknown';
    $self->{'mtu'} = $hash->{'mtu'} || 0;

    return 1;
}

=head2 to_hash

=cut
sub to_hash{
    my $self = shift;

    my $res = {
        name => $self->name(),
        cloud_interconnect_id => $self->cloud_interconnect_id(),
        cloud_interconnect_type => $self->cloud_interconnect_type(),
        description => $self->description(),
        interface_id => $self->interface_id(),
        node_id => $self->{node_id},
        admin_state => $self->{'admin_state'},
        mpls_vlan_tag_range => $self->{'mpls_vlan_tag_range'},
        operational_state => $self->{'operational_state'},
        workgroup_id => $self->workgroup_id(),
        utilized_bandwidth => $self->{'utilized_bandwidth'},
        bandwidth => $self->{'bandwidth'},
        role => $self->{'role'},
        provisionable_bandwidth => $self->{'provisionable_bandwidth'},
        mtu => $self->{'mtu'}
    };

    if (defined $self->{acls}) {
        my $acl_models = [];
        foreach my $acl (@{$self->{acls}}) {
            push @$acl_models, $acl->to_hash;
        }
        $res->{acls} = $acl_models;
    }
    if (defined $self->{node}) {
        $res->{node} = $self->node()->name();
        $res->{node_id} = $self->node()->node_id();
    }
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
                warn "Unable to fetch interface $self->{name} on $self->{node} from the db!";
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

=head2 create

=cut
sub create {
    my $self = shift;
    my $args = {
        node_id => undef,
        @_
    };

    if (!defined $self->{db}) {
        $self->{logger}->error("Couldn't create Interface; DB handle is missing.");
        return (undef, "Couldn't create Interface; DB handle is missing.");
    }
    if (!defined $args->{node_id}) {
        $self->{logger}->error("Couldn't create Interface; node_id is missing.");
        return (undef, "Couldn't create Interface; node_id is missing.");
    }

    my $model = $self->to_hash;
    $model->{node_id} = $args->{node_id};

    my ($id, $err) = OESS::DB::Interface::create(
        db => $self->{db},
        model => $model
    );
    return (undef, $err) if defined $err;

    $self->{interface_id} = $id;
    return ($id, undef);
}

=head2 update_db

=cut
sub update_db {
    my $self = shift;

    if (!defined $self->{'db'}) {
        $self->{'logger'}->error("Could not update Interface: No database object specified.");
        return;
    }

    my $err = OESS::DB::Interface::update(
        db => $self->{'db'},
        interface => $self->to_hash
    );
    if (defined $err) {
        $self->{'logger'}->error("Could not update Interface: $err");
        return;
    }

    return 1;
}

=head2 admin_state

=cut
sub admin_state{
    my $self = shift;
    my $admin_state = shift;

    if (defined $admin_state) {
        $self->{admin_state} = $admin_state;
    }
    return $self->{'admin_state'};
}

=head2 operational_state

=cut
sub operational_state{
    my $self = shift;
    my $operational_state = shift;

    if (defined $operational_state) {
        $self->{operational_state} = $operational_state;
    }
    return $self->{'operational_state'};
}

=head2 bandwidth

=cut
sub bandwidth{
    my $self = shift;
    my $bandwidth = shift;

    if (defined $bandwidth) {
        $self->{bandwidth} = $bandwidth;
    }

    if((defined $self->{'cloud_interconnect_type'}) && ($self->{'cloud_interconnect_type'} eq 'azure-express-route')){
        return $self->{'bandwidth'} * 4;
    }else{
        return $self->{'bandwidth'};
    }
}

=head2 provisionable_bandwidth

=cut
sub provisionable_bandwidth{
    my $self = shift;
    my $provisionable_bandwidth = shift;

    return $self->{provisionable_bandwidth};
}

=head2 mtu

=cut
sub mtu{
    my $self = shift;
    my $mtu = shift;

    if (defined $mtu) {
        $self->{mtu} = $mtu;
    }
    return $self->{'mtu'};
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
sub cloud_interconnect_id {
    my $self = shift;
    my $cloud_interconnect_id = shift;

    if (defined $cloud_interconnect_id) {
        $self->{cloud_interconnect_id} = $cloud_interconnect_id;
    }
    return $self->{'cloud_interconnect_id'};
}

=head2 cloud_interconnect_type

=cut
sub cloud_interconnect_type {
    my $self = shift;
    my $cloud_interconnect_type = shift;

    if (defined $cloud_interconnect_type) {
        $self->{cloud_interconnect_type} = $cloud_interconnect_type;
    }
    return $self->{'cloud_interconnect_type'};
}

=head2 description

=cut
sub description {
    my $self = shift;
    my $description = shift;

    if (defined $description) {
        $self->{description} = $description;
    }
    return $self->{description};
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
    my $self = shift;
    return $self->{'role'};
}

=head2 node

=cut
sub node {
    my $self = shift;
    return $self->{'node'};
}

=head2 node_id

=cut
sub node_id {
    my $self = shift;
    return $self->{'node_id'};
}

=head2 workgroup_id

=cut
sub workgroup_id {
    my $self = shift;
    my $workgroup_id = shift;

    if (defined $workgroup_id) {
        $self->{workgroup_id} = $workgroup_id;
    }
    return $self->{'workgroup_id'};
}

=head2 vlan_tag_range

=cut
sub vlan_tag_range{

}

=head2 mpls_vlan_tag_range

=cut
sub mpls_vlan_tag_range {
    my $self = shift;
    my $mpls_vlan_tag_range = shift;

    if (defined $mpls_vlan_tag_range) {
        $self->{mpls_vlan_tag_range} = $mpls_vlan_tag_range;
    }
    return $self->{mpls_vlan_tag_range};
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

    my $allow = 0;
    foreach my $a (@{$self->acls}) {
        my $ok = $a->vlan_allowed(workgroup_id => $workgroup_id, vlan => $vlan);
        if ($ok == 1) {
            $allow = 1;
            last;
        }
        if ($ok == 0) {
            # Because this rule explictly denies access to this vlan
            # and there could be lower priority rule that may allow
            # this vlan, we break from the for loop. This ensures the
            # higher priority rule is respected.
            $allow = 0;
            last;
        }
    }
    if (!$allow) {
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
    my $args = {
        bandwidth => undef,
        is_admin  => undef,
        @_
    };

    # Normal interfaces are not intended to limit the flow of traffic. Return 0
    # if a user specifies a bandwidth other than 0 on this interface. 
    if (!defined $self->cloud_interconnect_type) {
        return ($args->{bandwidth} == 0) ? 1 : 0;
    }

    if ($self->cloud_interconnect_type eq 'aws-hosted-vinterface') {
        return 1;
    }

    my $validator = new OESS::Cloud::BandwidthValidator(
        config_path => $self->{bandwidth_validator_config},
        interface   => $self
    );
    $validator->load;

    return $validator->is_bandwidth_valid(
        bandwidth => $args->{bandwidth},
        is_admin  => $args->{is_admin}
    );
}

sub bandwidth_requires_approval {
    my $self   = shift;
    my $args = {
        bandwidth => undef,
        is_admin  => undef,
        @_
    };

    # Normal interfaces are not intended to limit the flow of traffic. For this
    # reason we return 1 when bandwidth is not zero on standard interfaces.
    if (!defined $self->cloud_interconnect_type) {
        return ($args->{bandwidth} != 0) ? 1 : 0;
    }

    my $validator = new OESS::Cloud::BandwidthValidator(
        config_path => $self->{bandwidth_validator_config},
        interface   => $self
    );
    $validator->load;

    return $validator->requires_approval(
        bandwidth => $args->{bandwidth},
        is_admin  => $args->{is_admin}
    );
}

=head2 find_available_unit

=cut
sub find_available_unit{
    my $self = shift;
    my %params = @_;

    my $interface_id = $params{'interface_id'};
    my $tag = $params{'tag'};
    my $inner_tag = $params{'inner_tag'};

    if(!defined($inner_tag)){
        return $tag;
    }
    my $used_vrf_units = $self->_execute_query("select unit from vrf_ep where unit >= 5000 and state = 'active' and interface_id= ?",[$interface_id]);
    my $used_circuit_units = $self->_execute_query("select unit from circuit_edge_interface_membership where interface_id = ? and end_epoch = -1 and circuit_id in (select circuit.circuit_id from circuit join circuit_instantiation on circuit.circuit_id = circuit_instantiation.circuit_id and circuit.circuit_state = 'active' and circuit_instantiation.circuit_state = 'active' and circuit_instantiation.end_epoch = -1)",[$interface_id]);
    
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

1;
