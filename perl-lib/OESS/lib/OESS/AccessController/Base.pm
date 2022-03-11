package OESS::AccessController::Base;

use strict;
use warnings;

=head2 new

=cut
sub new {
    my $class = shift;
    my $args  = {
        @_
    };

    return bless $args, $class;
}

=head2 create_user

=cut
sub create_user { return; }

=head2 delete_user

=cut
sub delete_user { return; }

=head2 edit_user

=cut
sub edit_user { return; }

=head2 get_user

=cut
sub get_user { return; }

=head2 get_users

=cut
sub get_users { return; }

=head2 create_workgroup

=cut
sub create_workgroup { return; }

=head2 delete_workgroup

=cut
sub delete_workgroup { return; }

=head2 edit_workgroup

=cut
sub edit_workgroup { return; }

=head2 get_workgroup

=cut
sub get_workgroup { return; }

=head2 get_workgroups

=cut
sub get_workgroups { return; }

=head2 get_workgroup_users

=cut
sub get_workgroup_users { return; }

=head2 add_workgroup_user

=cut
sub add_workgroup_user { return; }

=head2 modify_workgroup_user

=cut
sub modify_workgroup_user { return; }

=head2 remove_workgroup_user

=cut
sub remove_workgroup_user { return; }

return 1;
