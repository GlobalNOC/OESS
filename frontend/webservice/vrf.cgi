#!/usr/bin/perl -I /home/aragusa/OESS/perl-lib/OESS/lib

use strict;
use warnings;

use Log::Log4perl;

use GRNOC::WebService::Method;
use GRNOC::WebService::Dispatcher;

use OESS::RabbitMQ::Client;
use OESS::Cloud::AWS;
use OESS::DB;
use OESS::VRF;


Log::Log4perl::init_and_watch('/etc/oess/logging.conf',10);


my $db = OESS::DB->new();
my $svc = GRNOC::WebService::Dispatcher->new();
my $mq = OESS::RabbitMQ::Client->new( topic    => 'OF.FWDCTL.RPC',
                                      timeout  => 120 );


sub register_ro_methods{

    my $method = GRNOC::WebService::Method->new( 
        name => "get_vrf_details",
        description => "returns the VRF details of a specified VRF",
        callback => sub { get_vrf_details(@_) }
        );

    $method->add_input_parameter( name => 'vrf_id',
                                  pattern => $GRNOC::WebService::Regex::INTEGER,
                                  required => 1,
                                  description => 'VRF ID to fetch details' 
        );

    $svc->register_method($method);

    $method = GRNOC::WebService::Method->new(
        name => 'get_vrfs',
        description => 'returns the list of VRFs',
        callback => sub { get_vrfs(@_) } );

    $method->add_input_parameter( name => 'workgroup_id',
                                  pattern => $GRNOC::WebService::Regex::INTEGER,
                                  required => 1,
                                  description => 'Workgroup ID to fetch the list of VRFs');

    $svc->register_method($method);
    


}

sub register_rw_methods{
    
    my $method = GRNOC::WebService::Method->new(
        name => 'provision',
        description => 'provision a new vrf on the network',
        callback => sub { provision_vrf(@_) });

    $method->add_input_parameter(
        name            => 'vrf_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "If editing an existing VRF specify the ID otherwise leave blank for new VRF."
        );

    $method->add_input_parameter(
        name            => 'name',
        pattern         => $GRNOC::WebService::Regex::NAME_ID,
        required        => 1,
        description     => "The workgroup_id with permission to build the vrf, the user must be a member of this workgroup."
        );

    $method->add_input_parameter(
        name            => 'workgroup_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The workgroup_id with permission to build the vrf, the user must be a member of this workgroup."
        );

    #add the required input parameter description
    $method->add_input_parameter(
        name            => 'description',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
        description     => "The description of the circuit."
        );    
    
    $method->add_input_parameter(
        name            => 'endpoint',
        pattern         => $GRNOC::WebService::Regex::TEXT,
        required        => 1,
        multiple        => 1,
        description     => "The JSON blob describing all of the endpoints"
    );

    $method->add_input_parameter(
        name            => 'local_asn',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The JSON blob describing all of the endpoints"
    );

    $method->add_input_parameter(
        name            => 'prefix_limit',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        default         => 1000,
        description     => "Maximum prefix limit size for BGP peer routes"
    );

    $svc->register_method($method);
    
    $method = GRNOC::WebService::Method->new(
        name => 'remove',
        description => 'removes a vrf that is on the network',
        callback => sub { remove_vrf(@_) });    
    
    $method->add_input_parameter(
        name            => 'workgroup_id',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 1,
        description     => "The workgroup_id with permission to build the vrf, the user must be a member of this workgroup."
        );

    $method->add_input_parameter(
        name => 'vrf_id',
        pattern => $GRNOC::WebService::Regex::INTEGER,
        required => 1,
        description => 'the ID of the VRF to remove from the network');

    $svc->register_method($method);

}

sub get_vrf_details{
    my $method = shift;
    my $params = shift;
    my $ref = shift;

    my $vrf_id = $params->{'vrf_id'}{'value'};
    
    my $vrf = OESS::VRF->new(db => $db, vrf_id => $vrf_id);
    
    if(!defined($vrf)){
        $method->set_error("VRF: " . $vrf_id . " was not found");
        return;
    }

    return {results => [$vrf->to_hash()]};
    
}

