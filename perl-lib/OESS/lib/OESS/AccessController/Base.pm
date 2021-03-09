package OESS::AccessController::Base;

use strict;
use warnings;

sub new {
    my $class = shift;
    my $args  = {
        @_
    };

    return bless $args, $class;
}

sub create_user { return; }
sub delete_user { return; }
sub edit_user { return; }
sub get_user { return; }
sub get_users { return; }

sub create_workgroup { return; }
sub delete_workgroup { return; }
sub edit_workgroup { return; }
sub get_workgroup { return; }
sub get_workgroups { return; }
sub get_workgroup_users { return; }

sub add_workgroup_user { return; }
sub modify_workgroup_user { return; }
sub remove_workgroup_user { return; }

return 1;
