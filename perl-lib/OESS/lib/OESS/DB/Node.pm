#!/usr/bin/perl

use strict;
use warnings;

package OESS::DB::Node;

use constant MAX_VLAN_TAG => 4096;
use constant MIN_VLAN_TAG => 1;
use constant UNTAGGED => -1;

=head2 fetch

=cut
sub fetch{
    my %params = @_;
    my $db = $params{'db'};

    my $status = $params{'status'} || 'active';

    my $node_id = $params{'node_id'};
    my $node_name = $params{'name'};
    my $details;

    my $node;
    
    if (defined $node_id) {
        $node = $db->execute_query("select * from node natural join node_instantiation where node_id = ? and node_instantiation.end_epoch = -1", [$node_id]);   
    } else {
        $node = $db->execute_query("SELECT * FROM node NATUARAL JOIN node_instantiation WHERE name = ? and node_instantiation.end_epoch = -1", [$node_name]);
    }
    
    return if(!defined($node) || !defined($node->[0]));

    $node = $node->[0];

    my $res = $db->execute_query("select interface.interface_id from interface natural join interface_instantiation where interface.node_id = ? and interface_instantiation.end_epoch = -1",[$node->{'node_id'}]);
    
    my @ints;

    foreach my $int_id (@$res){
        my $int = OESS::Interface->new( db => $db, interface_id => $int_id);                                                                                                                                        
        push(@ints, $int);
    }

    $node->{'interfaces'} = \@ints;
    return $node;
}

=head2 get_node_interfaces

=cut
sub get_node_interfaces{
    my $db = shift;
    my $node_id = shift;

    my $interfaces = $db->execute_query("select * from interface where node_id = ?",[$node_id]);

    my @ints;
    foreach my $interface (@$interfaces){
        push(@ints, OESS::Interface->new(db => $db, interface_id => $interface->{'interface_id'}));
    }

    return \@ints;
}

=head2 get_allowed_vlans

=cut
sub get_allowed_vlans {
    my $args = {
        db           => undef,
        node_id      => undef,
        interface_id => undef,
        @_
    };

    my $params = [];
    my $values = [];

    if (defined $args->{node_id}) {
        push @$params, "node.node_id=?";
        push @$values, $args->{node_id};
    }
    if (defined $args->{interface_id}) {
        push @$params, "interface.interface_id=?";
        push @$values, $args->{interface_id};
    }

    my $where = (@$params > 0) ? 'where ' . join(' and ', @$params) : '';

    my $q = "
        SELECT node.vlan_tag_range
        FROM node
        JOIN interface ON node.node_id=interface.node_id
        $where
        GROUP BY node.node_id
    ";

    my $results = $args->{db}->execute_query($q, $values);
    if (!defined $results) {
        return (undef, $args->{db}->get_error);
    }

    my $string = $results->[0]->{vlan_tag_range};
    my $tags = _process_tag_string($string);

    return $tags;
}

=head2 _process_tag_string

=cut
sub _process_tag_string{
    my $string        = shift;
    my $oscars_format = shift || 0;
    my $MIN_VLAN_TAG  = ($oscars_format) ? 0 : MIN_VLAN_TAG;

    if(!defined($string)){
        return;
    }
    if($oscars_format){
        $string =~ s/^-1/0/g;
        $string =~ s/,-1/0/g;
    }

    if ($string eq '-1') {
        return []
    }

    my @split = split(/,/, $string);
    my @tags;

    foreach my $element (@split){
        if ($element =~ /^(\d+)-(\d+)$/){

            my $start = $1;
            my $end   = $2;

            if (($start < MIN_VLAN_TAG && $start != UNTAGGED)|| $end > MAX_VLAN_TAG){
                return;
            }

            foreach my $tag_number ($start .. $end){
                push(@tags, $tag_number);
            }

        }elsif ($element =~ /^(\-?\d+)$/){
            my $tag_number = $1;
            if (($tag_number < MIN_VLAN_TAG && $tag_number != UNTAGGED) || $tag_number > MAX_VLAN_TAG){
                return;
            }
            push (@tags, $1);

        }else{
            return;
        }
    }

    return \@tags;
}

1;
