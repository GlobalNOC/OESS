#!/usr/bin/perl

use strict;
use warnings;

package OESS::DB::Workgroup;

sub fetch{
    my %params = @_;
    my $db = $params{'db'};
    my $workgroup_id = $params{'workgroup_id'};

    my $wg = $db->execute_query("select * from workgroup where workgroup_id = ?",[$workgroup_id]);
    if(!defined($wg) || !defined($wg->[0])){
        return;
    }

    return $wg->[0];
}


1;
