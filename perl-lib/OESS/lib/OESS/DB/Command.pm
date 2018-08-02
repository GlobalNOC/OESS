#!/usr/bin/perl

use strict;
use warnings;

package OESS::DB::Command;

sub fetch {
    my %params = @_;
    my $db = $params{'db'};
    my $command_id = $params{'command_id'};

    my $cmd = $db->execute_query(
        "select * from command where command_id = ?",
        [$command_id]
    );
    
    if (!defined $cmd || !defined $cmd->[0]) {
        return;
    }

    return $cmd->[0];
}

sub fetch_all {
    my %params = @_;
    my $db = $params{'db'};
    my $type = $params{'type'};

    my $cmds;
    if (defined $type) {
        $cmds = $db->execute_query(
            "select * from command where type=?",
            [$type]
        );
    } else {
        $cmds = $db->execute_query("select * from command", []);
    }
    
    if (!defined $cmds) {
        return [];
    }

    return $cmds;
}

return 1;
