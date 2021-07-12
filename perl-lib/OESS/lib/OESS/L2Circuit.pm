#!/usr/bin/perl

use strict;
use warnings;

package OESS::L2Circuit;

use Data::Dumper;
use DateTime;
use Graph::Directed;
use Log::Log4perl;

use OESS::DB;
use OESS::DB::Circuit;
use OESS::DB::Workgroup;
use OESS::Path;
use OESS::User;

#link statuses
use constant OESS_LINK_UP       => 1;
use constant OESS_LINK_DOWN     => 0;
use constant OESS_LINK_UNKNOWN  => 2;


=head1 OESS::L2Circuit

    use OESS::L2Circuit;

This is a module to provide a simplified object oriented way to
connect to and interact with the OESS Circuits.

=cut

=head2 new

    my $ckt = OESS::L2Circuit->new(
        db         => new OESS::DB,
        circuit_id => 100
    );

    # or

    $ckt = OESS::L2Circuit->new(
        model = {
            name => '',
            description => ''
            remote_url => '',
            remote_requester => '',
            external_identifier => '',
            provision_time => '',
            remove_time => '',
            user_id => '',
            workgroup_id => '',
        }
    );

    if (!defined $ckt) {
        warn $circuit->get_error;
    }

Creates a new OESS::L2Circuit object requires an OESS::Database handle
and either the details from get_circuit_details or a circuit_id.

=cut
sub new {
    my $that  = shift;
    my $class = ref($that) || $that;

    my $self = {
        circuit_id   => undef,
        db           => undef,
        model        => undef,
        logger       => Log::Log4perl->get_logger('OESS.L2Circuit'),
        just_display => 0,
        @_
    };
    bless $self, $class;

    if (!defined $self->{db}) {
        $self->{'logger'}->debug('Optional argument `db` is missing. Cannot save object to database.');
    }

    if (defined $self->{db} && defined $self->{circuit_id}) {
        eval {
            $self->{model} = $self->_load_circuit_details();
        };
        if ($@) {
            $self->{logger}->error("Couldn't load L2Circuit: $@");
            return;
        }
    }

    if (!defined $self->{model}) {
        $self->{logger}->debug('Optional argument `model` is missing.');
        $self->{logger}->error("Couldn't load L2Circuit from db or model.");
        return;
    }

    $self->_process_circuit_details($self->{model});

    # This is provided for a code path in MPLS::FWDCTL. Ideally this
    # would be removed in the future.
    $self->{type} = 'mpls';

    return $self;
}

=head2 circuit_id

returns the id of the circuit

=cut
sub circuit_id {
    my $self = shift;
    return $self->{'circuit_id'};
}

=head2 name

=cut
sub name{
    my $self = shift;
    my $name = shift;
    if (defined $name) {
        $self->{'name'} = $name;
    }
    return $self->{'name'};
}

=head2 description

=cut
sub description{
    my $self = shift;
    my $description = shift;
    if (defined $description) {
        $self->{'description'} = $description;
    }
    return $self->{'description'};
}

=head2 remote_url

=cut
sub remote_url{
    my $self = shift;
    my $remote_url = shift;
    if (defined $remote_url) {
        $self->{'remote_url'} = $remote_url;
    }
    return $self->{'remote_url'};
}

=head2 remote_requester

=cut
sub remote_requester{
    my $self = shift;
    my $remote_requester = shift;
    if (defined $remote_requester) {
        $self->{'remote_requester'} = $remote_requester;
    }
    return $self->{'remote_requester'};
}

=head2 external_identifier

=cut
sub external_identifier{
    my $self = shift;
    my $external_identifier = shift;
    if (defined $external_identifier) {
        $self->{'external_identifier'} = $external_identifier;
    }
    return $self->{'external_identifier'};
}

=head2 provision_time

=cut
sub provision_time{
    my $self = shift;
    my $provision_time = shift;
    if (defined $provision_time) {
        $self->{'provision_time'} = $provision_time;
    }
    return $self->{'provision_time'};
}

=head2 remove_time

=cut
sub remove_time{
    my $self = shift;
    my $remove_time = shift;
    if (defined $remove_time) {
        $self->{'remove_time'} = $remove_time;
    }
    return $self->{'remove_time'};
}

=head2 user_id

=cut
sub user_id{
    my $self = shift;
    my $user_id = shift;
    if (defined $user_id) {
        $self->{'user_id'} = $user_id;
    }
    return $self->{'user_id'};
}

=head2 reason

=cut
sub reason{
    my $self = shift;
    my $reason = shift;
    if (defined $reason) {
        $self->{'reason'} = $reason;
    }
    return $self->{'reason'};
}

