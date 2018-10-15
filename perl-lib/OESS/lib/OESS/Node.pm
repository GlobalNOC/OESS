#!/usr/bin/perl

use strict;
use warnings;

package OESS::Node;

use OESS::DB::Node;

=head2 new

=cut
sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS.Node");

    my %args = (
        node_id => undef,
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

    $self->{'node_id'} = $hash->{'node_id'};
    $self->{'name'} = $hash->{'name'};
    $self->{'latitude'} = $hash->{'latitude'};
    $self->{'longitude'} = $hash->{'longitude'};
    
}

=head2 to_hash

=cut
sub to_hash{
    my $self = shift;
    my $obj = { node_id => $self->{'node_id'},
                name => $self->{'name'},
                latitude => $self->{'latitude'},
                longitude => $self->{'longitude'}};

    return $obj;
}

=head2 _fetch_from_db

=cut
sub _fetch_from_db{
    my $self = shift;
    my $db = $self->{'db'};
    my $hash = OESS::DB::Node::fetch(db => $db, node_id => $self->{'node_id'});
    $self->from_hash($hash);
}

=head2 node_id

=cut
sub node_id{
    my $self = shift;
    return $self->{'node_id'};
}

=head2 name

=cut
sub name{
    my $self = shift;
    return $self->{'name'};
}

=head2 interfaces

=cut
sub interfaces{
    my $self = shift;
    my $interfaces = shift;
    
    if(defined($interfaces)){

    }else{
       
        if(!defined($self->{'interfaces'})){
            my $interfaces = OESS::DB::Node::get_interfaces(db => $self->{'db'}, node_id => $self->{'node_id'});
            $self->{'interfaces'} = $interfaces;
        }
        
        return $self->{'interfaces'};
    }
}

1;
