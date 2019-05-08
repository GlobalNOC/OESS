#!/usr/bin/perl

use strict;
use warnings;

package OESS::L2Circuit;

use Data::Dumper;
use Graph::Directed;
use Log::Log4perl;

use OESS::DB;
use OESS::DB::Circuit;
use OESS::Path;
use OESS::User;

#link statuses
use constant OESS_LINK_UP       => 1;
use constant OESS_LINK_DOWN     => 0;
use constant OESS_LINK_UNKNOWN  => 2;


=head1 NAME

OESS::L2Circuit - Circuit Interaction Module

=head1 SYNOPSIS

This is a module to provide a simplified object oriented way to
connect to and interact with the OESS Circuits.

Some examples:

    use OESS::L2Circuit;

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
            provision_time => '',
            remove_time => '',
            endpoints => [
                # See OESS::Endpoint
            ],
            user_id => '',
            workgroup_id => '',
        }
    );

    if (!defined $ckt) {
        warn $circuit->get_error;
    }

=cut


=head2 new

Creates a new OESS::L2Circuit object requires an OESS::Database handle
and either the details from get_circuit_details or a circuit_id.

=cut

sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $self = {
        circuit_id => undef,
        db         => undef,
        details    => undef,
        logger     => Log::Log4perl->get_logger('OESS.L2Circuit'),
        just_display => 0,
        link_status => undef,
        @_
    };
    bless $self, $class;

    if (!defined $self->{'db'}) {
        $self->{'logger'}->debug('Optional argument `db` is missing. Cannot save object to database.');
    }

    if (defined $self->{'db'} && defined $self->{'circuit_id'}) {
        eval {
            $self->_load_circuit_details();
        };
        if ($@) {
            $self->{logger}->error("Couldn't load L2Circuit: $@");
            return;
        }
    } elsif (!defined $self->{'details'}) {
        $self->{logger}->debug('Optional argument `model` is missing.');
        $self->{logger}->error("Couldn't load L2Circuit from db or model.");
        return;
    }

    $self->_process_circuit_details($self->{'details'});

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

=head2 workgroup_id

=cut
sub workgroup_id{
    my $self = shift;
    my $workgroup_id = shift;
    if (defined $workgroup_id) {
        $self->{'workgroup_id'} = $workgroup_id;
    }
    return $self->{'workgroup_id'};
}

=head2 load_users

=cut
sub load_users {
    my $self = shift;

    # TODO User object shouldn't load workgroup info. Way too much
    # info there.

    $self->{created_by} = OESS::User->new(
        db => $self->{db},
        user_id => $self->{created_by_id}
    );

    $self->{last_modified_by} = new OESS::User(
        db => $self->{db},
        user_id => $self->{last_modified_by_id}
    );
}

=head2 load_paths

=cut
sub load_paths {
    my $self = shift;

    my ($path_datas, $error) = OESS::DB::Path::fetch_all(
        db => $self->{db},
        circuit_id => $self->{circuit_id}
    );

    my $paths = [];
    foreach my $data (@$path_datas) {
        push @$paths, new OESS::Path(model => $data);
    }

    $self->{paths} = $paths;
}

=head2 load_endpoints

=cut
sub load_endpoints {
    my $self = shift;
}

=head2 load_workgroup

=cut
sub load_workgroup {
    my $self = shift;
}

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
        remove_time => '',
        endpoints => [
            # See OESS::Endpoint
        ]
    };

    if (defined $self->{created_by}) {
        $hash->{created_by} = $self->{created_by}->to_hash;
    }
    if (defined $self->{last_modified_by}) {
        $hash->{last_modified_by} = $self->{last_modified_by}->to_hash;
    }

    if (defined $self->{paths}) {
        $hash->{paths} = [];
        foreach my $path (@{$self->{paths}}) {
            push @{$hash->{paths}}, $path->to_hash;
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

    $self->{details} = $data;
    $self->_process_circuit_details($data);
}

sub _process_circuit_details{
    my $self = shift;
    my $hash = shift;

    $self->{remote_requester} = $hash->{remote_requester};
    $self->{last_modified_by_id} = $hash->{last_modified_by_id};
    $self->{external_identifier} = $hash->{external_identifier};
    $self->{state} = $hash->{state};
    $self->{remote_url} = $hash->{remote_url};
    $self->{created_on} = $hash->{created_on};
    $self->{circuit_id} = $hash->{circuit_id};
    $self->{workgroup_id} = $hash->{workgroup_id};
    $self->{created_on_epoch} = $hash->{created_on_epoch};
    $self->{last_modified_on_epoch} = $hash->{last_modified_on_epoch};
    $self->{name} = $hash->{name};
    $self->{reason} = $hash->{reason};
    $self->{description} = $hash->{description};
    $self->{user_id} = $hash->{user_id};
    $self->{last_modified_on} = $hash->{last_modified_on};
    $self->{created_by_id} = $hash->{created_by_id};

    # TODO Load primary links
    $self->{'has_primary_path'} = (defined $hash->{'links'} && @{$hash->{'links'}} > 0) ? 1 : 0;

    # TODO Load tertiary links
    $self->{'has_tertiary_path'} = (defined $hash->{'tertiary_links'} && @{$hash->{'tertiary_links'}} > 0) ? 1 : 0;

    # TODO Load endpoints
    $self->{'endpoints'} = $hash->{'endpoints'};

    foreach my $endpoint (@{$self->{'endpoints'}}){
        if ($endpoint->{'local'} == 0) {
            $self->{'interdomain'} = 1;
        }

        my $entity = OESS::Entity->new(
            db => $self->{'db'},
            interface_id => $endpoint->{'interface_id'},
            vlan => $endpoint->{'tag'}
        );
        if (!defined $entity) {
            next;
        }

        $endpoint->{'entity'} = $entity->to_hash();
    }

    # if (!$self->{'just_display'}) {
    #     $self->_create_graph();
    # }
}

sub _create_graph{
    my $self = shift;

    $self->{'logger'}->debug("Creating graphs for circuit " . $self->{'circuit_id'});
    my @links = @{$self->{'details'}->{'links'}};

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

        @links = @{$self->{'details'}->{'backup_links'}};
        my $b = Graph::Undirected->new;

        foreach my $link (@links){
            $b->add_vertex($link->{'node_z'});
            $b->add_vertex($link->{'node_a'});
            $b->add_edge($link->{'node_a'},$link->{'node_z'});
        }

        $self->{'graph'}->{'backup'} = $b;
    }
}