=head2 state

=cut
sub state{
    my $self = shift;
    my $state = shift;
    if (defined $state) {
        $self->{'state'} = $state;
    }
    return $self->{'state'};
}

=head2 load_users

    my $err = $vrf->load_users;

load_users populates C<created_by> and C<last_modified_by> with
C<OESS::User> objects.

=cut
sub load_users {
    my $self = shift;
    my $err = undef;

    # TODO User object shouldn't load workgroup info. Way too much
    # info there.

    $self->{created_by} = new OESS::User(
        db => $self->{db},
        user_id => $self->{created_by_id}
    );

    $self->{last_modified_by} = new OESS::User(
        db => $self->{db},
        user_id => $self->{last_modified_by_id}
    );
    return $err;
}

=head2 add_path

=cut
sub add_path {
    my $self = shift;
    my $path = shift;

    push @{$self->{paths}}, $path;
}

=head2 path

=cut
sub path {
    my $self = shift;
    my $args = {
        type => undef,
        @_
    };

    return if (!defined $self->{paths});

    foreach my $path (@{$self->{paths}}) {
        if (defined $args->{type}) {
            return $path if ($path->type eq $args->{type});
        }
        else {
            if ($path->{state} eq 'active') {
                return $path;
            }
        }
    }

    return;
}

=head2 load_paths

=cut
sub load_paths {
    my $self = shift;

    my ($path_datas, $error) = OESS::DB::Path::fetch_all(
        db => $self->{db},
        circuit_id => $self->{circuit_id}
    );
    if (defined $error) {
        $self->{logger}->error($error);
        return;
    }

    $self->{paths} = [];
    foreach my $data (@$path_datas) {
        my $path = new OESS::Path(db => $self->{db}, model => $data);
        $path->load_links;
        push @{$self->{paths}}, $path;
    }

    return 1;
}

=head2 paths

=cut
sub paths {
    my $self = shift;
    return $self->{paths};
}

=head2 workgroup_id

    my $workgroup_id = $vrf->workgroup_id;

or

    $vrf->workgroup_id($workgroup_id);

=cut
sub workgroup_id {
    my $self = shift;
    my $workgroup_id = shift;

    if (defined $workgroup_id) {
        $self->{workgroup_id} = $workgroup_id;
    }
    return $self->{workgroup_id};
}

=head2 workgroup

    my $workgroup = $vrf->workgroup;

or

    $vrf->workgroup(new OESS::Workgroup(db => $db, workgroup_id => $id));

=cut
sub workgroup {
    my $self = shift;
    my $workgroup = shift;

    if (defined $workgroup) {
        $self->{workgroup} = $workgroup;
        $self->{workgroup_id} = $workgroup->{workgroup_id};
    }
    return $self->{workgroup};
}

=head2 load_workgroup

    my $err = $vrf->load_workgroup;

load_workgroup populates C<< $self->{workgroup} >> with an
C<OESS::Workgroup> object.

=cut
sub load_workgroup {
    my $self = shift;

    if (!defined $self->{db}) {
        return "Unable to read Workgroup from database; Handle is missing";
    }

    $self->{workgroup} = new OESS::Workgroup(db => $self->{db}, workgroup_id => $self->{workgroup_id});
    return;
}

=head2 to_hash

=cut
sub to_hash {
    my $self = shift;

    my $hash = {
        remote_requester => $self->{remote_requester},
        external_identifier => $self->{external_identifier},
        state => $self->{state},
        remote_url => $self->{remote_url},
        created_on => $self->{created_on},
        circuit_id => $self->{circuit_id},
        workgroup_id => $self->{workgroup_id},
        created_on_epoch => $self->{created_on_epoch},
        last_modified_on_epoch => $self->{last_modified_on_epoch},
        name => $self->{name},
        reason => $self->{reason},
        description => $self->{description},
        user_id => $self->{user_id},
        last_modified_on => $self->{last_modified_on},
        provision_time => '',
        remove_time => ''
    };

    if (defined $self->{created_by}) {
        $hash->{created_by} = $self->{created_by}->to_hash;
    }
    if (defined $self->{last_modified_by}) {
        $hash->{last_modified_by} = $self->{last_modified_by}->to_hash;
    }

    if (defined $self->{workgroup}) {
        $hash->{workgroup} = $self->{workgroup}->to_hash;
    }

    if (defined $self->{paths}) {
        $hash->{paths} = [];
        foreach my $path (@{$self->{paths}}) {
            push @{$hash->{paths}}, $path->to_hash;
        }
    }

    if (defined $self->{endpoints}) {
        $hash->{endpoints} = [];
        foreach my $ep (@{$self->{endpoints}}) {
            push @{$hash->{endpoints}}, $ep->to_hash;
        }
    }

    return $hash;
}

