#!/usr/bin/perl
#
##----- D-Bus OESS NSI Provisioning State Machine
##-----
##----- Handles NSI Provisioning Requests
#---------------------------------------------------------------------
#
# Copyright 2015 Trustees of Indiana University
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

package OESS::NSI::Provisioning;

use strict;
use warnings;

use DateTime;
use SOAP::Lite on_action => sub { sprintf '"http://schemas.ogf.org/nsi/2013/12/connection/service/%s"', $_[1]};
use Data::Dumper;

use GRNOC::Log;
use GRNOC::Config;
use GRNOC::WebService::Client;

use OESS::NSI::Constant;
use OESS::NSI::Utils;

use Data::UUID;

=head2 new

=cut

sub new {
    my $caller = shift;

    my $class = ref($caller);
    $class = $caller if(!$class);

    my $self = {
        'config_file' => undef,
        @_
    };

    bless($self,$class);

    $self->_init();

    return $self;
}


=head2 process_queue

=cut

sub process_queue {
    my ($self) = @_;

    log_debug("Processing Provisioning Queue.");
    while(my $message = shift(@{$self->{'provisioning_queue'}})){
        my $type = $message->{'type'};
        if($type == OESS::NSI::Constant::PROVISIONING_SUCCESS){
            log_debug("Handling Provisioning Success Message");
            $self->_provisioning_success($message->{'args'});
            next;
        }elsif($type == OESS::NSI::Constant::DO_PROVISIONING){
            log_debug("Actually provisioning");
            $self->_do_provisioning($message->{'args'});
            next;
        }elsif($type == OESS::NSI::Constant::DO_TERMINATE){
            log_debug("Actually terminating");
            $self->_do_terminate($message->{'args'});
            next;
        }elsif($type == OESS::NSI::Constant::PROVISIONING_FAILED){
            log_debug("Handling provisioning Fail Message");
            $self->_provisioning_failed($message->{'args'});
            next;
        }elsif($type == OESS::NSI::Constant::TERMINATION_SUCCESS){
            log_debug("handling terminate success");
            $self->_terminate_success($message->{'args'});
            next;
        }elsif($type == OESS::NSI::Constant::TERMINATION_FAILED){
            log_debug("handling termination failed!");
            $self->_terminate_failure($message->{'args'});
            next;
        }elsif($type == OESS::NSI::Constant::DO_RELEASE){
            $self->_do_release($message->{'args'});
            next;
        }elsif($type == OESS::NSI::Constant::RELEASE_FAILED){
            log_debug("handling release failed");
            $self->_release_failed($message->{'args'});
            next;
        }elsif($type == OESS::NSI::Constant::RELEASE_SUCCESS){
            log_debug("handling release success");
            $self->_release_confirmed($message->{'args'});
            next;
        }else{
            log_error("Unknown type: " . $type);
            next;
        }

    }
}

=head2 provision

=cut

sub provision{
    my ($self, $args) = @_;

    my $connection_id = $args->{'connectionId'};
    
    log_info("provision: connectionId: " . $connection_id);

    if(!defined($connection_id) || $connection_id eq ''){
        log_error("Missing connection id!");
        return OESS::NSI::Constant::MISSING_REQUEST_PARAMETERS;
    }

    push(@{$self->{'provisioning_queue'}}, {type => OESS::NSI::Constant::DO_PROVISIONING, args => $args});
    return OESS::NSI::Constant::SUCCESS;

}

