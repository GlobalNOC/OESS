#!/usr/bin/perl
use strict;
use warnings;

package OESS::VRF;

use Log::Log4perl;

#link statuses
use constant OESS_LINK_UP       => 1;
use constant OESS_LINK_DOWN     => 0;
use constant OESS_LINK_UNKNOWN  => 2;

use Data::Dumper;
use OESS::DB;
use OESS::Endpoint;
use OESS::Workgroup;
use NetAddr::IP;
use OESS::Config;

=head1 OESS::VRF

    use OESS::VRF;

This is a module to provide a simplified object oriented way to
connect to and interact with the OESS VRFs.

=cut

=head2 new

    my $vrf = OESS::VRF->new(
        db     => new OESS::DB,
        vrf_id => 100
    );
    if (!defined $vrf) {
        warn $vrf->get_error;
    }

Creates a new OESS::VRF object requires an OESS::DB handle and either
the details from get_vrf_details or a vrf_id.

=cut

sub new {
    my $that  = shift;
    my $class = ref($that) || $that;

    my %args = (
        details => undef,
        vrf_id => undef,
        db => undef,
        logger => Log::Log4perl->get_logger("OESS.VRF"),
        just_display => 0,
        link_status => undef,
        @_
    );
    my $self = \%args;
    bless $self, $class;

    if (!defined $self->{db} && !defined $self->{model}) {
        $self->{logger}->error("Couldn't create VRF: Arguments `db` and `model` are both missing.");
        return;
    }

    if (!defined $self->{config}) {
        $self->{config} = new OESS::Config();
    }

    if (defined $self->{db} && (defined $self->{vrf_id} && $self->{vrf_id} != -1)) {
        eval {
            my $model = OESS::DB::VRF::fetch(db => $self->{db}, vrf_id => $self->{vrf_id});
            $self->{model} = $model;
        };
        if ($@) {
            $self->{logger}->error("Couldn't create VRF: $@");
            warn "Couldn't create VRF: $@";
            return;
        }
    }

    if (!defined $self->{model}) {
        $self->{logger}->error("Couldn't create VRF. Couldn't load `model` and none provided.");
        return;
    }

    $self->from_hash($self->{model});
    return $self;
}

=head2 from_hash

    my $ok = $vrf->from_hash;

=cut
sub from_hash{
    my $self = shift;
    my $hash = shift;

    $self->{'created'} = $hash->{'created'};
    $self->{'created_by_id'} = $hash->{'created_by_id'};
    $self->{'description'} = $hash->{'description'};
    $self->{'last_modified'} = $hash->{'last_modified'};
    $self->{'last_modified_by_id'} = $hash->{'last_modified_by_id'};
    $self->{'local_asn'} = $hash->{'local_asn'} || $self->{'config'}->local_as;
    $self->{'name'} = $hash->{'name'};
    $self->{'operational_state'} = $hash->{'operational_state'};
    $self->{'prefix_limit'} = $hash->{'prefix_limit'};
    $self->{'state'} = $hash->{'state'};
    $self->{'vrf_id'} = $hash->{'vrf_id'};
    $self->{'workgroup_id'} = $hash->{'workgroup_id'};

    return 1;
}

=head2 to_hash

=cut
sub to_hash{
    my $self = shift;

    my $hash = {
        created => $self->{created},
        created_by_id => $self->{created_by_id},
        description => $self->{description},
        last_modified => $self->{last_modified},
        last_modified_by_id => $self->{last_modified_by_id},
        local_asn => $self->{local_asn},
        name => $self->{name},
        operational_state => $self->operational_state,
        prefix_limit => $self->{prefix_limit} || 1000,
        state => $self->{state},
        vrf_id => $self->{vrf_id},
        workgroup_id => $self->{workgroup_id}
    };

    if (defined $self->{workgroup}) {
        $hash->{workgroup} = $self->{workgroup}->to_hash;
    }
    if (defined $self->{created_by}) {
        $hash->{created_by} = $self->{created_by}->to_hash;
    }
    if (defined $self->{last_modified_by}) {
        $hash->{last_modified_by} = $self->{last_modified_by}->to_hash;
    }
    if (defined $self->{endpoints}) {
        $hash->{endpoints} = [];
        foreach my $ep (@{$self->{endpoints}}) {
            push @{$hash->{endpoints}}, $ep->to_hash;
        }
    }

    return $hash;
}