sub get_vrfs{
    my $method = shift;
    my $params = shift;
    my $ref = shift;

    my $workgroup_id = $params->{'workgroup_id'}{'value'};
    
    #verify user is in workgroup
    my $user = OESS::DB::User::find_user_by_remote_auth( db => $db, remote_user => $ENV{'REMOTE_USER'} );

    $user = OESS::User->new(db => $db, user_id =>  $user->{'user_id'} );

    if(!defined($user)){
        $method->set_error("User " . $ENV{'REMOTE_USER'} . " is not in OESS");
        return;
    }

    #first validate the user is in the workgroup
    if(!$user->in_workgroup( $workgroup_id)){
        $method->set_error("User is not in workgroup");
        return;
    }
    
    my $vrfs = OESS::DB::VRF::get_vrfs( db => $db, workgroup_id => $workgroup_id, state => 'active');
    
    my @vrfs;
    foreach my $vrf (@$vrfs){
        my $vrf = OESS::VRF->new( db => $db, vrf_id => $vrf->{'vrf_id'});
        next if(!defined($vrf));
        push(@vrfs, $vrf->to_hash());
    }

    return \@vrfs;
        

}

sub provision_vrf{
    my $method = shift;
    my $params = shift;
    my $ref = shift;

    my $model = {};

    my $user = OESS::DB::User::find_user_by_remote_auth( db => $db, remote_user => $ENV{'REMOTE_USER'} );
    
    $user = OESS::User->new(db => $db, user_id =>  $user->{'user_id'} );

    if(!defined($user)){
        $method->set_error("User " . $ENV{'REMOTE_USER'} . " is not in OESS");
        return;
    }

    $model->{'description'} = $params->{'description'}{'value'};
    $model->{'prefix_limit'} = $params->{'prefix_limit'}{'value'};

    $model->{'workgroup_id'} = $params->{'workgroup_id'}{'value'};
    $model->{'vrf_id'} = $params->{'vrf_id'}{'value'} || undef;
    $model->{'name'} = $params->{'name'}{'value'};
    $model->{'provision_time'} = $params->{'provision_time'}{'value'};
    $model->{'remove_time'} = $params->{'provision_time'}{'value'};
    $model->{'created_by'} = $user->user_id();
    $model->{'last_modified'} = $params->{'provision_time'}{'value'};
    $model->{'last_modified_by'} = $user->user_id();
    $model->{'endpoints'} = ();

    #first validate the user is in the workgroup
    if(!$user->in_workgroup( $model->{'workgroup_id'})){
        $method->set_error("User is not in workgroup");
        return;
    }

    # Use $peerings to validate a local address isn't specified twice
    # on the same interface.
    my $peerings = {};

    foreach my $endpoint (@{$params->{'endpoint'}{'value'}}){
        my $obj;
        eval{
            $obj = decode_json($endpoint);
        };
        if ($@) {
            $method->set_error("Cannot decode endpoint: $@");
            return;
        }

        foreach my $peering (@{$obj->{peerings}}) {
            if (defined $peerings->{"$obj->{node} $obj->{interface} $peering->{local_ip}"}) {
                $method->set_error("Cannot have duplicate local addresses on an interface.");
                return;
            }
            $peerings->{"$obj->{node} $obj->{interface} $peering->{local_ip}"} = 1;
        }

        push(@{$model->{'endpoints'}}, $obj);
    }

    my $vrf;
    if (defined $model->{'vrf_id'} && $model->{'vrf_id'} != -1) {
        $vrf = OESS::VRF->new( db => $db, vrf_id => $model->{'vrf_id'});

        # Each endpoint in $vrf should compared against
        # $model->{endpoints}. If the vlan numbers have changed we'll
        # need to reprovision the cloud connections.

        my $cl_lookup = {};
        my $ep_lookup = {};

        foreach my $ep (@{$vrf->endpoints}) {
            if (!$ep->{interface}->{cloud_interconnect_id}) {
                next;
            }

            my $switch = $ep->{interface}->{node}->{name};
            my $interface = $ep->{interface}->{name};
            my $tag = $ep->{tag};
            my $inner_tag = $ep->{inner_tag};

            my $cl_name = "$switch-$interface";
            my $ep_name = "$switch-$interface-$tag-$inner_tag";

            $cl_lookup->{$cl_name} = 1;
            $ep_lookup->{$ep_name} = $ep;
        }

        for (my $i = 0; $i < @{$model->{endpoints}}; $i++) {
            my $switch = $model->{endpoints}->[$i]->{node};
            my $interface = $model->{endpoints}->[$i]->{interface};
            my $tag = $model->{endpoints}->[$i]->{tag};
            my $inner_tag = $model->{endpoints}->[$i]->{inner_tag};

            my $cl_name = "$switch-$interface";
            my $ep_name = "$switch-$interface-$tag-$inner_tag";

            if (!defined $cl_lookup->{$cl_name}) {
                next; # Not a cloud endpoint
            }

            if (defined $ep_lookup->{$ep_name}) {
                $model->{endpoints}->[$i]->{cloud_account_id} = $ep_lookup->{$ep_name}->{cloud_account_id};
                $model->{endpoints}->[$i]->{cloud_connection_id} = $ep_lookup->{$ep_name}->{cloud_connection_id};
                warn 'Doing nothing: ' . Dumper($ep_name);
                delete $ep_lookup->{$ep_name};
            } else {
                # Add cloud interface
                warn 'Adding: ' . Dumper($ep_name);
            }
        }

#        warn Dumper('!!!!!!!!!!!!!!!');
#        warn Dumper($vrf->endpoints);
#        warn Dumper($model->{endpoints});
#        warn Dumper('!!!!!!!!!!!!!!!');

        # if new endpoint with cloud_interconnect_id allocate
        # if missing endpoint that had a cloud_interconnect_id delete
        # if endpoint vlan changed delete and allocate

        my $ok = $vrf->update($model);
        if (!$ok) {
            $method->set_error($vrf->error());
            return;
        }

        $ok = $vrf->update_db();
        if (!$ok) {
            $method->set_error($vrf->error());
            return;
        }

        # Remove these cloud endpoints. They either were removed or
        # had their tags changed.
        foreach my $name (keys %$ep_lookup) {
            warn 'Removing: ' . Dumper($name);
            my $ep = $ep_lookup->{$name};

        warn "oooooooooooo AWS oooooooooooo";
        my $aws = OESS::Cloud::AWS->new();

        if ($ep->interface()->cloud_interconnect_type eq 'aws-hosted-connection') {
            my $aws_account = $ep->cloud_account_id;
            my $aws_connection = $ep->cloud_connection_id;
            warn "Removing aws conn $aws_connection from $aws_account";
            $aws->delete_connection($aws_connection);

        } elsif ($ep->interface()->cloud_interconnect_type eq 'aws-hosted-vinterface') {
            my $aws_account = $ep->cloud_account_id;
            my $aws_connection = $ep->cloud_connection_id;
            warn "Removing aws vint $aws_connection from $aws_account";
            $aws->delete_vinterface($aws_connection);

        } else {
            warn "Cloud interconnect type is not supported.";
        }

        }

    my $new_endpoints = [];
    foreach my $ep (@{$vrf->endpoints()}) {

        if (!$ep->interface()->cloud_interconnect_id) {
            push @$new_endpoints, $ep;
            next;
        }

        warn "oooooooooooo AWS oooooooooooo";
        my $aws = OESS::Cloud::AWS->new();

        if ($ep->interface()->cloud_interconnect_type eq 'aws-hosted-connection') {
            my $res = $aws->allocate_connection(
                $vrf->name,
                347957162513, # TODO Get AWS owner account from user
                $ep->tag,
                $ep->bandwidth . 'Mbps'
            );
            $ep->cloud_account_id(347957162513);
            $ep->cloud_connection_id($res->{ConnectionId});
            push @$new_endpoints, $ep;

        } elsif ($ep->interface()->cloud_interconnect_type eq 'aws-hosted-vinterface') {
            my $peer = $ep->peers()->[0];

            my $ip_version = 'ipv4';
            if ($peer->local_ip !~ /^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/([0-9]|[1-2][0-9]|3[0-2]))$/) {
                $ip_version = 'ipv6';
            }

            my $res = $aws->allocate_vinterface(
                347957162513, # TODO Get AWS owner account from user
                $ip_version,
                $peer->peer_ip,
                $peer->peer_asn || 55038,
                $peer->md5_key || '6f5902ac237024bdd0c176cb93063dc4',
                $peer->local_ip,
                $vrf->name,
                $ep->tag
            );
            $ep->cloud_account_id(347957162513);
            $ep->cloud_connection_id($res->{VirtualInterfaceId});
            push @$new_endpoints, $ep;

        } else {
            warn "Cloud interconnect type is not supported.";
            push @$new_endpoints, $ep;
        }
    }

    $vrf->endpoints($new_endpoints);
    $vrf->update_db();

        my $vrf_id = $vrf->vrf_id();

        my $res = vrf_del(method => $method, vrf_id => $vrf_id);
        $res = vrf_add( method => $method, vrf_id => $vrf_id);
        $res->{'vrf_id'} = $vrf_id;
        return { results => $res };
    }

    $vrf = OESS::VRF->new( db => $db, model => $model);
    my $ok = $vrf->create();
    if (!$ok) {
        $method->set_error('error creating VRF: ' . $vrf->error());
        return;
    }

    my $vrf_id = $vrf->vrf_id();
    if ($vrf_id == -1) {
        $method->set_error('error creating VRF: ' . $vrf->error());
        return;
    }

    my $new_endpoints = [];
    foreach my $ep (@{$vrf->endpoints()}) {

        if (!$ep->interface()->cloud_interconnect_id) {
            push @$new_endpoints, $ep;
            next;
        }

        warn "oooooooooooo AWS oooooooooooo";
        my $aws = OESS::Cloud::AWS->new();

        if ($ep->interface()->cloud_interconnect_type eq 'aws-hosted-connection') {
            my $res = $aws->allocate_connection(
                $vrf->name,
                347957162513, # TODO Get AWS owner account from user
                $ep->tag,
                $ep->bandwidth . 'Mbps'
            );
            $ep->cloud_account_id(347957162513);
            $ep->cloud_connection_id($res->{ConnectionId});
            push @$new_endpoints, $ep;

        } elsif ($ep->interface()->cloud_interconnect_type eq 'aws-hosted-vinterface') {
            my $peer = $ep->peers()->[0];

            my $ip_version = 'ipv4';
            if ($peer->local_ip !~ /^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/([0-9]|[1-2][0-9]|3[0-2]))$/) {
                $ip_version = 'ipv6';
            }

            my $res = $aws->allocate_vinterface(
                347957162513, # TODO Get AWS owner account from user
                $ip_version,
                $peer->peer_ip,
                $peer->peer_asn || 55038,
                $peer->md5_key,
                $peer->local_ip,
                $vrf->name,
                $ep->tag
            );
            $ep->cloud_account_id(347957162513);
            $ep->cloud_connection_id($res->{VirtualInterfaceId});
            push @$new_endpoints, $ep;

        } else {
            warn "Cloud interconnect type is not supported.";
            push @$new_endpoints, $ep;
        }
    }

    $vrf->endpoints($new_endpoints);
    $vrf->update_db();

    my $res = vrf_add( method => $method, vrf_id => $vrf_id);

    $res->{'vrf_id'} = $vrf_id;
    return {results => $res};
}