sub _do_provisioning{
    my ($self, $args) = @_;
    
    my $connection_id = $args->{'connectionId'};
    
    log_debug("do provisioning: " . $connection_id);

    my $ckt = $self->_get_circuit_details($connection_id);

    if(!defined($ckt)){
        log_error("Unable to fetch circuit details: " . $connection_id);
        return;
    }

    $self->{'websvc'}->set_url($self->{'websvc_location'} . "/provisioning.cgi");

    my $res = $self->{'websvc'}->foo( action => 'provision_circuit',
                                      state => 'provisioned',
                                      circuit_id => $connection_id,
                                      workgroup_id => $self->{'workgroup_id'},
                                      description => $ckt->{'description'},
                                      name => $ckt->{'name'},
                                      link => $ckt->{'link'},
                                      backup_link => $ckt->{'backup_link'},
                                      bandwidth => $ckt->{'bandwidth'},
                                      provision_time => -1,
                                      remove_time => 1,
                                      node => $ckt->{'node'},
                                      interface => $ckt->{'interface'},
                                      tag => $ckt->{'tag'} );

    log_debug("results of provision circuit: " .  Data::Dumper::Dumper($res));

    if(defined($res) && defined($res->{'results'})){
        push(@{$self->{'provisioning_queue'}}, {type => OESS::NSI::Constant::PROVISIONING_SUCCESS, args => $args});
        return OESS::NSI::Constant::SUCCESS;
    }

    log_error("Error provisioning circuit: " . $res->{'error'});
    push(@{$self->{'provisioning_queue'}}, {type => OESS::NSI::Constant::PROVISIONING_FAILED, args => $args});
    return OESS::NSI::Constant::SUCCESS;
}

sub _get_circuit_details{
    my $self = shift;
    my $circuit_id = shift;

    $self->{'websvc'}->set_url($self->{'websvc_location'} . "/data.cgi");
    
    log_debug("fetching circuit details");

    my $circuit = $self->{'websvc'}->foo( action => "get_circuit_details",
					  circuit_id => $circuit_id);

    log_debug("Circuit Details: " . Data::Dumper::Dumper($circuit));

    my $scheduled_actions = $self->{'websvc'}->foo( action => "get_circuit_scheduled_events",
                                                    circuit_id => $circuit_id);
    
    log_debug("Circuit scheduled events: " . Data::Dumper::Dumper($scheduled_actions));

    if(!defined($circuit) && !defined($circuit->{'results'})){
        log_error("circuit $circuit_id was not defined");
	return OESS::NSI::Constant::ERROR;
    }

    $circuit = $circuit->{'results'};
    
    my @links = ();
    foreach my $link (@{$circuit->{'links'}}){
	push(@links, $link->{'name'});
    }

    my @backup_links = ();
    foreach my $link (@{$circuit->{'backup_links'}}){
	push(@backup_links, $link->{'name'});
    }

    my @nodes = ();
    my @ints = ();
    my @tags = ();

    foreach my $ep (@{$circuit->{'endpoints'}}){
	push(@nodes,$ep->{'node'});
	push(@ints,$ep->{'interface'});
	push(@tags,$ep->{'tag'});
    }
    
    my $ckt = { state => $circuit->{'state'},
                circuit_id => $circuit->{'circuit_id'},
                workgroup_id => $circuit->{'workgroup'}->{'workgroup_id'},
                description => $circuit->{'description'},
                name => $circuit->{'name'},
                remote_url => $circuit->{'remote_url'},
                remote_requester => $circuit->{'remote_requester'},
                link => \@links,
                backup_link => \@backup_links,
                bandwidth => $circuit->{'bandwidth'},
                provision_time => $circuit->{'provision_time'},
                remove_time => $circuit->{'remove_time'},
                node => \@nodes,
                interface => \@ints,
                tag => \@tags
    };
    
    return $ckt;


}

=head2 terminate

=cut

sub terminate{
    my ($self, $args) = @_;

    my $connection_id = $args->{'connectionId'};

    log_info("terminate: connectionId: " . $connection_id);

    if(!defined($connection_id) || $connection_id eq ''){
        log_error("Missing connection id!");
        return OESS::NSI::Constant::MISSING_REQUEST_PARAMETERS;
    }

    push(@{$self->{'provisioning_queue'}}, {type => OESS::NSI::Constant::DO_TERMINATE, args => $args});
    return OESS::NSI::Constant::SUCCESS;
}
    