=head2 get_details

=cut
sub get_details{
    my $self = shift;

    # TODO Create a to_hash method

    return $self->{'details'};
}

=head2 generate_clr

generate_clr creates a circuit layout record for this circuit.

=cut
sub generate_clr{
    my $self = shift;

    my $clr = "";
    $clr .= "Circuit: $self->{'details'}->{'name'}\n";
    $clr .= "Created by: $self->{'details'}->{'created_by'}->{'given_names'} $self->{'details'}->{'created_by'}->{'family_name'} at $self->{'details'}->{'created_on'} for workgroup $self->{'details'}->{'workgroup'}->{'name'}\n";
    $clr .= "Last Modified By: $self->{'details'}->{'last_modified_by'}->{'given_names'} $self->{'details'}->{'last_modified_by'}->{'family_name'} at $self->{'details'}->{'last_edited'}\n\n";
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

=head2 get_endpoints

=cut
sub get_endpoints{
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
        $self->{'logger'}->error("Path was not defined.");
        return;
    }

    if ($path eq 'tertiary') {
        return $self->{'details'}->{'tertiary_links'};
    } else {
        return $self->{'details'}->{'links'};
    }
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
            $self->{'db'}->_execute_query($query,[$self->{'details'}->{'paths'}->{'tertiary'}->{'path_id'}]);

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

        $self->{'details'}->{'paths'}->{'tertiary'}->{'path_id'} = $path_id;
        $self->{'details'}->{'paths'}->{'tertiary'}->{'mpls_path_type'} = 'tertiary';
        $self->{'has_tertiary_path'} = 1;
        $self->{'details'}->{'tertiary_links'} = $params{'links'};
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
        $self->{'details'}->{'active_path'} = $current_path;
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
    $self->{'details'}->{'active_path'} = $params{'new_path'};
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

=head2 is_static_mac

=cut
sub is_static_mac{
    my $self = shift;
    return $self->{'static_mac'};
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

    $self->{'logger'}->debug("MPLS Path Type: " . Data::Dumper::Dumper($self->{'details'}{'paths'}));

    if(!defined($self->{'details'}{'paths'}{$params{'path'}})){
        return;
    }

    return $self->{'details'}{'paths'}{$params{'path'}}{'mpls_path_type'};
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

    $self->{'logger'}->debug("Path is: " . Dumper($p));

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
    my $eps = $self->get_endpoints();

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

    $self->{'logger'}->debug("IP addresses: " . Dumper(@ips));

    return \@ips;
}

=head2 get_path_status

=cut
sub get_path_status{
    my $self = shift;
    my %params = @_;

    my $path = $params{'path'};
    my $link_status = $params{'link_status'};

    if(!defined($path)){
        return;
    }

    my %down_links;
    my %unknown_links;

    if(!defined($link_status)){
        my $links = $self->{'db'}->get_current_links(type => $self->{'type'});

        foreach my $link (@$links){
            if( $link->{'status'} eq 'down'){
                $down_links{$link->{'name'}} = $link;
            }elsif($link->{'status'} eq 'unknown'){
                $unknown_links{$link->{'name'}} = $link;
            }
        }
    }else{
        foreach my $key (keys (%{$link_status})){
            if($link_status->{$key} == OESS_LINK_DOWN){
                $down_links{$key} = 1;
            }elsif($link_status->{$key} == OESS_LINK_UNKNOWN){
                $unknown_links{$key} = 1;
            }
        }
    }

    my $path_links = $self->get_path( path => $path );

    foreach my $link (@$path_links){

        if( $down_links{ $link->{'name'} } ){
            $self->{'logger'}->warn("Path is down because link: " . $link->{'name'} . " is down");
            return 0;
        }elsif($unknown_links{$link->{'name'}}){
            $self->{'logger'}->warn("Path is unknown because link: " . $link->{'name'} . " is unknown");
            return 2;
        }
    }

    return 1;
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

1;
