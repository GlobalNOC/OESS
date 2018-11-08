#!/usr/bin/perl

use strict;
use warnings;

package OESS::Workgroup;

use OESS::DB::Workgroup;
use Data::Dumper;

=head2 new

=cut
sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS.Workgroup");

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

    $self->_fetch_from_db();

    return $self;
}

=head2 from_hash

=cut
sub from_hash{
    my $self = shift;
    my $hash = shift;

    $self->{'workgroup_id'} = $hash->{'workgroup_id'};
    $self->{'name'} = $hash->{'name'};
    $self->{'type'} = $hash->{'type'};
    $self->{'max_circuits'} = $hash->{'max_circuits'};
    $self->{'external_id'} = $hash->{'external_id'};
    $self->{'interfaces'} = ();

    foreach my $int (@{$hash->{'interfaces'}}){
        push(@{$self->{'interfaces'}}, OESS::Interface->new(interface_id => $int->{'interface_id'}, db => $self->{'db'}));
    }

}

=head2 to_hash

=cut
sub to_hash{
    my $self = shift;

    my $obj = {};

    $obj->{'workgroup_id'} = $self->workgroup_id();
    $obj->{'name'} = $self->name();
    $obj->{'type'} = $self->type();

    #$obj->{'users'} = ();
    $obj->{'external_id'} = $self->external_id();
    $obj->{'max_circuits'} = $self->max_circuits();    
    $obj->{'interfaces'} = ();;

    foreach my $user (@{$self->users()}){
        push(@{$self->{'users'}}, $user->to_hash());
    }
   
    foreach my $int (@{$self->interfaces()}){
        push(@{$obj->{'interfaces'}}, $int->to_hash());
    }
 
    return $obj;
}

=head2 _fetch_from_db

=cut
sub _fetch_from_db{
    my $self = shift;

    my $wg = OESS::DB::Workgroup::fetch(db => $self->{'db'}, workgroup_id => $self->{'workgroup_id'});
    $self->from_hash($wg);
    
}

=head2 max_circuits

=cut
sub max_circuits{
    my $self = shift;
    return $self->{'max_circuits'};
}

=head2 workgroup_id

=cut
sub workgroup_id{
    my $self = shift;
    my $workgroup_id = shift;

    if(!defined($workgroup_id)){
        return $self->{'workgroup_id'};
    }else{
        $self->{'workgroup_id'} = $workgroup_id;
        return $self->{'workgroup_id'};
    }
}

=head2 name

=cut
sub name{
    my $self = shift;
    my $name = shift;

    if(!defined($name)){
        return $self->{'name'};
    }else{
        $self->{'name'} = $name;
        return $self->{'name'};
    }
}

=head2 users

=cut
sub users{
    my $self = shift;
    return $self->{'users'} || [];
}

=head2 interfaces

=cut
sub interfaces{
    my $self = shift;
    return $self->{'interfaces'} || [];
}

=head2 type

=cut
sub type{
    my $self = shift;
    my $type = shift;

    if(!defined($type)){
        return $self->{'type'};
    }else{
        $self->{'type'} = $type;
        return $self->{'type'};
    }
}

=head2 external_id

=cut
sub external_id{
    my $self = shift;
    return $self->{'external_id'};
}

1;