sub _do_terminate{
    my ($self, $args) = @_;

    my $connection_id = $args->{'connectionId'};

    log_debug("do terminate: $connection_id");

    $self->{'websvc'}->set_url($self->{'websvc_location'} . "/provisioning.cgi");
    my $res = $self->{'websvc'}->foo( action => "remove_circuit",
				      circuit_id => $connection_id,
				      workgroup_id => $self->{'workgroup_id'},
				      remove_time => -1);

    log_debug("Results of remove_circuit: " . Data::Dumper::Dumper($res));

    if(defined($res) && defined($res->{'results'})){
        log_info("Termination success: connection_id: " . $connection_id);
	push(@{$self->{'provisioning_queue'}}, {type => OESS::NSI::Constant::TERMINATION_SUCCESS, args => $args});
        return OESS::NSI::Constant::SUCCESS;
    }

    log_error("Unable to remove circuit: " . $res->{'error'});
    push(@{$self->{'provisioning_queue'}}, {type => OESS::NSI::Constant::TERMINATION_FAILED, args => $args});
    return OESS::NSI::Constant::ERROR;
}

sub _provisioning_success{
    my ($self, $data) = @_;

    my $soap = OESS::NSI::Utils::build_client( proxy =>$data->{'header'}->{'replyTo'},ssl => $self->{'ssl'});

    my $nsiheader = OESS::NSI::Utils::build_header($data->{'header'});

    eval{
        my $soap_response = $soap->provisionConfirmed($nsiheader, SOAP::Data->name(connectionId => $data->{'connectionId'})->type(''));
    };
    log_error("Unable to send provisionConfirmed message: " . Data::Dumper::Dumper($@)) if $@;
}

sub _terminate_success{

    my ($self, $data) = @_;

    my $soap = OESS::NSI::Utils::build_client( proxy =>$data->{'header'}->{'replyTo'},ssl => $self->{'ssl'});

    my $nsiheader = OESS::NSI::Utils::build_header($data->{'header'});
    eval{
        my $soap_response = $soap->terminateConfirmed($nsiheader, SOAP::Data->name(connectionId => $data->{'connectionId'})->type(''));
    };
    log_error("Unable to send terminateConfirmed message: " . Data::Dumper::Dumper($@)) if $@;
}


sub _init {
    my ($self) = @_;

    log_debug("Creating new Config object from $self->{'config_file'}");
    my $config = new GRNOC::Config(
        'config_file' => $self->{'config_file'},
        'force_array' => 0
        );

    $self->{'config'} = $config;

    log_debug("Creating new WebService Client object");
    my $websvc = new GRNOC::WebService::Client(
        'cookieJar' => '/tmp/oess-nsi-cookies.dat',
        'debug' => $self->{'debug'}
        );

    $websvc->{'debug'} = 0;

    $self->{'websvc'} = $websvc;

    $self->{'websvc_user'}     = $self->{'config'}->get('/config/oess-service/@username');
    $self->{'websvc_pass'}     = $self->{'config'}->get('/config/oess-service/@password');
    $self->{'websvc_realm'}    = $self->{'config'}->get('/config/oess-service/@realm');
    $self->{'websvc_location'} = $self->{'config'}->get('/config/oess-service/@web-service');

    $self->{'websvc'}->set_credentials(
        'uid' => $self->{'websvc_user'},
        'passwd' => $self->{'websvc_pass'},
	'realm' => $self->{'websvc_realm'}
        );

    $self->{'ssl'} = $self->{'config'}->get('/config/ssl');
    if(defined($self->{'ssl'}->{'enabled'}) && $self->{'ssl'}->{'enabled'} ne '' && $self->{'ssl'}->{'enabled'} eq 'true'){
        $self->{'ssl'}->{'enabled'} = 1;
    }

    $self->{'workgroup_id'} = $self->{'config'}->get('/config/oess-service/@workgroup-id');

    $self->{'ug'} = Data::UUID->new;

    $self->{'provisioning_queue'} = [];
}


sub _release_failed{
    my ($self, $args) = @_;

    log_error("RELEASE FAILED!!");
}