sub remove_vrf{    
    my $method = shift;
    my $params = shift;
    my $ref = shift;

    my $model = {};
    my $user = OESS::DB::User::find_user_by_remote_auth( db => $db, remote_user => $ENV{'REMOTE_USER'} );

    my $wg = $params->{'workgroup_id'}{'value'};
    my $vrf_id = $params->{'vrf_id'}{'value'} || undef;

    my $vrf = OESS::VRF->new(db => $db, vrf_id => $vrf_id);

    $user = OESS::User->new(db => $db, user_id =>  $user->{'user_id'} );

    if(!defined($user)){
        $method->set_error("User " . $ENV{'REMOTE_USER'} . " is not in OESS");
        return;
    }

    if(!defined($vrf)){
        $method->set_error("Unable to find VRF: " . $vrf_id);
        return {success => 0};
    }

    my $result;
    if(!$user->in_workgroup( $wg)){
        $method->set_error("User " . $ENV{'REMOTE_USER'} . " is not in workgroup");
        return {success => 0};
    }

    my $res = vrf_del( method => $method, vrf_id => $vrf_id);
    $res->{'vrf_id'} = $vrf_id;

    $vrf->decom(user_id => $user->user_id());

    foreach my $ep (@{$vrf->endpoints()}) {
        if (!$ep->interface()->cloud_interconnect_id) {
            next;
        }

        warn "oooooooooooo AWS oooooooooooo";
        my $aws = OESS::Cloud::AWS->new();

        if ($ep->interface()->cloud_interconnect_type eq 'aws-hosted-connection') {
            my $aws_account = $ep->cloud_account_id;
            my $aws_connection = $ep->cloud_connection_id;
            warn "Removing aws conn $aws_connection from $aws_account";
            $aws->delete_connection($aws_connection);

        } elsif ($ep->interface()->cloud_interconnect_type eq 'aws-hosted-vinterface') {
            my $aws_account = $ep->cloud_account_id;
            my $aws_connection = $ep->cloud_connection_id;
            warn "Removing aws vint $aws_connection from $aws_account";
            $aws->delete_vinterface($aws_connection);

        } else {
            warn "Cloud interconnect type is not supported.";
        }
    }
    return {results => $res};
}

