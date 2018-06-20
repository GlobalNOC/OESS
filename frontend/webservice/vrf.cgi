#!/usr/bin/perl -I /home/aragusa/OESS/perl-lib/OESS/lib

use strict;
use warnings;

use GRNOC::WebService::Method;
use GRNOC::WebService::Dispatcher;

use OESS::RabbitMQ::Client;
use OESS::DB;
use OESS::VRF;


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

    #first validate the user is in the workgroup
    if(!$user->in_workgroup( $workgroup_id)){
        $method->set_error("User is not in workgroup");
        return;
    }
    
    my $vrfs = OESS::DB::VRF::get_vrfs( db => $db, workgroup_id => $workgroup_id, state => 'active');
    
    my @vrfs;
    foreach my $vrf (@$vrfs){
        push(@vrfs, OESS::VRF->new( db => $db, vrf_id => $vrf->{'vrf_id'})->to_hash());
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

    $model->{'description'} = $params->{'name'}{'value'};
    $model->{'prefix_limit'} = $params->{'prefix_limit'}{'value'};

    $model->{'workgroup_id'} = $params->{'workgroup_id'}{'value'};
    $model->{'vrf_id'} = $params->{'vrf_id'}{'value'} || undef;
    $model->{'name'} = $params->{'name'}{'value'};
    $model->{'provision_time'} = $params->{'provision_time'}{'value'};
    $model->{'remove_time'} = $params->{'provision_time'}{'value'};
    $model->{'created_by'} = $user->user_id();
    $model->{'last_modified_by'} = $user->user_id();

    $model->{'endpoints'} = ();
    foreach my $endpoint (@{$params->{'endpoint'}{'value'}}){
        my $obj;
        eval{
            $obj = decode_json($endpoint);
        };
        
        push(@{$model->{'endpoints'}}, $obj);
    }

    #first validate the user is in the workgroup
    if(!$user->in_workgroup( $model->{'workgroup_id'})){
        $method->set_error("User is not in workgroup");
        return;
    }

    my $vrf = OESS::VRF->new( db => $db, vrf_id => -1, model => $model);
    #warn Dumper($vrf);
    $vrf->create();
    
    my $vrf_id = $vrf->vrf_id();
    if($vrf_id == -1){

        return {results => {'success' => 0}, error => {'error creating VRF: ' . $vrf->error()}};

    }else{

        my $res = vrf_add( method => $method, vrf_id => $vrf_id);
        $res->{'vrf_id'} = $vrf_id;
        return {results => $res};
                
    }

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

    if(!defined($vrf)){
        $method->set_error("Unable to find VRF: " . $vrf_id);
        return {success => 0};
    }

    my $result;
    if(!$user->is_in_workgroup( $wg)){
        $method->set_error("User " . $ENV{'REMOTE_USER'} . " is not in workgroup");
        return {success => 0};
    }

    my $res = vrf_del( method => $method, vrf_id => $vrf_id);
    $res->{'vrf_id'} = $vrf_id;
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