=head2 vrf_id

=cut
sub vrf_id {
    my $self =shift;
    return $self->{'vrf_id'};
}

=head2 load_endpoints

=cut
sub load_endpoints {
    my $self = shift;

    my ($ep_datas, $error) = OESS::DB::Endpoint::fetch_all(
        db => $self->{db},
        vrf_id => $self->{vrf_id}
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

    my $ep = $vrf->get_endpoint(
        vrf_ep_id => 100
    );

get_endpoint returns the endpoint identified by C<vrf_ep_id>.

=cut
sub get_endpoint {
    my $self = shift;
    my $args = {
        vrf_ep_id => undef,
        @_
    };

    if (!defined $args->{vrf_ep_id}) {
        return;
    }

    foreach my $ep (@{$self->{endpoints}}) {
        if ($args->{vrf_ep_id} == $ep->{vrf_endpoint_id}) {
            return $ep;
        }
    }

    return;
}

=head2 remove_endpoint

    my $ok = $vrf->remove_endpoint($vrf_ep_id);

remove_endpoint removes the endpoint identified by C<vrf_ep_id> from
this vrf.

=cut
sub remove_endpoint {
    my $self = shift;
    my $vrf_ep_id = shift;

    if (!defined $vrf_ep_id) {
        return;
    }

    my $new_endpoints = [];
    foreach my $ep (@{$self->{endpoints}}) {
        if ($vrf_ep_id == $ep->{vrf_endpoint_id}) {
            next;
        }
        push @$new_endpoints, $ep;
    }
    $self->{endpoints} = $new_endpoints;

    return 1;
}

=head2 endpoints

=cut
sub endpoints {
    my $self = shift;
    my $eps = shift;

    if (!defined $eps) {
        return $self->{endpoints} || [];
    }

    $self->{endpoints} = $eps;
    return $self->{endpoints};
}

=head2 name

=cut
sub name{
    my $self = shift;
    my $name = shift;
    
    if(!defined($name)){
        return $self->{'name'};
    }else{
        $self->{'name'} = $name;
        return $self->{'name'};
    }
}

=head2 description

=cut
sub description{
    my $self = shift;
    my $description = shift;

    if(!defined($description)){
        return $self->{'description'};
    }else{
        $self->{'description'} = $description;
        return $self->{'description'};
    }
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


=head2 create

    my ($id, $err) = $vrf->create;
    if (defined $err) {
        warn $err;
    }

=cut
sub create {
    my $self = shift;

    if (!defined $self->{db}) {
        $self->{'logger'}->error("Database handle is missing.");
        return (undef, "Database handle is missing.");
    }

    my ($id, $err) = OESS::DB::VRF::create(db => $self->{db}, model => $self->to_hash);
    if (defined $err) {
        $self->{logger}->error($err);
        return (undef, $err);
    }
    $self->{vrf_id} = $id;

    return ($id, undef);
}

=head2 update

    my $err = $vrf->update;
    $db->rollback if defined $err;

update saves any changes made to this VRF.

Note that any changes to the underlying Endpoint or Path objects will
not be propagated to the database by this method call.

=cut
sub update {
    my $self = shift;

    if (!defined $self->{db}) {
        return "Unable to write VRF to database; Handle is missing";
    }
    return OESS::DB::VRF::update(db => $self->{db}, vrf => $self->to_hash);
}

=head2 update_vrf_details

reload the vrf details from the database to make sure everything is in
sync with what should be there

=cut
sub update_vrf_details{
    my $self = shift;
    my %params = @_;

    return 1;
}

=head2 decom

    my $ok = $vrf->decom;

=cut
sub decom{
    my $self = shift;
    my %params = @_;
    my $user_id = $params{'user_id'};
    
    foreach my $ep (@{$self->endpoints()}){
        $ep->decom();
    }

    my $res = OESS::DB::VRF::decom(db => $self->{'db'}, vrf_id => $self->{'vrf_id'}, user_id => $user_id);
    return $res;

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

=head2 prefix_limit

=cut
sub prefix_limit{
    my $self = shift;
    if(!defined($self->{'prefix_limit'})){
        return 1000;
    }
    return $self->{'prefix_limit'};
}

=head2 load_users

    my $err = $vrf->load_users;

load_users populates C<created_by> and C<last_modified_by> with
C<OESS::User> objects.

=cut
sub load_users {
    my $self = shift;
    my $err = undef;

    $self->{created_by} = new OESS::User(db => $self->{db}, user_id => $self->{created_by_id});
    $self->{last_modified_by} = new OESS::User(db => $self->{db}, user_id => $self->{last_modified_by_id});
    return $err;
}

=head2 created

    my $unixtime = $vrf->created;

=cut
sub created {
    my $self = shift;
    return $self->{'created'};
}

=head2 created_by

    my $created_by = $vrf->created_by;

or

    $vrf->created_by(new OESS::User(db => $db, user_id => $id));

=cut
sub created_by {
    my $self = shift;
    my $created_by = shift;

    if (defined $created_by) {
        $self->{created_by} = $created_by;
        $self->{created_by_id} = $created_by->{user_id};
    }
    return $self->{created_by};
}

=head2 last_modified

    my $unixtime = $vrf->last_modified;

=cut
sub last_modified {
    my $self = shift;
    return $self->{'last_modified'};
}

=head2 last_modified_by

    my $last_modified_by = $vrf->last_modified_by;

or

    $vrf->last_modified_by(new OESS::User(db => $db, user_id => $id));

=cut
sub last_modified_by {
    my $self = shift;
    my $last_modified_by = shift;

    if (defined $last_modified_by) {
        $self->{last_modified_by} = $last_modified_by;
        $self->{last_modified_by_id} = $last_modified_by->user_id;
    }
    return $self->{last_modified_by};
}

=head2 local_asn

=cut
sub local_asn{
    my $self = shift;
    return $self->{'local_asn'};
}

=head2 state

=cut
sub state{
    my $self = shift;
    return $self->{'state'};
}

=head2 operational_state

=cut
sub operational_state{
    my $self = shift;
    
    my $operational_state = 1;
    foreach my $ep (@{$self->endpoints()}){
        foreach my $peer (@{$ep->peers()}){
            if($peer->operational_state() ne 'up'){
                $operational_state = 0;
            }
        }
    }

    if($operational_state){
        return "up";
    }else{
        return "down";
    }
}

=head2 nso_diff

Given an NSO Connection object: Return a hash of device-name to
human-readable-diff containing the difference between this L2Circuit
and the provided NSO Connection object.

NSO L2Connection:

    {
        "connection_id" => 1,
        "endpoint" => [
            {
                "endpoint_id" => 1,
                "vars" => {
                    "pdp" => "CHIC-JJJ-0",
                    "ce_id" => 1,
                    "remote_ce_id" => 2
                },
                "device" => "xr0",
                "interface" => "GigabitEthernet0/0",
                "tag" => 300,
                "bandwidth" => 100,
                "peer" => [
                    {
                        "peer_id" => 1,
                        "local_asn" => 64600,
                        "local_ip" => "192.168.1.2/31",
                        "peer_asn" => 64001,
                        "peer_ip" => "192.168.1.3/31",
                        "bfd" => 0
                    }
                ]
            },
            {
                "endpoint_id" => 2,
                "vars" => {
                    "pdp" => "CHIC-JJJ-1",
                    "ce_id" => 2,
                    "remote_ce_id" => 1
                },
                "device" => "xr1",
                "interface" => "GigabitEthernet0/1",
                "tag" => 300,
                "bandwidth" => 100,
                "peer" => [
                    {
                        "peer_id" => 2,
                        "local_asn" => 64600,
                        "local_ip" => "192.168.2.2/31",
                        "peer_asn" => 64602,
                        "peer_ip" => "192.168.2.3/31",
                        "bfd" => 0
                    }
                ]
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

            foreach my $peer (@{$ep->{peer}}) {
                $diff->{$ep->{device}} .= "-   Peer $peer->{peer_id}:\n";
                $diff->{$ep->{device}} .= "-     Local ASN: $peer->{local_asn}\n";
                $diff->{$ep->{device}} .= "-     Local IP:  $peer->{local_ip}\n";
                $diff->{$ep->{device}} .= "-     Peer ASN:  $peer->{peer_asn}\n";
                $diff->{$ep->{device}} .= "-     Peer IP:   $peer->{peer_ip}\n";
                $diff->{$ep->{device}} .= "-     BFD:       $peer->{bfd}\n";
            }
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

        # Compare an Endpoint's Peers
        my $peer_diff = "";
        my $index = {};
        foreach my $peer (@{$ref_ep->peers}) {
            $index->{$peer->vrf_ep_peer_id} = $peer;
        }

        foreach my $pr (@{$ep->{peer}}) {
            if (!defined $index->{$pr->{peer_id}}) {
                # Peer should be removed
                $peer_diff .= "-   Peer $pr->{peer_id}\n";
                $peer_diff .= "-     Local ASN: $pr->{local_asn}\n";
                $peer_diff .= "-     Local IP:  $pr->{local_ip}\n";
                $peer_diff .= "-     Peer ASN:  $pr->{peer_asn}\n";
                $peer_diff .= "-     Peer IP:   $pr->{peer_ip}\n";
                $peer_diff .= "-     BFD:       $pr->{bfd}\n";
            }

            my $ref = $index->{$pr->{peer_id}};

            # Peer should be compared
            my $ok = 1;
            $ok = 0 if $pr->{local_ip} ne $ref->local_ip;
            $ok = 0 if $pr->{peer_asn} != $ref->peer_asn;
            $ok = 0 if $pr->{peer_ip}  ne $ref->peer_ip;
            if (!$ok) {
                $peer_diff .= "    Peer $pr->{peer_id}:\n";
            }

            if ($pr->{local_ip} ne $ref->local_ip) {
                $peer_diff .= "-     Local IP:  $pr->{local_ip}\n";
                $peer_diff .= "+     Local IP:  $ref->{local_ip}\n";
            }
            if ($pr->{peer_asn} != $ref->peer_asn) {
                $peer_diff .= "-     Peer ASN:  $pr->{peer_asn}\n";
                $peer_diff .= "+     Peer ASN:  $ref->{peer_asn}\n";
            }
            if ($pr->{peer_ip} ne $ref->peer_ip) {
                $peer_diff .= "-     Peer IP:   $pr->{peer_ip}\n";
                $peer_diff .= "+     Peer IP:   $ref->{peer_ip}\n";
            }
            if ($pr->{bfd} != $ref->bfd) {
                $peer_diff .= "-     BFD:      $pr->{bfd}\n";
                $peer_diff .= "+     BFD:      $ref->{bfd}\n";
            }

            delete $index->{$pr->{peer_id}};
        }

        foreach my $id (keys %{$index}) {
            # Peer should be added
            my $pr = $index->{$id};
            $peer_diff .= "+   Peer $pr->{vrf_ep_peer_id}:\n";
            $peer_diff .= "+     Local ASN: $pr->{local_asn}\n";
            $peer_diff .= "+     Local IP:  $pr->{local_ip}\n";
            $peer_diff .= "+     Peer ASN:  $pr->{peer_asn}\n";
            $peer_diff .= "+     Peer IP:   $pr->{peer_ip}\n";
            $peer_diff .= "+     BFD:       $pr->{bfd}\n";
        }
        # End Compare an Endpoint's Peers
        $diff->{$ep->{device}} .= $peer_diff;

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

            foreach my $peer (@{$ep->peers}) {
                $diff->{$ep->node} .= "+   Peer $peer->{vrf_ep_peer_id}:\n";
                $diff->{$ep->node} .= "+     Local ASN: $self->{local_asn}\n";
                $diff->{$ep->node} .= "+     Local IP:  $peer->{local_ip}\n";
                $diff->{$ep->node} .= "+     Peer ASN:  $peer->{peer_asn}\n";
                $diff->{$ep->node} .= "+     Peer IP:   $peer->{peer_ip}\n";
                $diff->{$ep->node} .= "+     BFD:       $peer->{bfd}\n";
            }
        }
    }

    foreach my $key (keys %$diff) {
        delete $diff->{$key} if ($diff->{$key} eq '');
    }

    return $diff;
}

1;
