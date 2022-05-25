use strict;
use warnings;

package OESS::DB::User;

use Data::Dumper;

use OESS::DB::Circuit;
use OESS::DB::Endpoint;
use OESS::DB::Workgroup;

=head2 fetch

=cut
sub fetch{
    my %params = @_;
    my $db = $params{'db'};
    my $user_id = $params{'user_id'};
    my $username = $params{'username'};
    my $role = $params{'role'};         

    my $user;

    if (defined $user_id) {
        my $q = "
            select remote_auth.auth_name as username, user.family_name as last_name, user.given_names as first_name, user.*
            from user
            join remote_auth on remote_auth.user_id=user.user_id
            where user.user_id = ?
        ";
        $user = $db->execute_query($q, [$user_id]);
    } else {
        my $q = "
            select remote_auth.auth_name as username, user.family_name as last_name, user.given_names as first_name, user.*
            from user
            join remote_auth on remote_auth.user_id=user.user_id
            where remote_auth.auth_name = ?
        ";
        $user = $db->execute_query($q, [$username]);
    }
    if (!defined($user) || !defined($user->[0])){
        return;
    }

    my $admin_query = "
        select exists(
            select type
            from workgroup
            join user_workgroup_membership on workgroup.workgroup_id=user_workgroup_membership.workgroup_id
            where user_workgroup_membership.user_id=? and workgroup.status='active' and type='admin'
        ) as is_admin;
    ";
    my $admin_result = $db->execute_query(
        $admin_query,
        [$user->[0]->{user_id}]
    );
    if (!defined($admin_result) || !defined($admin_result->[0])){
        return;
    }

    # Replace is_admin field with scan for admin workgroups
    $user->[0]->{is_admin} = $admin_result->[0]->{is_admin};
    # Add the role will typically be empty but added for the cases when a
    # workgroup needs to display users.
    if(defined $role){
       $user->[0]{role} = $role;
    }
    return $user->[0];
}

=head2 fetch_v2

    my ($user, $err) = OESS::DB::User::fetch_v2(
        db      => $db,
        user_id => 123
    );
    die $err if defined $err;

=cut
sub fetch_v2 {
    my $args = {
        db       => undef,
        user_id  => undef,
        username => undef,
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};
    return (undef, 'Required argument `user_id` or `username` is missing.') if (!defined $args->{user_id} && !defined $args->{username});

    my $user_records;
    if (defined $args->{user_id}) {
        my $q = "
            select remote_auth.auth_name as username, user.family_name as last_name, user.given_names as first_name, user.user_id, user.email, user.status
            from user
            join remote_auth on remote_auth.user_id=user.user_id
            where user.user_id = ?
        ";
        $user_records = $args->{db}->execute_query($q, [$args->{user_id}]);
    } else {
        my $q = "
            select remote_auth.auth_name as username, user.family_name as last_name, user.given_names as first_name, user.user_id, user.email, user.status
            from user
            join remote_auth on remote_auth.user_id=user.user_id
            where user.user_id=(select user_id from remote_auth where auth_name=?);
        ";
        $user_records = $args->{db}->execute_query($q, [$args->{username}]);
    }
    if (!defined $user_records) {
        return (undef, $args->{db}->get_error);
    }

    my $user = $user_records->[0];
    if (!defined $user) {
        return (undef, "Unable to find user.");
    }
    $user->{usernames} = [];

    foreach my $record (@$user_records) {
        push @{$user->{usernames}}, $record->{username};
        delete $record->{username};
    }
    return ($user, undef);
}

=head2 fetch_all_v2

=cut
sub fetch_all_v2 {
    my $args = {
        db     => undef,
        status => 'active',
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};

    my $q = "
        select user.family_name as last_name, user.given_names as first_name, user.user_id, user.email, user.status, remote_auth.auth_name as username
        from user join remote_auth on user.user_id=remote_auth.user_id
        where status=?
    ";
    my $users = $args->{db}->execute_query($q, [$args->{status}]);
    if (!defined $users) {
        return (undef, $args->{db}->get_error);
    }

    my $result = [];
    my $id     = -1;
    my $u      = {};
    foreach my $user (@$users) {
        if (!$u || $u->{user_id} != $user->{user_id}) {
            $u = $user;
            $u->{usernames} = [$user->{username}];

            push @{$result}, $u;
            delete $user->{username};
        } else {
            push @{$u->{usernames}}, $user->{username};
        }
    }

    return ($result, undef);
}