sub _do_release{
    my ($self, $args) = @_;

    my $connection_id = $args->{'connectionId'};
   

    my $ckt = $self->_get_circuit_details($connection_id);

    $self->{'websvc'}->set_url($self->{'websvc_location'} . "/provisioning.cgi");

    my $res = $self->{'websvc'}->foo( action => 'provision_circuit',
                                      state => 'reserved',
                                      circuit_id => $connection_id,
                                      workgroup_id => $self->{'workgroup_id'},
                                      description => $ckt->{'description'},
                                      name => $ckt->{'name'},
                                      link => $ckt->{'link'},
                                      backup_link => $ckt->{'backup_link'},
                                      bandwidth => $ckt->{'bandwidth'},
                                      provision_time => $ckt->{'provision_time'},
                                      remove_time => $ckt->{'remove_time'},
                                      node => $ckt->{'node'},
                                      interface => $ckt->{'interface'},
                                      tag => $ckt->{'tag'});
    
    if(defined($res) && defined($res->{'results'})){
        log_info("Release connectionId: " . $args->{'connectionId'} . " success!");
        push(@{$self->{'provisioning_queue'}}, {type => OESS::NSI::Constant::RELEASE_SUCCESS, args => $args});
        return OESS::NSI::Constant::SUCCESS;
    }

    log_error("Unable to remove circuit: " . $res->{'error'});
    push(@{$self->{'provisioning_queue'}}, {type => OESS::NSI::Constant::RELEASE_FAILED, args => $args});
    return OESS::NSI::Constant::ERROR;

}

=head2 release

=cut

sub release{
    my ($self, $args) = @_;
    log_info("release connectionId: " . $args->{'connectionId'});
    push(@{$self->{'provisioning_queue'}}, {type => OESS::NSI::Constant::DO_RELEASE, args => $args});
    return OESS::NSI::Constant::SUCCESS;
}

sub _build_dataPlaneStatus{
    my $circuit_details = shift;
    
    my $active = 'false';
    if($circuit_details->{'state'} eq 'active'){
        $active = 'true';
    }

    return SOAP::Data->name( dataPlaneStatus => \SOAP::Data->value( SOAP::Data->name( active => $active)->type(''),
                                                                    SOAP::Data->name( version => 0)->type(''),
                                                                    SOAP::Data->name( versionConsistent => 'true')->type('')));
                      
}

=head2 dataPlaneStateChange

=cut

sub dataPlaneStateChange{
    my $self = shift;
    my $circuit = shift;

    log_info("Circuit Modification detected: connectionId: " . $circuit);

    my $ckt = $self->_get_circuit_details($circuit);

    if(!defined($ckt->{'remote_url'}) || !defined($ckt->{'remote_requester'})){
        log_error("Circuit in NSI workgroup, did not have remote_url or remote_requester specified!\n");
        return;
    }

    my $soap = OESS::NSI::Utils::build_client( proxy => $ckt->{'remote_url'}, ssl => $self->{'ssl'});

    my $nsiheader = OESS::NSI::Utils::build_header({ requesterNSA => $ckt->{'remote_requester'} });
    eval{
        my $resp = $soap->dataPlaneStateChange($nsiheader, SOAP::Data->name( connectionId => $circuit)->type(''),
                                               SOAP::Data->name( notificationId => 1)->type(''),
                                               SOAP::Data->name( timeStamp => _timestampNow() )->type(''),
                                               _build_dataPlaneStatus($ckt ));
        
    };
    log_error("Unable to send dataPlaneStateChange message: " . Data::Dumper::Dumper($@)) if $@;
}

sub _timestampNow{
    
    my $dt = DateTime->now();
    return $dt->strftime( "%F" ) . "T" . $dt->strftime( "%T" ) . "Z";

}

sub _release_confirmed{
    my ($self, $data) = @_;

    log_info("releaseConfirmed connectionId: " . $data->{'connectionId'});

    my $soap = OESS::NSI::Utils::build_client( proxy =>$data->{'header'}->{'replyTo'},ssl => $self->{'ssl'});
    my $nsiheader = OESS::NSI::Utils::build_header($data->{'header'});
    my $soap_response = $soap->releaseConfirmed($nsiheader, SOAP::Data->name(connectionId => $data->{'connectionId'}));
}

1;
