#!/usr/bin/perl -I /home/aragusa/OESS/perl-lib/OESS/lib

use strict;
use warnings;

use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use JSON;
use Log::Log4perl;

use GRNOC::WebService::Method;
use GRNOC::WebService::Dispatcher;

use OESS::RabbitMQ::Client;
use OESS::Cloud;
use OESS::Cloud::AWS;
use OESS::DB;
use OESS::DB::Entity;
use OESS::VRF;


Log::Log4perl::init_and_watch('/etc/oess/logging.conf',10);


my $db = OESS::DB->new();
my $svc = GRNOC::WebService::Dispatcher->new();
my $mq = OESS::RabbitMQ::Client->new( topic    => 'OF.FWDCTL.RPC',
                                      timeout  => 120 );

my $log_client = OESS::RabbitMQ::Client->new( topic    => 'OF.FWDCTL.event',
                                              timeout  => 15 );

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
        name            => 'skip_cloud_provisioning',
        pattern         => $GRNOC::WebService::Regex::INTEGER,
        required        => 0,
        description     => "If editing an existing VRF specify the ID otherwise leave blank for new VRF.",
        default         => 0
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
    if(!$user->in_workgroup( $workgroup_id) && !$user->is_admin()){
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

    my $user = OESS::DB::User::find_user_by_remote_auth(db => $db, remote_user => $ENV{'REMOTE_USER'});
    $user = OESS::User->new(db => $db, user_id =>  $user->{'user_id'} );

    if (!defined $user) {
        $method->set_error("User $ENV{'REMOTE_USER'} is not in OESS.");
        return;
    }

    my $model = {};
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

    # User must be in workgroup or an admin to continue
    if (!$user->in_workgroup($model->{'workgroup_id'}) && !$user->is_admin()){
        $method->set_error("User is not in workgroup $model->{workgroup_id}.");
        return;
    }

    # Modified VRFs should already have selected the appropriate
    # endpoints for any of their cloud connections. This has not been
    # been done for new VRFs.
    my $selected_endpoints = [];
    my $db = OESS::DB->new;

    # Use $peerings to validate a local address isn't specified twice
    # on the same interface. Cloud peerings are provided/overwritten
    # with sane defaults.
    my $peerings = {};
    my $last_octet = 2;

    foreach my $value (@{$params->{endpoint}{value}}) {
        my $endpoint;
        eval{
            $endpoint = decode_json($value);
        };
        if ($@) {
            $method->set_error("Cannot decode endpoint: $@");
            return;
        }

        my $entity = OESS::DB::Entity::fetch(db=> $db, name => $endpoint->{entity});
        my $interfaces = $entity->{interfaces};

        # Node and Interface user selections must be respected by the
        # endpoint selection algos. These selections indicate either
        # an endpoint modification or explicit selection by user.
        if (defined $endpoint->{interface} && defined $endpoint->{node}) {
            push @$selected_endpoints, $endpoint;
            next;
        }

        $endpoint->{cloud_interconnect_type} = $interfaces->[0]->{cloud_interconnect_type};

        if (!defined $endpoint->{cloud_interconnect_type} || $endpoint->{cloud_interconnect_type} eq '') {
            $endpoint->{interface} = $interfaces->[0]->{name};
            $endpoint->{node} = $interfaces->[0]->{node}->{name};
            $endpoint->{cloud_interconnect_id} = $interfaces->[0]->{cloud_interconnect_id};

            push @$selected_endpoints, $endpoint;
        }
        elsif ($endpoint->{cloud_interconnect_type} eq 'aws-hosted-connection') {
            $endpoint->{interface} = $interfaces->[0]->{name};
            $endpoint->{node} = $interfaces->[0]->{node}->{name};
            $endpoint->{cloud_interconnect_id} = $interfaces->[0]->{cloud_interconnect_id};

            push @$selected_endpoints, $endpoint;
        }
        elsif ($endpoint->{cloud_interconnect_type} eq 'aws-hosted-vinterface') {
            $endpoint->{interface} = $interfaces->[0]->{name};
            $endpoint->{node} = $interfaces->[0]->{node}->{name};
            $endpoint->{cloud_interconnect_id} = $interfaces->[0]->{cloud_interconnect_id};

            push @$selected_endpoints, $endpoint;
        }
        elsif ($endpoint->{cloud_interconnect_type} eq 'azure-express-route') {
            $endpoint->{interface} = $interfaces->[0]->{name};
            $endpoint->{node} = $interfaces->[0]->{node}->{name};
            $endpoint->{cloud_interconnect_id} = $interfaces->[0]->{cloud_interconnect_id};

            # Azure requires a second interface for all connections
            my $endpoint2 = {
                cloud_account_id => $endpoint->{cloud_account_id},
                cloud_interconnect_type => $endpoint->{cloud_interconnect_type},
                bandwidth => $endpoint->{bandwidth},
                peerings => [{ version => 4 }],
                entity => $endpoint->{entity},
                tag => $endpoint->{tag},
                interface => $interfaces->[1]->{name},
                node => $interfaces->[1]->{node}->{name},
                cloud_interconnect_id => $interfaces->[1]->{cloud_interconnect_id}
            };

            # my $primary_prefix = '192.168.100.248/30';
            # my $secondary_prefix = '192.168.100.252/30';
            if ($endpoint->{cloud_interconnect_id} =~ /PRI/) {
                $endpoint->{peerings} = [{
                    asn => 12076,
                    key => '',
                    local_ip => '192.168.100.249/30',
                    peer_ip  => '192.168.100.250/30',
                    version  => 4
                }];
                $endpoint2->{peerings} = [{
                    asn => 12076,
                    key => '',
                    local_ip => '192.168.100.253/30',
                    peer_ip  => '192.168.100.254/30',
                    version  => 4
                }];
            } else {
                $endpoint->{peerings} = [{
                    asn => 12076,
                    key => '',
                    local_ip => '192.168.100.253/30',
                    peer_ip  => '192.168.100.254/30',
                    version  => 4
                }];
                $endpoint2->{peerings} = [{
                    asn => 12076,
                    key => '',
                    local_ip => '192.168.100.249/30',
                    peer_ip  => '192.168.100.250/30',
                    version  => 4
                }];
            }

            push @$selected_endpoints, $endpoint;
            push @$selected_endpoints, $endpoint2;
        }
        elsif ($endpoint->{cloud_interconnect_type} eq 'gcp-partner-interconnect') {
            # GCP pairing keys define which endpoint should be used
            my @part = split(/\//, $endpoint->{cloud_account_id});
            my $key_zone = 'zone' . $part[2];

            foreach my $intf (@$interfaces) {
                @part = split(/-/, $intf->cloud_interconnect_id);
                my $conn_zone = $part[4];

                if ($conn_zone eq $key_zone) {
                    $endpoint->{interface} = $intf->{name};
                    $endpoint->{node} = $intf->{node}->{name};
                    $endpoint->{cloud_interconnect_id} = $intf->{cloud_interconnect_id};
                    last;
                }
            }

            push @$selected_endpoints, $endpoint;
        }
        else {
            warn "Skipping endpoint with unknown interconnect type '$endpoint->{cloud_interconnect_type}' specified.";
        }
    }

    # Use $peerings to validate a local address isn't specified twice
    # on the same interface. Cloud peerings are provided/overwritten
    # with sane defaults.
    my $last_octet = 2;
    my $peerings = {};

    foreach my $endpoint (@$selected_endpoints) {
        foreach my $peering (@{$endpoint->{peerings}}) {

            if (defined $peerings->{"$endpoint->{node} $endpoint->{interface} $peering->{local_ip}"}) {
                $method->set_error("Cannot have duplicate local addresses on an interface.");
                return;
            }

            # User defined or pre-defined (eg. azure) peering
            if ($peering->{local_ip}) {
                $peerings->{"$endpoint->{node} $endpoint->{interface} $peering->{local_ip}"} = 1;
                next;
            }

            # Peerings not auto-generated for non-cloud endpoints
            if (defined $endpoint->{cloud_account_id} && $endpoint->{cloud_account_id} eq '') {
                next;
            }
            if (!defined $endpoint->{cloud_account_id}) {
                next;
            }

            $peering->{asn} = (!defined $peering->{asn} || $peering->{asn} eq '') ? 64512 : $peering->{asn};
            $peering->{key} = (!defined $peering->{key} || $peering->{key} eq '') ? md5_hex(rand) : $peering->{key};
            if ($peering->{version} == 4) {
                $peering->{local_ip} = '172.31.254.' . $last_octet . '/31';
                $peering->{peer_ip}  = '172.31.254.' . ($last_octet + 1) . '/31';
            } else {
                $peering->{local_ip} = 'fd28:221e:28fa:61d3::' . $last_octet . '/127';
                $peering->{peer_ip}  = 'fd28:221e:28fa:61d3::' . ($last_octet + 1) . '/127';
            }

            # Assuming we use .2 and .3 the first time around. We can
            # use .4 and .5 on the next peering.
            $last_octet += 2;
            $peerings->{"$endpoint->{node} $endpoint->{interface} $peering->{local_ip}"} = 1;
        }

        push(@{$model->{endpoints}}, $endpoint);
    }

    # Handle Jumbo frame support here. By default the MTU on all
    # endpoints should be 9000.
    #
    # AWS hosted vInterfaces are slightly different; Valid MTUs are
    # 9001 (default) and 1500 if jumbo frames are disabled.
    foreach my $endpoint (@$selected_endpoints) {
        $endpoint->{mtu} = 9000;

        if ($endpoint->{cloud_interconnect_type} eq 'aws-hosted-vinterface') {
            if (!defined $endpoint->{jumbo} || $endpoint->{jumbo} == 1) {
                $endpoint->{mtu} = 9001;
            } else {
                $endpoint->{mtu} = 1500;
            }
        }
    }

    if (defined $model->{'vrf_id'} && $model->{'vrf_id'} != -1) {
        return _edit_vrf(
            method => $method,
            db => $db,
            model => $model,
            skip_cloud_provisioning => $params->{'skip_cloud_provisioning'}{'values'}
        );
    }

    my $vrf;
    eval {
        $vrf = OESS::VRF->new(db => $db, model => $model);
    };
    if ($@) {
        $method->set_error("$@");
        return;
    }

    if (!$params->{skip_cloud_provisioning}{value}) {
        eval {
            my $setup_endpoints = OESS::Cloud::setup_endpoints($vrf->name, $vrf->endpoints);
            $vrf->endpoints($setup_endpoints);
        };
        if ($@) {
            $method->set_error("$@");
            return;
        }
    } else {
        warn 'Skipping cloud provisioning!';
        foreach my $endpoint (@{$vrf->endpoints}) {
            $endpoint->cloud_connection_id('');
        }
    }

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

    my $res = vrf_add(method => $method, vrf_id => $vrf_id);

    eval {
        my $vrf_details = $vrf->to_hash();
        $log_client->vrf_notification(
            type => 'provisioned',
            reason => 'Created by ' . $ENV{'REMOTE_USER'},
            vrf => $vrf_id,
            no_reply  => 1
        );
    };
    return {results => $res};
}

sub _edit_vrf{
    my %params = @_;
    my $method = $params{'method'};
    my $model = $params{'model'};
    my $db = $params{'db'};
    my $skip_cloud_provisioning = $params{'skip_cloud_provisioning'};

    my $vrf = OESS::VRF->new( db => $db, vrf_id => $model->{'vrf_id'} );

    my @new_endpoints;

    #first lets update all the "basic" stuff like name, description, etc...

    my @cloud_adds;
    my @cloud_dels;

    foreach my $ep (@{$vrf->endpoints()}){
        my $found = 0;
        for( my $i=0; $i<=$#{$model->{'endpoints'}}; $i++){
            my $new_ep = $model->{'endpoints'}->[$i];
            if($new_ep->{'node'} eq $ep->node()->{'name'} && $new_ep->{'interface'} eq $ep->interface()->name() && $new_ep->{'tag'} eq $ep->tag()){
                #found the same endpoint..
                $found = 1;
                #remove the endpoint from the endpoint list
                splice(@{$model->{'endpoints'}},$i,1);

                my @new_peers;
                #now compare the Peers
                foreach my $peer (@{$ep->peers()}){
                    my $peer_found = 0;
                    for( my $j =0 ; $j<= $#{$new_ep->{'peerings'}}; $j++){
                        my $new_peer = $new_ep->{'peerings'}->[$j];
                        next if($new_peer->{'peer_ip'} ne $peer->peer_ip());
                        next if($new_peer->{'local_ip'} ne $peer->local_ip());
                        next if($new_peer->{'asn'} ne $peer->peer_asn());
                        next if($new_peer->{'key'} ne $peer->md5_key());
                        $peer_found = 1;

                        #remove the peering from the new_ep
                        splice(@{$new_ep->{'peerings'}},$j,1);
                        last;
                    }
                    if($peer_found){
                        push(@new_peers, $peer);
                    }
                }

                foreach my $model_peer (@{$new_ep->{'peerings'}}){
                    my $peer = OESS::Peer->new( model => $model_peer, db => $db );
                    push(@new_peers, $peer);
                }

                $ep->peers(\@new_peers);

            }
        }
        if($found){
            #we found the endpoint and updated any peerings
            push(@new_endpoints, $ep);
            #there should be no need to do CLOUD stuff here! (unless we added a second peering)
        }else{
            #if it isn't found we don't add it to new_endpoints
            #is this a cloud connection?
            if($ep->{'cloud_account_id'}){
                push(@cloud_dels, $ep);
            }
        }
    }

    if($#{$model->{'endpoints'}} >= 0){
        foreach my $model_ep (@{$model->{'endpoints'}}){
            #create an Endpoint object!
            my $ep = OESS::Endpoint->new( db => $db, model => $model_ep, type => 'vrf');
            push(@new_endpoints, $ep);
            if(defined($ep->{'cloud_account_id'})){
                push(@cloud_adds, $ep);
            }
        }
    }

    #$vrf->endpoints(\@new_endpoints);

    #our VRF object has the endpoints... now make any cloud changes (if necessary)
    if(!$skip_cloud_provisioning){
        eval {
            OESS::Cloud::cleanup_endpoints(\@cloud_dels);

            my $setup_endpoints = OESS::Cloud::setup_endpoints($vrf->name, \@cloud_adds);

            foreach my $ep (@new_endpoints){
                foreach my $new_ep (@{$setup_endpoints}){
                    if($ep->node()->name() eq $new_ep->node()->name() && $ep->interface()->name() eq $new_ep->interface()->name() && $ep->tag() eq $new_ep->tag()){
                        $ep->{'cloud_connection_id'} = $new_ep->{'cloud_connection_id'};
                    }
                }
            }
        };
        if ($@) {
            $method->set_error("$@");
            return;
        }
    }

    $vrf->endpoints(\@new_endpoints);

    #ok now that we made it this far... 4 steps to complete...
    #1. remove the existing VRF from the network
    #2. update the model in the DB
    #3. add the new model to the network
    #4. handle any failures
    my $vrf_id = $vrf->vrf_id();

    my $res = vrf_del(method => $method, vrf_id => $vrf_id);

    my $ok = $vrf->update_db();
    if(!$ok){
        #whoops... failed to update... re-add to network and signal to user
        vrf_add(method => $method, vrf_id => $vrf_id);
        $method->set_error("Failed to update database with VRF. Please try again later.");
        return;
    }

    #ok we made it this far... and have updated our DB now to update the cache
    _update_cache(vrf_id => $vrf_id);

    #finally we get to adding it to the network again!
    $res = vrf_add(method => $method, vrf_id => $vrf_id);

    eval{
        my $vrf_details = $vrf->to_hash();
        $vrf_details->{'status'} = 'up';
        $vrf_details->{'reason'} = 'edited';
        $vrf_details->{'type'} = 'modified';
        $log_client->vrf_notification(type => 'modified',
                                      reason => 'Edited by ' . $ENV{'REMOTE_USER'},
                                      vrf => $vrf->vrf_id(),
                                      no_reply  => 1);
    };

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
    if(!$user->in_workgroup( $wg) && !$user->is_admin()){
        $method->set_error("User " . $ENV{'REMOTE_USER'} . " is not in workgroup");
        return {success => 0};
    }

    eval {
        OESS::Cloud::cleanup_endpoints($vrf->endpoints);
    };
    if ($@) {
        $method->set_error("$@");
        return;
    }

    my $res = vrf_del(method => $method, vrf_id => $vrf_id);
    $res->{'vrf_id'} = $vrf_id;

    $vrf->decom(user_id => $user->user_id());

    #send the update cache to the MPLS fwdctl
    _update_cache(vrf_id => $vrf_id);

    eval{
        my $vrf_details = $vrf->to_hash();
        $log_client->vrf_notification(type => 'removed',
                                      reason => 'Removed by ' . $ENV{'REMOTE_USER'},
                                      vrf => $vrf->vrf_id(),
                                      no_reply  => 1);
    };

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
            $method->set_error($result->{'error'});
        } else {
            $method->set_error("Did not get response from addVRF.");
        }
        return {success => 0, vrf_id => $vrf_id};
    }

    return {success => 1, vrf_id => $vrf_id};
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
            $method->set_error($result->{'error'});
        } else {
            $method->set_error("Did not get response from delVRF.");
        }
        return {success => 0, vrf_id => $vrf_id};
    }
    
    return {success => 1, vrf_id => $vrf_id};
}

sub _update_cache{
    my %args = @_;

    if(!defined($args{'vrf_id'})){
        $args{'vrf_id'} = -1;
    }

    my $err = undef;

    if (!defined $mq) {
        $err = "Couldn't create RabbitMQ client.";
        return;
    } else {
        $mq->{'topic'} = 'MPLS.FWDCTL.RPC';
    }
    my $cv = AnyEvent->condvar;
    $mq->update_cache(vrf_id => $args{'vrf_id'},
                      async_callback => sub {
                          my $result = shift;
                          $cv->send($result);
                      });

    my $result = $cv->recv();

    if (!defined $result) {
        warn "Error occurred while calling update_cache: Couldn't contact MPLS.FWDCTL via RabbitMQ.";
        return undef;
    }
    if (defined $result->{'error'}) {
        warn "Error occurred while calling update_cache: $result->{'error'}";
        return undef;
    }
    if (defined $result->{'results'}->{'error'}) {
        warn "Error occured while calling update_cache: " . $result->{'results'}->{'error'};
        return undef;
    }

    return $result->{'results'}->{'status'};
}


sub main{

    register_ro_methods();
    register_rw_methods();
    $svc->handle_request();
}

main();