sub _load_circuit_details{
    my $self = shift;
    $self->{'logger'}->debug("Loading Circuit data for circuit: " . $self->{'circuit_id'});

    my $datas = OESS::DB::Circuit::fetch_circuit(
        db => $self->{db},
        circuit_id => $self->{circuit_id}
    );
    if (!defined $datas || @$datas == 0) {
        $self->{logger}->error("No data for circuit $self->{circuit_id}.");
        return;
    }

    my $data = $datas->[0];
    my $first_data = OESS::DB::Circuit::fetch_circuit(
        db => $self->{db},
        circuit_id => $self->{circuit_id},
        first => 1
    );

    $data->{last_modified_by_id} = $data->{user_id};
    $data->{last_modified_on_epoch} = $data->{start_epoch};
    $data->{last_modified_on} = DateTime->from_epoch(
        epoch => $data->{'last_modified_on_epoch'}
    )->strftime('%m/%d/%Y %H:%M:%S');

    $data->{created_by_id} = $first_data->[0]->{user_id} || $data->{user_id};
    $data->{created_on_epoch} = $first_data->[0]->{start_epoch} || $data->{start_epoch};
    $data->{created_on} = DateTime->from_epoch(
        epoch => $data->{'created_on_epoch'}
    )->strftime('%m/%d/%Y %H:%M:%S');

    delete $data->{end_epoch};
    delete $data->{start_epoch};

    return $data;
}

sub _process_circuit_details{
    my $self = shift;
    my $hash = shift;

    $self->{remote_requester} = $hash->{remote_requester};

    $self->{external_identifier} = $hash->{external_identifier};
    $self->{state} = $hash->{state};
    $self->{remote_url} = $hash->{remote_url};

    $self->{circuit_id} = $hash->{circuit_id};
    $self->{workgroup_id} = $hash->{workgroup_id};

    $self->{name} = $hash->{name};
    $self->{reason} = $hash->{reason};
    $self->{description} = $hash->{description};
    $self->{user_id} = $hash->{user_id};

    # These extra bits need to be looked up separately to find the
    # first circuit instantiation.
    $self->{created_by_id} = $hash->{created_by_id};
    $self->{created_on} = $hash->{created_on};
    $self->{created_on_epoch} = $hash->{created_on_epoch};

    $self->{last_modified_by_id} = $hash->{user_id};
    if (defined $hash->{start_epoch}) {
        $self->{last_modified_on} = DateTime->from_epoch(epoch => $hash->{start_epoch})->strftime('%m/%d/%Y %H:%M:%S');
        $self->{last_modified_on_epoch} = $hash->{start_epoch};
    }

    # TODO Load primary links
    $self->{'has_primary_path'} = (defined $hash->{'links'} && @{$hash->{'links'}} > 0) ? 1 : 0;

    # TODO Load tertiary links
    $self->{'has_tertiary_path'} = (defined $hash->{'tertiary_links'} && @{$hash->{'tertiary_links'}} > 0) ? 1 : 0;

    # TODO Load endpoints
    if (defined $hash->{endpoints}) {
        $self->{endpoints} = [];
        foreach my $ep (@{$hash->{endpoints}}) {
            push(@{$self->{endpoints}}, new OESS::Endpoint(db => $self->{db}, model => $ep));
        }
    }

    # foreach my $endpoint (@{$hash->{'endpoints'}}){
    #     if (!defined $self->{endpoints}) {
    #         $self->{endpoints} = [];
    #     }

    #     if ($endpoint->{'local'} == 0) {
    #         $self->{'interdomain'} = 1;
    #     }

    #     my $entity = OESS::Entity->new(
    #         db => $self->{'db'},
    #         interface_id => $endpoint->{'interface_id'},
    #         vlan => $endpoint->{'tag'}
    #     );
    #     if (!defined $entity) {
    #         next;
    #     }

    #     push @{$self->{endpoints}}, $entity;
    #     # $endpoint->{'entity'} = $entity->to_hash();
    # }
}

