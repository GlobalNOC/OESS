#!/usr/bin/perl

use strict;
use warnings;

package OESS::VRF;

use Log::Log4perl;

#link statuses
use constant OESS_LINK_UP       => 1;
use constant OESS_LINK_DOWN     => 0;
use constant OESS_LINK_UNKNOWN  => 2;

use Data::Dumper;
use OESS::DB;

=head1 NAME

OESS::VRF - VRF Interaction Module

=head1 SYNOPSIS

This is a module to provide a simplified object oriented way to connect to
and interact with the OESS VRFs.

Some examples:

    use OESS::VRF;

    my $vrf = OESS::VRF->new( vrf_id => 100, db => new OESS::Database());

    my $vrf_id = $vrf->get_id();

    if (! defined $vrf_id){
        warn "Uh oh, something bad happened: " . $vrf->get_error();
        exit(1);
    }

=cut





=head2 new

    Creates a new OESS::VRF object
    requires an OESS::Database handle
    and either the details from get_vrf_details or a vrf_id

=cut

sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS.VRF");
    
    my %args = (
	details => undef,
	vrf_id => undef,
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

sub from_hash{
    my $self = shift;
    my $hash = shift;

    $self->{'endpoints'} = $hash->{'endpoints'};
    $self->{'name'} = $hash->{'name'};
    $self->{'prefix_limit'} = $hash->{'prefix_limit'};

    
}

sub _fetch_from_db{
    my $self = shift;

    my $hash = OESS::DB::VRF::fetch(db => $self->{'db'}, vrf_id => $self->{'vrf_id'});
    $self->from_hash($hash);

}

sub to_hash{
    my $self = shift;

    my $obj;

    $obj->{'name'} = $self->name();
    $obj->{'vrf_id'} = $self->vrf_id();

    my @endpoints;
    foreach my $endpoint (@{$self->endpoints()}){
        push(@endpoints, $endpoint->to_hash());
    }

    $obj->{'endpoints'} = \@endpoints;
    $obj->{'prefix_limit'} = $self->prefix_limit();
    

    return $obj;
}

sub vrf_id{
    my $self =shift;
    return $self->{'vrf_id'};
}

sub id{
    my $self = shift;
    my $id = shift;

    if(!defined($id)){
        return $self->{'vrf_id'};
    }else{
        $self->{'vrf_id'} = $id;
        return $self->{'vrf_id'};
    }
}

sub endpoints{
    my $self = shift;
    my $eps = shift;

    if(!defined($eps)){
        if(!defined($self->{'endpoints'})){
            return []
        }
        return $self->{'endpoints'};
    }else{
        return [];
    }
}

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



=head2 update_vrf_details

    reload the vrf details from the database to make sure everything 
    is in sync with what should be there

=cut

sub update_vrf_details{
    my $self = shift;
    my %params = @_;

    $self->_load_vrf_details();
}

=head2 error

=cut

sub error{
    my $self = shift;
    my $error = shift;
    if(defined($error)){
        $self->{'error'} = $error;
    }
    return $self->{'error'};
}

sub prefix_limit{
    my $self = shift;
    return $self->{'prefix_limit'};
}

1;