sub vrf_add{
    my %params = @_;
    my $vrf_id = $params{'vrf_id'};
    my $method = $params{'method'};
    $mq->{'topic'} = 'MPLS.FWDCTL.RPC';
    
    my $cv = AnyEvent->condvar;

    warn "_send_vrf_add_command: Calling addVrf on vrf $vrf_id";
    $mq->addVrf(vrf_id => int($vrf_id), async_callback => sub {
        my $result = shift;
        $cv->send($result);
    });
    
    my $result = $cv->recv();
    
    if (defined $result->{'error'} || !defined $result->{'results'}){
        if (defined $result->{'error'}) {
            warn '_send_mpls_vrf_command: ' . $result->{'error'};
            $method->set_error($result->{'error'});
        }
      
        return {success => 0};
    }

    return {success => 1};
}


sub vrf_del{
    my %params = @_;
    my $vrf_id = $params{'vrf_id'};
    my $method = $params{'method'};
    $mq->{'topic'} = 'MPLS.FWDCTL.RPC';

    my $cv = AnyEvent->condvar;

    warn "_send_vrf_add_command: Calling delVrf on vrf $vrf_id";
    $mq->delVrf(vrf_id => int($vrf_id), async_callback => sub {
        my $result = shift;
        $cv->send($result);
                });
    
    my $result = $cv->recv();
    
    if (defined $result->{'error'} || !defined $result->{'results'}){
        if (defined $result->{'error'}) {
            warn '_send_mpls_vrf_command: ' . $result->{'error'};
            $method->set_error($result->{'error'});
        }
        
        return {success => 0};
    }
    
    return {success => 1};
}

sub edit_vrf{
    my $method = shift;
    my $params = shift;
    my $ref = shift;
    
}


sub main{

    register_ro_methods();
    register_rw_methods();
    $svc->handle_request();
}

main();