sub _create_graph{
    my $self = shift;

    $self->{'logger'}->debug("Creating graphs for circuit " . $self->{'circuit_id'});
    my @links = @{$self->{model}->{'links'}};

    $self->{'logger'}->debug("Creating a Graph for the primary path for the circuit " . $self->{'circuit_id'});

    my $p = Graph::Undirected->new;
    foreach my $link (@links){
        $p->add_vertex($link->{'node_z'});
        $p->add_vertex($link->{'node_a'});
        $p->add_edge($link->{'node_a'},$link->{'node_z'});
    }

    $self->{'graph'}->{'primary'} = $p;

    if ($self->has_backup_path()) {
        $self->{'logger'}->debug("Creating a Graph for the backup path for the circuit " . $self->{'circuit_id'});

        @links = @{$self->{model}->{'backup_links'}};
        my $b = Graph::Undirected->new;

        foreach my $link (@links){
            $b->add_vertex($link->{'node_z'});
            $b->add_vertex($link->{'node_a'});
            $b->add_edge($link->{'node_a'},$link->{'node_z'});
        }

        $self->{'graph'}->{'backup'} = $b;
    }
}

=head2 generate_clr

generate_clr creates a circuit layout record for this circuit.

=cut
sub generate_clr{
    my $self = shift;

    my $clr = "";
    $clr .= "Circuit: $self->{model}->{'name'}\n";
    $clr .= "Created by: $self->{model}->{'created_by'}->{'given_names'} $self->{model}->{'created_by'}->{'family_name'} at $self->{model}->{'created_on'} for workgroup $self->{model}->{'workgroup'}->{'name'}\n";
    $clr .= "Last Modified By: $self->{model}->{'last_modified_by'}->{'given_names'} $self->{model}->{'last_modified_by'}->{'family_name'} at $self->{model}->{'last_edited'}\n\n";
    $clr .= "Endpoints: \n";

    my $active = $self->get_active_path();
    if ($active eq 'tertiary') {
        $active = 'default';
    }
    $clr .= "\nActive Path:\n";
    $clr .= $active . "\n";

    if ($#{$self->get_path( path => 'primary')} > -1){
        $clr .= "\nPrimary Path:\n";
        foreach my $path (@{$self->get_path( path => 'primary' )}){
            $clr .= "  $path->{'name'}\n";
        }
    }

    # In mpls land the tertiary path is the auto-selected
    # path. Displaying 'Default' to users for less confusion.
    if ($#{$self->get_path( path => 'tertiary')} > -1){
        $clr .= "\nDefault Path:\n";
        foreach my $path (@{$self->get_path( path => 'tertiary' )}){
            $clr .= "  $path->{'name'}\n";
        }
    }

    return $clr;
}

=head2 endpoints

=cut
sub endpoints{
    my $self = shift;
    return $self->{'endpoints'};
}

=head2 has_primary_path

=cut
sub has_primary_path{
    my $self = shift;
    return $self->{'has_primary_path'};
}

=head2 has_tertiary_path

=cut
sub has_tertiary_path{
    my $self = shift;
    return $self->{'has_tertiary_path'};
}

=head2 get_path

=cut
sub get_path{
    my $self = shift;

    my %params = @_;

    my $path = $params{'path'};

    if (!defined $path) {
        return;
    }

    foreach my $p (@{$self->{paths}}) {
        if ($p->type eq $path) {
            return $p;
        }
    }

    return;
}

=head2 get_active_path

=cut
sub get_active_path{
    my $self = shift;
    return $self->{'active_path'};
}

=head2 update_mpls_path

    my $ckt = OESS::Circuit->new(db => $db, circuit_id => $circuit_id);
    $ckt->{db}->_start_transaction();
    my $ok = $ckt->update_mpls_path(links => \@ckt_path);
    if ($ok) {
        $ckt->{db}->_commit();
    } else {
        $ckt->{db}->_rollback();
    }

B<Note>: This method B<must> be called within a transaction.