=head2 fetch_all

    my ($users, $error) = OESS::DB::User::fetch_all(
        db => new OESS::DB
    );

=cut
sub fetch_all{
    my %params = @_;
    my $db = $params{db};

    my $res = $db->execute_query(" SELECT *
                                   FROM user
                                   WHERE status='active'
                                   ORDER BY given_names", []);
    if (!defined $res || !defined $res->[0]) {
        return (undef, $db->get_error);
    }
    
    my @users;

    foreach my $user (@$res) {
        my $data = {
            'given_name' => $user->{given_names},
            'family_name' => $user->{family_name},
            'email' => $user->{'email'},
            'user_id' => $user->{'user_id'},
            'status' => $user->{'status'},
            'is_admin' => $user->{'is_admin'},
            'usernames' => []
        };
        my $username_results = $db->execute_query("SELECT auth_name from remote_auth where user_id=?", [$user->{user_id}]);

        if (!defined $username_results) {
            return (undef, "Internal error fetching usernames");
        }
        foreach my $username (@$username_results){
            push(@{$data->{usernames}}, $username->{'auth_name'});
        }

        my $admin_query = "
            SELECT exists(
                SELECT type
                FROM workgroup
                JOIN user_workgroup_membership on workgroup.workgroup_id=user_workgroup_membership.workgroup_id
                WHERE user_workgroup_membership.user_id=? AND workgroup.status='active' AND type='admin'
            ) as is_admin;
        ";
        my $admin_result = $db->execute_query(
            $admin_query,
            [$user->{'user_id'}]);
        if (!defined $admin_result || !defined $admin_result->[0]) {
            return (undef, $db->get_error);
        }

        $data->{is_admin} = $admin_result->[0]->{is_admin};

        push(@users, $data);

    }
    return (\@users, undef);
}

=head2 add_user

=over

=item db
    Used to denote which database is being used for the transactions

=item given_name
    Denotes the first name of the user to be added to the database

=item family_name
    Denotes the last name of the user to be added to the database

=item email
    Denotes the email address of the user to be added to the database

=item auth_names
    Denotes either a single or list of usernames accreditted to the user

=back

    my ($result, $err) = OESS::DB::User::add_user(db => $db, 
                                                  given_name => $given_name,
                                                  family_name => $family_name,
                                                  email => $email,
                                                  auth_names => $auth_names);

Takes the your input and creates the user object in the database and the associated auth_user associated table.


Returns a tuple of of a the result that is the new user id and and error if defined.

=cut
sub add_user {
   my %params = @_;
   my $db = $params{'db'};
   my $given_name = $params{'given_name'};
   my $family_name = $params{'family_name'};
   my $email = $params{'email'};
   my $auth_names = $params{'auth_names'};

   return (undef, 'Required argument `db` is missing.') if !defined $db;
   return (undef, 'Required argument `given_name` is missing.') if !defined $given_name;
   return (undef, 'Required argument `family_name` is missing.') if !defined $family_name;
   return (undef, 'Required argument `email` is missing.') if !defined $email;
   return (undef, 'Required argument `auth_names` is missing.') if !defined $auth_names;
   
   if ($given_name =~ /^system$/ || $family_name =~ /^system$/) {
       return (undef, "Cannot use system as a username.");
   }

   my $query = "INSERT INTO user (email, given_names, family_name, status) VALUES (?, ?, ?, 'active')";
   my $user_id = $db->execute_query($query,[$email,$given_name,$family_name]);
   if (!defined $user_id) {
       return (undef, "Unable to create new user.");
   }

   if (ref($auth_names) eq 'ARRAY') {
       foreach my $name (@$auth_names) {
           if (length($name) >=1) {
               $query = "INSERT INTO remote_auth (auth_name, user_id) VALUES (?, ?)";
               my $ok = $db->execute_query($query, [$name,$user_id]);
               return (undef, $db->get_error) if (!$ok);
           }
       }
   } else {
       if (length($auth_names) >=1) {
           $query = "INSERT INTO remote_auth (auth_name, user_id) VALUES (?, ?)";
           my $ok = $db->execute_query($query, [$auth_names, $user_id]);
           return (undef, $db->get_error) if (!$ok);
       } else {
           return (undef, "Username should be at least 1 character long");
       }
   }

   return ($user_id, undef);
}

=head2 delete_user

=over

=item db
    Denotes the database that the user is being deleted from

=item user_id
    Denotes the user_id of the user to be deleted.

=back

    my ($result, $error) = OESS::DB::User::delete_user(db => $db,

                                                       user_id => $user_id);
    Takes you input and delete the associate user from the database and associated tables. (user, user_workgroup_management, auth_names)

Returns a tuple of a result code 1 if correct, and and error

=cut
sub delete_user {
    my %params = @_; 
    my $db = $params{db};
    my $user_id = $params{user_id};

    return (undef, 'Required argument `db` is missing.') if !defined $db;
    return (undef, 'Requried argument `user_id` is missing.') if !defined $user_id;

    my $info = OESS::DB::User::fetch(db => $db, user_id => $user_id);

    if (!defined $info) {
        return (undef, "Internal error identifying user with id: $user_id");
    }

    if ($info->{'given_names'} =~ /^system$/i || $info->{'family_name'} =~ /^system$/i) {
       return (undef, "Cannot delete the system user.");
    }

    my $count = $db->execute_query("DELETE FROM user_workgroup_membership WHERE user_id = ?", [$user_id]);
    if (!defined $count) {
        return (undef, "Internal error in delete_user: " . $db->get_error);
    }
    $count = $db->execute_query("DELETE FROM remote_auth WHERE user_id = ?", [$user_id]);
    if (!defined $count) {
        return (undef, "Internal error in delete_user: " . $db->get_error);
    }
    $count = $db->execute_query("update user set status='decom' where user_id=?", [$user_id]);
    if (!defined $count) {
        return (undef, "Internal error in delete_user: " . $db->get_error);
    }

    return (1, undef);
}

=head2 edit_user

=over

=item db
    Denotes the database that is being used for these edits that are being made.

=item user_id
    Denotes the user_id of the user who is being editted.

=item given_name
    Denotes the new first name of the edited user

=item family_name
    Denotes the new last name of the edited user

=item email
    Denotes the new email of the edited user

=item auth_names
    Denotes the new usernames of the edited user

=item status
    Denotes the new status of the edited user

=back

    my ($result, $error) = OESS::DB::User::edit_user(
        db          => $db,
        user_id     => $user_id
        given_name  => $given_name,
        family_name => $family_name,
        email       => $email,
        auth_names  => $auth_names,
        status      => $status
    );

Returns the result of 1 if edit is succesful and an error is neccessary 

=cut
sub edit_user {
    my %params = @_;
    my $db = $params{'db'};

    my $user_id      = $params{'user_id'};
    my $given_name   = $params{'given_name'};
    my $family_name  = $params{'family_name'};
    my $email        = $params{'email'};
    my $auth_names   = $params{'auth_names'};
    my $status       = $params{'status'};

    return (undef, 'Required argument `db` is missing.') if !defined $db;
    return (undef, 'Required arguemnt `user_id` is missing.') if !defined $user_id; 
    return (undef, 'Required argument `given_name` is missing.') if !defined $given_name;
    return (undef, 'Required argument `family_name` is missing.') if !defined $family_name;
    return (undef, 'Required argument `email` is missing.') if !defined $email;
    return (undef, 'Required argument `auth_names` is missing.') if !defined $auth_names;
    return (undef, 'Required argument `status` is missing.') if !defined $status;

    if ($given_name =~ /^system$/ || $family_name =~ /^system$/) {
        return(undef, "User 'system' is reserved.");
    }

    my $query = "UPDATE user SET email = ?, given_names = ?, family_name = ?, status = ? WHERE user_id = ?";

    my $results = $db->execute_query($query, [$email, $given_name, $family_name, $status, $user_id]);
    if (!defined $user_id || $results == 0) {
        return (undef, "Unable to edit user - does this user actually exist?");
    }

    if (ref($auth_names) ne 'ARRAY') {
        $auth_names = [$auth_names];
    }

    my $uindex = {};
    my $usernames = $db->execute_query("select * from remote_auth where user_id=?", [$user_id]);
    if (!defined $usernames) {
        warn "edit_user called on user without any known usernames.";
        $usernames = [];
    }
    foreach my $u (@$usernames) {
        $uindex->{$u->{auth_name}} = $u;
    }

    foreach my $name (@$auth_names) {
        if (defined $uindex->{$name}) {
            delete $uindex->{$name};
            next;
        }

        return (undef, 'auth_names is required to be at least 1 character.') if length $auth_names < 1;

        my $ok = $db->execute_query("INSERT INTO remote_auth (auth_name, user_id) VALUES (?, ?)", [$name, $user_id]);
        return (undef, $db->get_error) if !defined $ok;

        delete $uindex->{$name};
    }

    foreach my $name (keys %$uindex) {
        my $ok = $db->execute_query("delete from remote_auth where auth_name=?", [$name]);
        return (undef, $db->get_error) if !defined $ok;
    }

     return (1,undef)
}

=head2 update

=cut
sub update {
    my $args = {
        db         => undef,
        user_id    => undef,
        first_name => undef,
        last_name  => undef,
        email      => undef,
        status     => 'active',
        @_
    };

    return 'Required argument `db` is missing.' if !defined $args->{db};
    return 'Required arguemnt `user_id` is missing.' if !defined $args->{user_id}; 
    return 'Required argument `first_name` is missing.' if !defined $args->{first_name};
    return 'Required argument `last_name` is missing.' if !defined $args->{last_name};
    return 'Required argument `email` is missing.' if !defined $args->{email};
     
    my $query = "UPDATE user SET email=?, given_names=?, family_name=?, status=? WHERE user_id=?";
    my $results = $args->{db}->execute_query(
        $query,
        [
            $args->{email},
            $args->{first_name},
            $args->{last_name},
            $args->{status},
            $args->{user_id}
        ]
    );
    if (!defined $results) {
        return $args->{db}->get_error;
    }
    return;
}

=head2 add_username

    my ($auth_id, $err) = OESS::DB::User::add_username(
        db       => $db,
        user_id  => 123,
        username => "demo"
    );

=cut
sub add_username {
    my $args = {
        db       => undef,
        user_id  => undef,
        username => undef,
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};
    return (undef, 'Required arguemnt `user_id` is missing.') if !defined $args->{user_id}; 
    return (undef, 'Required arguemnt `username` is missing.') if !defined $args->{username}; 

    my $query = "insert into remote_auth (user_id, auth_name) values (?, ?)";
    my $auth_id = $args->{db}->execute_query(
        $query,
        [
            $args->{user_id},
            $args->{username}
        ]
    );
    if (!defined $auth_id) {
        return (undef, $args->{db}->get_error);
    }
    return ($auth_id, undef);
}

=head2 remove_username

    my $err = OESS::DB::User::remove_username(
        db       => $db,
        username => "demo"
    );

=cut
sub remove_username {
    my $args = {
        db       => undef,
        username => undef,
        @_
    };

    return 'Required argument `db` is missing.' if !defined $args->{db};
    return 'Required arguemnt `username` is missing.' if !defined $args->{username}; 

    my $query = "delete from remote_auth where auth_name=?";
    my $result = $args->{db}->execute_query($query, [$args->{username}]);
    if (!defined $result) {
        return $args->{db}->get_error;
    }
    return;
}

=head2 get_workgroups

=cut
sub get_workgroups {
    my $args = {
        db       => undef,
        user_id  => undef,
        @_
    };

    my $is_admin_query = "
        SELECT workgroup.*, user_workgroup_membership.role as role
        FROM workgroup
        JOIN user_workgroup_membership ON workgroup.workgroup_id=user_workgroup_membership.workgroup_id AND workgroup.type='admin'
        WHERE user_workgroup_membership.user_id=? AND workgroup.status='active'
    ";
    my $is_admin = $args->{db}->execute_query($is_admin_query, [$args->{user_id}]);

    my $query;
    my $values;
    my $datas;
    if (defined $is_admin && defined $is_admin->[0]) {
        $query = "SELECT *, ? as role from workgroup WHERE workgroup.status='active' ORDER BY workgroup.name ASC";
        $values = [];
        $datas = $args->{db}->execute_query($query,[$is_admin->[0]->{role}]);
    } else {
        $query = "
            SELECT workgroup.* , user_workgroup_membership.role as role
            FROM workgroup
            JOIN user_workgroup_membership ON workgroup.workgroup_id=user_workgroup_membership.workgroup_id
            WHERE user_workgroup_membership.user_id=? AND workgroup.status='active'
            ORDER BY workgroup.name ASC
        ";
        $values = [$args->{user_id}];
        $datas = $args->{db}->execute_query($query,$values);
    }

    if (!defined $datas) {
        return (undef, $args->{db}->get_error);
    }
    return ($datas, undef);
}

=head2 find_user_by_remote_auth

=cut
sub find_user_by_remote_auth{
    my %params = @_;
    my $db = $params{'db'};
    my $remote_user = $params{'remote_user'};

    my $user_id = $db->execute_query("select remote_auth.user_id from remote_auth where remote_auth.auth_name = ?",[$remote_user]);
    if(!defined($user_id) || !defined($user_id->[0])){
        return;
    }

    return $user_id->[0];
}

=head2 has_system_access

=over

=item db
    Denotes the database we are checking for access

=item user_id
    Denotes the user_id of the user whose access we are checking

=item username
    Denotes the username of the user whose access we are checking

=item workgroup_id
   Denotes the workgroup_id of the workgroup we checking the users permissions in

=item role
   Denotes the level of access the user needs for a particular action

=back

    my $results = OESS::DB::User::has_system_access(
                                  db           => $db,
                                  user_id      => $user_id,
                                  role        => $role);
    
    OR

    my $results = OESS::DB::User::has_workgroup_access(
                                  db           => $db,
                                  username     => $username,,
                                  role        => $role);
 
has_system_access checks if the user belongs to and admin C<workgroup> and then
checks if their C<role> is the same or higher level than the passed C<role>. If
it is then the User has the proper level of permissions based on the following
C<admin> highest access C<normal> medium access C<read-only> mimum access
Then the function grants permission Otherwise spits out an error.

=cut
sub has_system_access{
    my %params = @_;
    my $db = $params{'db'};
    my $user_id = $params{'user_id'};
    my $username = $params{'username'};
    my $role = $params{'role'};


    return (0, "Required argument 'db' is missing.") if !defined $db;
    return (0, "Required to pass either 'user_id' or 'username'.") if !defined $user_id && !defined $username;
    return (0, "Required argument 'role' is missing.") if !defined $role;
    my $user;
    if (!defined $user_id) {
        $user = OESS::DB::User::fetch(db => $db, username => $username);
    } else {
        $user = OESS::DB::User::fetch(db => $db, user_id =>$user_id);
    }
    
    if (!defined $user || $user->{'status'} eq 'decom'){
        return (0 ,"Invalid or decommissioned user specified.");
    }
    if ($user->{'is_admin'} == 1) {
        my ($workgroups, $wg_err) = OESS::DB::User::get_workgroups(db => $db, user_id => $user->{user_id});
        
        my $read_access = 1;
        my $normal_access = 0;
        my $admin_access = 0;
        
        foreach my $workgroup (@$workgroups){
          if ( $workgroup->{type} ne 'admin'){
              next;
          }
          my $role_result = $db->execute_query("SELECT role FROM user_workgroup_membership WHERE user_id = ? AND workgroup_id = ?",
                                                      [$user->{user_id}, $workgroup->{'workgroup_id'}]);
          my $group_role = $role_result->[0]->{role} || 'dud';
          
          if ($group_role eq 'normal') {
              $normal_access = 1;
          }
          if ($group_role eq 'admin') {
              $normal_access = 1;
              $admin_access = 1;
          }
        }
        if ($role eq 'read-only' && $read_access == 1) {
           return (1, undef);
        } elsif ($role eq 'normal' && $normal_access == 1) {
           return (1, undef);
        } elsif ($role eq 'admin' && $admin_access ==1)  {
           return (1, undef);
        } else {
           return (0, "User $user->{'username'} does not have the proper level of access.");
        }
    } else {
       return (0, "User $user->{'username'} does not have system admin privileges.");
    }
}

=head2 has_workgroup_access

=over

=item db
    Denotes the database we are checking for access

=item user_id
    Denotes the user_id of the user whose access we are checking

=item username
    Denotes the username of the user whose access we are checking

=item workgroup_id
   Denotes the workgroup_id of the workgroup we checking the users permissions in

=item role
   Denotes the level of access the user needs for a particular action

=back

    my $results = OESS::DB::User::has_workgroup_access(
                                  db           => $db,
                                  user_id      => $user_id,
                                  workgroup_id => $workgroup_id,
                                  $role        => $role);
    
    OR

    my $results = OESS::DB::User::has_workgroup_access(
                                  db           => $db,
                                  user_id      => $user_id,
                                  workgroup_id => $workgroup_id,
                                  $role        => $role);

has_workgroup_access checks if a specified user's C<role> found in C<user_workgroup_membership>
identified by the C<workgroup_id> and C<user_id> or C<username> matches the passed
C<role> and grants access based on that criteria. The roles are ranked as follows
C<admin> highest access, C<normal> middle access, C<read-only> minimum access. 
It will also grant access to system admins of an appropriate level.

=cut
sub has_workgroup_access {
    my %params = @_;
    my $db = $params{'db'};
    my $user_id = $params{'user_id'};
    my $username = $params{'username'};
    my $workgroup_id = $params{'workgroup_id'};
    my $role = $params{'role'};

    return (0, "Required argument 'db' is missing.") if !defined $db;
    return (0, "Required to pass either 'user_id' or 'username'.") if !defined $user_id && !defined $username;
    return (0, "Required argument 'workgroup_id' is missing.") if !defined $workgroup_id;
    return (0, "Required argument 'role' is missing.") if !defined $role;
    my $user;
    if (!defined $user_id) {
        $user = OESS::DB::User::fetch(db => $db, username => $username);
    } else {
        $user = OESS::DB::User::fetch(db => $db, user_id => $user_id);
    }
    
    if (!defined $user || $user->{'status'} eq 'decom') {
        return (0, "Invalid or decommissioned user specified.");
    }
    
    my $workgroup = OESS::DB::Workgroup::fetch(db => $db, workgroup_id => $workgroup_id);

    if (!defined $workgroup || $workgroup->{'status'} eq 'decom') {
        return (0, "Invalid or decommissioned workgroup specified." );
    }
    if ($workgroup->{'type'} eq 'admin') {
        my ($high_admin, $ha_err) = has_system_access(db => $db, user_id => $user->{user_id}, role => $role);
        if (!defined $ha_err) {
            return (1, undef);
        } else {
            return (0, $ha_err);
        }
    } else {
       my $user_wg_role = $db->execute_query("SELECT role from user_workgroup_membership WHERE user_id = ? and workgroup_id = ?",
                                             [$user->{user_id}, $workgroup_id])->[0]->{'role'};
       my $read_access = 0;
       my $normal_access = 0;
       my $admin_access = 0;
       if(defined $user_wg_role) {
           $read_access = 1;
           if ($user_wg_role eq 'normal') {
               $normal_access = 1;
           }
           if ($user_wg_role eq 'admin') {
               $normal_access = 1;
               $admin_access = 1;        
           }
       }
       my $is_sys_admin;
       my $adminErr;
       if ($role eq 'read-only') {
           ($is_sys_admin, $adminErr) = has_system_access(db =>$db, user_id => $user->{user_id}, role => 'read-only');
       } else {
           ($is_sys_admin, $adminErr) = has_system_access(db => $db, user_id => $user->{user_id}, role => 'normal');
       }
       if (!defined $adminErr) {
           $read_access = 1;
           $normal_access = 1;
           $admin_access = 1;
       }
        if ($role eq 'read-only' && $read_access == 1) {
            return (1, undef);
        } elsif ($role eq 'normal' && $normal_access == 1) {
            return (1, undef);
        } elsif ($role eq 'admin' && $admin_access == 1) {
            return (1, undef);
        } else {
            return (0, "User $user->{'username'} does not have the proper access permissions");
            
        }
    }
}

=head2 has_circuit_permission

=over

=item db
    Denotes the database we are checking for access

=item user_id
    Denotes the user_id of the user whose access we are checking

=item username
    Denotes the username of the user whose access we are checking

=item circuit_id
   Denotes the circuit_id of the circuit we checking the users permissions in

=item permission
   Denotes the level of access the user needs for a particular action. May be 'create', 'read', 'update', or 'delete'.

=back

    my $results = OESS::DB::User::has_circuit_permission(
        db         => $db,
        user_id    => $user_id,
        circuit_id => $circuit_id,
        permission => 'update'
    );

has_circuit_permission checks if the specified user has appropriate
permission for that circuit. Permissions are determined by looking up
circuit details, pairing those details against the user's workgroups,
and then fetching the user's role within those workgroups.

=cut
sub has_circuit_permission {
    my %params = @_;
    my $db         = $params{'db'};
    my $user_id    = $params{'user_id'};
    my $username   = $params{'username'};
    my $circuit_id = $params{'circuit_id'};
    my $permission = $params{'permission'};

    return (0, "Required argument 'db' is missing.") if !defined $db;
    return (0, "Required to pass either 'user_id' or 'username'.") if !defined $user_id && !defined $username;
    return (0, "Required argument 'circuit_id' is missing.") if !defined $circuit_id;
    return (0, "Required argument 'permission' is missing.") if !defined $permission;

    my $permissions = {
        create => undef,
        read   => undef,
        update => undef,
        delete => undef,
    };
    if (!exists $permissions->{$permission}) {
        return (0, "Required argument 'permission' must be 'create', 'read', 'update', or 'delete'.");
    }

    my $user;
    if (!defined $user_id) {
        $user = OESS::DB::User::fetch(db => $db, username => $username);
    } else {
        $user = OESS::DB::User::fetch(db => $db, user_id => $user_id);
    }
    if (!defined $user || $user->{'status'} eq 'decom'){
        return (0, "Invalid or decommissioned user specified.");
    }

    my $circuit = OESS::DB::Circuit::fetch_circuit(db => $db, circuit_id => $circuit_id)->[0];
    if (!defined $circuit || $circuit->{'state'} eq 'decom') {
        return (0, "Invalid or decommissioned circuit specified.");
    }

    # Permissions for admin users
    my $admin_results = $db->execute_query(
        "SELECT role
         FROM user_workgroup_membership JOIN workgroup
           ON user_workgroup_membership.workgroup_id=workgroup.workgroup_id
         WHERE workgroup.type='admin' AND user_workgroup_membership.user_id=?",
        [$user->{user_id}]
    );
    $admin_results = [] if !defined $admin_results;
    foreach my $result (@$admin_results) {
        if ($result->{role} eq 'admin' || $result->{role} eq 'normal') {
            $permissions->{create} = 1;
            $permissions->{read}   = 1;
            $permissions->{update} = 1;
            $permissions->{delete} = 1;
        } else {
            $permissions->{read}   = 1;
        }
    }

    # Permissions for users in the circuit owner's workgroup
    my $workgroup_results = $db->execute_query(
        "SELECT role
         FROM user_workgroup_membership
         WHERE user_workgroup_membership.user_id=? and user_workgroup_membership.workgroup_id=?",
        [$user->{user_id}, $circuit->{workgroup_id}]
    );
    $workgroup_results = [] if !defined $workgroup_results;
    foreach my $result (@$workgroup_results) {
        if ($result->{role} eq 'admin' || $result->{role} eq 'normal') {
            $permissions->{create} = 1;
            $permissions->{read}   = 1;
            $permissions->{update} = 1;
            $permissions->{delete} = 1;
        } else {
            $permissions->{read}   = 1;
        }
    }

    # Permissions for users in the circuit's interfaces' owner workgroups
    my $interface_results = $db->execute_query(
        "SELECT user_workgroup_membership.role
         FROM user_workgroup_membership JOIN interface
           ON user_workgroup_membership.workgroup_id=interface.workgroup_id
         JOIN circuit_edge_interface_membership AS circuit_ep
           ON circuit_ep.interface_id=interface.interface_id AND circuit_ep.end_epoch=-1
         WHERE user_workgroup_membership.user_id=? AND circuit_ep.circuit_id=?
        ",
        [$user->{user_id}, $circuit->{circuit_id}]
    );
    $interface_results = [] if !defined $interface_results;
    foreach my $result (@$interface_results) {
        if ($result->{role} eq 'admin' || $result->{role} eq 'normal') {
            $permissions->{read}   = 1;
            # TODO Ideally interface owners may remove endpoints from
            # any circuit which terminate on their interfaces,
            # although is not supported at this time.
            #
            # $permissions->{update} = 1;
        } else {
            $permissions->{read}   = 1;
        }
    }

    if (!$permissions->{$permission}) {
        return (0, "User $user->{username} doesn't have $permission permission for circuit $circuit_id.");
    }
    return (1, undef);
}



1;
