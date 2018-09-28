#!/usr/bin/perl

use strict;
use warnings;

package OESS::ACL;

use OESS::DB::Interface;

=head2 new

=cut
sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS.ACL");

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

    $self->_fetch_from_db();

    return $self;
}

=head2 from_hash

=cut
sub from_hash{
    my $self = shift;
    my $hash = shift;
 
    my @acls;
    foreach my $acl (@$hash){

        push(@acls, { workgroup_id => $acl->{'workgroup_id'},
                      entity_id => $acl->{'entity_id'},
                      allow_deny => $acl->{'allow_deny'},
                      eval_position => $acl->{'eval_position'},
                      start => $acl->{'vlan_start'},
                      end => $acl->{'vlan_end'} });

    }

    my @sorted_acls = sort { $a->{'eval_position'} cmp $b->{'eval_position'} } @acls;

    $self->{'acls'} = \@sorted_acls;
}

=head2 to_hash

=cut
sub to_hash{
    my $self = shift;
    
    my $obj = {};
    
    $obj->{'acls'} = $self->{'acls'};
    $obj->{'interface_id'} = $self->{'interface_id'};
    

    return $obj;
}

=head2 _fetch_from_db

=cut
sub _fetch_from_db{
    my $self = shift;

    my $acls = OESS::DB::Interface::get_acls( db => $self->{'db'}, interface_id => $self->{'interface_id'} );
    $self->from_hash($acls);
}

=head2 acls

=cut
sub acls{
    my $self = shift;
    return $self->{'acls'};
}


=head2 vlan_allowed

=cut
sub vlan_allowed{
    my $self = shift;
    my %params = @_;
    
    my $workgroup_id = $params{'workgroup_id'};
    my $vlan = $params{'vlan'};

    foreach my $acl (@{$self->{'acls'}}){
        if(   (defined($acl->{'end'}) && $acl->{'start'} <= $vlan && $acl->{'end'} >= $vlan)
           || ((!defined($acl->{'end'})) && $acl->{'start'} == $vlan) ){
            if(!defined($acl->{'workgroup_id'}) || $acl->{'workgroup_id'} == $workgroup_id){
                if($acl->{'allow_deny'} eq 'allow'){
                    return 1;
                }else{
                    return 0;
                }
            }
        }
    }
    
    #default deny
    return 0;
}

1;