=cut
sub update_mpls_path{
    my $self = shift;
    my %params = @_;

    if(!defined($params{'user_id'})){
        #if this isn't defined set the system user
        $params{'user_id'} = 1;
    }
    my $user_id = $params{'user_id'};
    my $reason = $params{'reason'};

    return if($#{$params{'links'}} == -1);

    if($self->get_type() ne 'mpls'){
        $self->{'logger'}->error("change mpls path can only be done on mpls circuits");
        return;
    }

    if ($self->has_primary_path()) {
        $self->{'logger'}->debug("Checking primary path for $self->{'circuit_id'}");

        if (_compare_links($self->get_path(path => 'primary'), $params{'links'})) {
            $self->{'logger'}->debug("Primary path selected for $self->{'circuit_id'}");
            return $self->_change_active_path(new_path => 'primary');
        }
    }

    if ($self->has_backup_path()) {
        $self->{'logger'}->info("Checking backup path for $self->{'circuit_id'}");

        if (_compare_links($self->get_path(path => 'backup'), $params{'links'})) {
            $self->{'logger'}->info("Backup path selected for $self->{'circuit_id'}");
            return $self->_change_active_path(new_path => 'backup');
        }
    }

    # After checking that any manually defined paths are not active,
    # we check that we are tracking the auto-generated path correctly;
    # This includes adding the path to the database if not already
    # existing.
    #
    # Check and see if circuit has any previously defined tertiary path

    my $query  = "select path.path_id from path join path_instantiation on path.path_id=path_instantiation.path_id where path.path_type=? and circuit_id=? and path_instantiation.end_epoch=-1";
    my $results = $self->{'db'}->_execute_query($query, ["tertiary", $self->{'circuit_id'}]);

    if (defined $results && defined $results->[0]) {
        $self->{'logger'}->debug("Tertiary path already exists.");
        my $tertiary_path_id = $results->[0]->{'path_id'};

        if(!_compare_links($self->get_path(path => 'tertiary'), $params{'links'})) {
            my $query = "update link_path_membership set end_epoch = unix_timestamp(NOW()) where path_id = ? and end_epoch = -1";
            $self->{'db'}->_execute_query($query,[$self->{model}->{'paths'}->{'tertiary'}->{'path_id'}]);

            $query = "insert into link_path_membership (end_epoch,link_id,path_id,start_epoch,interface_a_vlan_id,interface_z_vlan_id) " .
                "VALUES (-1,?,?,unix_timestamp(NOW()),?,?)";

            foreach my $link (@{$params{'links'}}) {
                $self->{'db'}->_execute_query($query, [
                    $link->{'link_id'},
                    $tertiary_path_id,
                    $self->{'circuit_id'} + 5000,
                    $self->{'circuit_id'} + 5000
                ]);
            }
        }

    }else{
        $self->{'logger'}->info("Creating tertiary path for circuit $self->{circuit_id}.");

        my @link_ids;
        foreach my $link (@{$params{'links'}}) {
            push(@link_ids, $link->{'link_id'});
        }

        $self->{'logger'}->debug("Creating tertiary path with links ". Dumper(@link_ids));

        my $path_id = $self->{'db'}->create_path($self->{'circuit_id'}, \@link_ids, 'tertiary');

        $self->{model}->{'paths'}->{'tertiary'}->{'path_id'} = $path_id;
        $self->{model}->{'paths'}->{'tertiary'}->{'mpls_path_type'} = 'tertiary';
        $self->{'has_tertiary_path'} = 1;
        $self->{model}->{'tertiary_links'} = $params{'links'};
    }

    return $self->_change_active_path(new_path => 'tertiary');
}

=head2 _change_active_path

B<Note>: This method B<must> be called within a transaction.

=cut
sub _change_active_path{
    my $self = shift;
    my %params = @_;

    my $current_path = $self->get_active_path();
    my $new_path = $params{'new_path'};

    if ($current_path eq $new_path) {
        # If an attempt is made to change the active path, but no
        # change is required return ok.
        $self->{'active_path'} = $current_path;
        $self->{model}->{'active_path'} = $current_path;
        return 1;
    }

    my $cur_path_id = $self->{db}->get_path_id(circuit_id => $self->{circuit_id}, type => $current_path);
    my $cur_path_inst = $self->{db}->get_current_path_instantiation(path_id => $cur_path_id);
    my $cur_path_state = $cur_path_inst->{path_state};
    my $cur_path_end = $cur_path_inst->{end_epoch};

    if (defined $cur_path_inst && $cur_path_inst->{end_epoch} != -1) {
        my $id = $cur_path_inst->{path_instantiation_id};
        my $q  = "insert into path_instantiation (path_id, path_state, start_epoch, end_epoch) values (?, ?, ?, ?)";
        my $count = $self->{db}->_execute_query($q, [$cur_path_id, 'decom', $cur_path_end, -1]);
        if (!defined $count || $count < 0) {
            my $err = "Unable to correct path_instantiation.";
            $self->{logger}->error($err);
            $self->error($err);
            return;
        }
        $cur_path_state = 'decom';
    } elsif ($cur_path_state ne 'decom') {
        $cur_path_state = 'available';
    }

    my $new_path_id = $self->{db}->get_path_id(circuit_id => $self->{circuit_id}, type => $new_path);
    my $new_path_inst = $self->{db}->get_current_path_instantiation(path_id => $new_path_id);
    my $new_path_state = $new_path_inst->{path_state};
    my $new_path_end = $new_path_inst->{end_epoch};

    if (defined $new_path_inst && $new_path_inst->{end_epoch} != -1) {
        my $id = $new_path_inst->{path_instantiation_id};
        my $q  = "insert into path_instantiation (path_id, path_state, start_epoch, end_epoch) values (?, ?, ?, ?)";
        my $count = $self->{db}->_execute_query($q, [$new_path_id, 'decom', $new_path_end, -1]);
        if (!defined $count || $count < 0) {
            my $err = "Unable to correct path_instantiation.";
            $self->{logger}->error($err);
            $self->error($err);
            return;
        }
        $new_path_state = 'decom';
    } elsif ($new_path_state ne 'decom') {
        $new_path_state = 'active';
    }

    $self->{'logger'}->info("Circuit $self->{'circuit_id'} changing paths from $current_path to $new_path");

    my $ok = $self->{db}->set_path_state(path_id => $cur_path_id, state => $cur_path_state);
    if (!$ok) {
        return;
    }

    $ok = $self->{db}->set_path_state(path_id => $new_path_id, state => $new_path_state);
    if (!$ok) {
        return;
    }

    $self->{'db'}->_commit();

    $self->{'active_path'} = $params{'new_path'};
    $self->{model}->{'active_path'} = $params{'new_path'};
    return 1;
}

sub _compare_links{
    my $a_links = shift;
    my $z_links = shift;

    if($#{$a_links} != $#{$z_links}){
        return 0;
    }

    my $same = 1;
    foreach my $a_link (@{$a_links}){
        my $found = 0;
        foreach my $z_link (@{$z_links}){
            if($a_link->{'name'} eq $z_link->{'name'}){
                $found = 1;
            }
        }

        if(!$found){
            $same = 0;
        }
    }

    return $same;
}

=head2 is_interdomain

=cut
sub is_interdomain{
    my $self = shift;
    return $self->{'interdomain'};
}

=head2 get_mpls_path_type

=cut
sub get_mpls_path_type{
    my $self = shift;
    my %params = @_;

    if(!defined($params{'path'})){
        $self->{'logger'}->error("No path specified");
        return;
    }

    if(!defined($self->{model}{'paths'}{$params{'path'}})){
        return;
    }

    return $self->{model}{'paths'}{$params{'path'}}{'mpls_path_type'};
}

=head2 get_mpls_hops

get_mpls_hops returns an array of IPs representing the next hops from
C<start> to C<end>.

=cut
sub get_mpls_hops{
    my $self = shift;
    my %params = @_;

    my @ips;

    my $path = $params{'path'};
    if(!defined($path)){
        $self->{'logger'}->error("Fetching the path hops for undefined path");
        return \@ips;
    }

    my $start = $params{'start'};
    if(!defined($start)){
        $self->{'logger'}->error("Fetching hops requires a start");
        return \@ips;
    }

    my $end = $params{'end'};
    if(!defined($end)){
        $self->{'logger'}->error("Fetching hops requires an end");
        return \@ips;
    }

    return \@ips if ($end eq $start);

    $self->{'logger'}->debug("Path: " . $path);

    #fetch the path
    my $p = $self->get_path(path => $path);
    if(!defined($p)){
        return \@ips;
    }

    my $nodes = $self->{'db'}->get_current_nodes( mpls => 1);
    my %nodes;
    foreach my $node (@$nodes){
        $nodes{$node->{'name'}} = $node;
    }

    #build our lookup has to find our IP addresses
    my %ip_address;
    foreach my $link (@$p){
        my $node_a = $link->{'node_a'};
        my $node_z = $link->{'node_z'};

        $ip_address{$node_a}{$node_z} = $nodes{$node_z}->{'loopback_address'};
        $ip_address{$node_z}{$node_a} = $nodes{$node_a}->{'loopback_address'};
    }

    #verify that our start/end are endpoints
    my $eps = $self->endpoints();

    #find the next hop in the shortest path from $ep_a to $ep_z
    my @shortest_path = $self->{'graph'}->{$path}->SP_Dijkstra($start,$end);
    #ok we have the list of verticies... now to convert that into IP addresses
    if(scalar(@shortest_path) <= 1){
        #uh oh... no path!!!!
        $self->{'logger'}->error("Uh oh there is no path");
        return \@ips;
    }

    for(my $i=1;$i<=$#shortest_path;$i++){
        my $ip = $ip_address{$shortest_path[$i-1]}{$shortest_path[$i]};
        $self->{'logger'}->debug("  Next hop: " . $shortest_path[$i-1] . " to " . $shortest_path[$i]);
        $self->{'logger'}->debug("      Address: " . $ip);
        push(@ips, $ip);
    }

    return \@ips;
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

# BEGIN Endpoints

=head2 load_endpoints

=cut
sub load_endpoints {
    my $self = shift;

    if (!defined $self->{db}) {
        $self->{'logger'}->warn('Optional argument `db` is missing. Cannot load Endpoints.');
        return 1;
    }
    if (!defined $self->{circuit_id}) {
        $self->{'logger'}->warn('Optional argument `circuit_id` is missing. Cannot load Endpoints.');
        return 1;
    }

    my ($ep_datas, $error) = OESS::DB::Endpoint::fetch_all(
        db => $self->{db},
        circuit_id => $self->{circuit_id}
    );

    $self->{endpoints} = [];
    foreach my $data (@$ep_datas) {
        my $ep = new OESS::Endpoint(db => $self->{db}, model => $data);
        push @{$self->{endpoints}}, $ep;
    }

    return 1;
}

=head2 add_endpoint

=cut
sub add_endpoint {
    my $self = shift;
    my $endpoint = shift;

    push @{$self->{endpoints}}, $endpoint;
}

=head2 get_endpoint

    my $ep = $l2vpn->get_endpoint(
        circuit_ep_id => 100
    );

get_endpoint returns the endpoint identified by C<circuit_ep_id> or
C<vrf_ep_id>.

=cut
sub get_endpoint {
    my $self = shift;
    my $args = {
        circuit_ep_id => undef,
        @_
    };

    if (!defined $args->{circuit_ep_id}) {
        return;
    }

    foreach my $ep (@{$self->{endpoints}}) {
        if ($args->{circuit_ep_id} == $ep->{circuit_ep_id}) {
            return $ep;
        }
    }

    return;
}

=head2 remove_endpoint

    my $ok = $l2vpn->remove_endpoint($circuit_ep_id);

remove_endpoint removes the endpoint identified by C<circuit_ep_id>
from this L2Circuit.

=cut
sub remove_endpoint {
    my $self = shift;
    my $circuit_ep_id = shift;

    if (!defined $circuit_ep_id) {
        return;
    }

    my $new_endpoints = [];
    foreach my $ep (@{$self->{endpoints}}) {
        if ($circuit_ep_id == $ep->{circuit_ep_id}) {
            next;
        }
        push @$new_endpoints, $ep;
    }
    $self->{endpoints} = $new_endpoints;

    return 1;
}

=head2 create

    $db->start_transaction;
    my ($id, $err) = $l2vpn->create;
    if (defined $err) {
        $db->rollback;
        warn $err;
    }

create saves this L2Circuit along with its Endpoints and Paths to the
database. This method B<must> be wrapped in a transaction and B<shall>
only be used to create a new L2Circuit.

=cut
sub create {
    my $self = shift;

    if (!defined $self->{db}) {
        $self->{'logger'}->error("Database handle is missing.");
        return (undef, "Database handle is missing.");
    }

    my ($circuit_id, $circuit_err) = OESS::DB::Circuit::create(
        db => $self->{db},
        model => {
            name => $self->name,
            description => $self->description,
            user_id => $self->user_id,
            workgroup_id => $self->workgroup_id,
            provision_time => $self->provision_time,
            remove_time => $self->remove_time,
            remote_url => $self->remote_url,
            remote_requester => $self->remote_requester,
            external_identifier => $self->external_identifier
        }
    );
    if (defined $circuit_err) {
        $self->{logger}->error($circuit_err);
        return (undef, $circuit_err);
    }

    $self->{circuit_id} = $circuit_id;

    return ($circuit_id, undef);
}

=head2 update

    my $err = $l2vpn->update;
    $db->rollback if defined $err;

update saves any changes made to this L2Circuit.

Note that any changes to the userlying Endpoint or Path objects will
not be propagated to the database by this method call.

=cut
sub update {
    my $self = shift;

    if (!defined $self->{db}) {
        return "Unable to write L2Circuit to database; Handle is missing.";
    }
    return OESS::DB::Circuit::update(db => $self->{db}, circuit => $self->to_hash);
}

=head2 remove

    my $err = $l2conn->remove(
        user_id => 101
        reason  => 'user request' # Optional
    );

=cut
sub remove {
    my $self = shift;
    my $args = {
        user_id    => undef,
        reason     => 'User requested remove of circuit',
        @_
    };

    return 'Required argument `user_id` is missing.' if !defined $args->{user_id};

    if (!defined $self->{db}) {
        $self->{'logger'}->error('Database handle is missing.');
    }

    my $err = OESS::DB::Circuit::remove(
        db => $self->{db},
        circuit_id => $self->circuit_id,
        user_id => $args->{user_id},
        reason => $args->{reason}
    );
    return $err;
}

=head2 nso_diff

Given an NSO Connection object: Return a hash of device-name to
human-readable-diff containing the difference between this L2Circuit
and the provided NSO Connection object.

NSO L2Connection:

    {
        'connection_id' => 3000,
        'endpoint' => [
            {
                'bandwidth' => 0,
                'endpoint_id' => 1,
                'interface' => 'GigabitEthernet0/0',
                'tag' => 1,
                'device' => 'xr0'
            },
            {
                'bandwidth' => 0,
                'endpoint_id' => 2,
                'interface' => 'GigabitEthernet0/1',
                'tag' => 1,
                'device' => 'xr0'
            }
        ]
    }

=cut
sub nso_diff {
    my $self = shift;
    my $nsoc = shift; # NSOConnection

    my $diff = {};
    my $ep_index = {};

    # Handle case where connection has no endpoints or a connection
    # created with an empty model.
    my $endpoints = $self->endpoints || [];

    foreach my $ep (@{$endpoints}) {
        if (!defined $ep_index->{$ep->node}) {
            $diff->{$ep->node} = "";
            $ep_index->{$ep->node} = {};
        }
        $ep_index->{$ep->node}->{$ep->interface} = $ep;
    }

    foreach my $ep (@{$nsoc->{endpoint}}) {
        if (!defined $ep_index->{$ep->{device}}->{$ep->{interface}}) {
            $diff->{$ep->{device}} = "" if !defined $diff->{$ep->{device}};
            $diff->{$ep->{device}} .= "- $ep->{interface}\n";
            $diff->{$ep->{device}} .= "-   Bandwidth: $ep->{bandwidth}\n";
            $diff->{$ep->{device}} .= "-   Tag:       $ep->{tag}\n";
            $diff->{$ep->{device}} .= "-   Inner Tag: $ep->{inner_tag}\n" if defined $ep->{inner_tag};
            next;
        }
        my $ref_ep = $ep_index->{$ep->{device}}->{$ep->{interface}};

        # Compare endpoints
        my $ok = 1;
        $ok = 0 if $ep->{bandwidth} != $ref_ep->bandwidth;
        $ok = 0 if $ep->{tag} != $ref_ep->tag;
        $ok = 0 if $ep->{inner_tag} != $ref_ep->inner_tag;
        if (!$ok) {
            $diff->{$ep->{device}} = "" if !defined $diff->{$ep->{device}};
            $diff->{$ep->{device}} .= "  $ep->{interface}\n";
        }

        if ($ep->{bandwidth} != $ref_ep->bandwidth) {
            $diff->{$ep->{device}} .= "-   Bandwidth: $ep->{bandwidth}\n";
            $diff->{$ep->{device}} .= "+   Bandwidth: $ref_ep->{bandwidth}\n";
        }
        if ($ep->{tag} != $ref_ep->tag) {
            $diff->{$ep->{device}} .= "-   Tag:       $ep->{tag}\n";
            $diff->{$ep->{device}} .= "+   Tag:       $ref_ep->{tag}\n";
        }
        if ($ep->{inner_tag} != $ref_ep->inner_tag) {
            $diff->{$ep->{device}} .= "-   Inner Tag: $ep->{inner_tag}\n" if defined $ep->{inner_tag};
            $diff->{$ep->{device}} .= "+   Inner Tag: $ref_ep->{inner_tag}\n" if defined $ref_ep->{inner_tag};
        }

        delete $ep_index->{$ep->{device}}->{$ep->{interface}};
    }

    foreach my $device_key (keys %{$ep_index}) {
        foreach my $ep_key (keys %{$ep_index->{$device_key}}) {
            my $ep = $ep_index->{$device_key}->{$ep_key};
            $diff->{$ep->node} = "" if !defined $diff->{$ep->node};

            $diff->{$ep->node} .= "+ $ep->{interface}\n";
            $diff->{$ep->node} .= "+   Bandwidth: $ep->{bandwidth}\n";
            $diff->{$ep->node} .= "+   Tag:       $ep->{tag}\n";
            $diff->{$ep->node} .= "+   Inner Tag: $ep->{inner_tag}\n" if defined $ep->{inner_tag};
        }
    }

    foreach my $key (keys %$diff) {
        delete $diff->{$key} if ($diff->{$key} eq '');
    }

    return $diff;
}

1;
