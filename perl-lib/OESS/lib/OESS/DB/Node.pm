#!/usr/bin/perl

use strict;
use warnings;

package OESS::DB::Node;

sub fetch{
    my %params = @_;
    my $db = $params{'db'};

    my $status = $params{'status'} || 'active';

    my $node_id = $params{'node_id'};

    my $details;

    my $node = $db->execute_query("select * from node natural join node_instantiation where node_id = ? and node_instantiation.end_epoch = -1", [$node_id]);

    my $res = $db->execute_query("select interface.interface_id from interface natural join interface_instantiation where interface.node_id = ? and interface_instantiation.end_epoch = -1");
    
    my @ints;

    foreach my $int_id (@$res){
        my $int = OESS::Interface->new( db => $db, interface_id => $int_id);
        push(@ints, $int);
    }

    $node->{'interfaces'} = \@ints;
    return $node;
}

sub update{
    


}


sub _update{


}

sub _create{


}

1;
