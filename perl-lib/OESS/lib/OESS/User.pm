#!/usr/bin/perl

use strict;
use warnings;

package OESS::User;

use OESS::DB::User;

sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS.User");

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

sub to_hash{
    my $self = shift;

    my $obj = {};

    $obj->{'first_name'} = $self->first_name();
    $obj->{'last_name'} = $self->last_name();
    $obj->{'email'} = $self->email();
    $obj->{'user_id'} = $self->user_id();
    
    my @wgs;
    foreach my $wg (@{$self->workgroups()}){
        push(@wgs, $wg->to_hash());
    }
    
    $obj->{'workgroups'} = \@wgs;
    
    return $obj;
}

sub from_hash{
    my $self = shift;
    my $hash = shift;

    $self->{'user_id'} = $hash->{'user_id'};
    $self->{'first_name'} = $hash->{'first_name'};
    $self->{'last_name'} = $hash->{'last_name'};
    $self->{'email'} = $hash->{'email'};
    $self->{'workgroups'} = $hash->{'workgroups'};
}

sub _fetch_from_db{
    my $self = shift;

    my $user = OESS::DB::User::fetch(db => $self->{'db'}, user_id => $self->{'user_id'});
    $self->from_hash($user);

}

sub first_name{
    my $self = shift;
    return $self->{'first_name'};
}

sub last_name{
    my $self = shift;
    return $self->{'last_name'};

}

sub user_id{
    my $self = shift;
    return $self->{'user_id'};
    
}

sub workgroups{
    my $self = shift;
    return $self->{'workgroups'} || [];
}

sub email{
    my $self = shift;
    return $self->{'email'};
}


sub in_workgroup{
    my $self = shift;
    my $workgroup_id = shift;

    foreach my $wg (@{$self->workgroups()}){
        if($wg->workgroup_id() == $workgroup_id){
            return 1;
        }
    }
    return 0;
}

1;
