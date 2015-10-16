#!/usr/bin/perl
#
##----- D-Bus OESS NSI Reservation State Machine
##-----
##----- Handles NSI Reservation Requests
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

use SOAP::Lite on_action => sub { sprintf '"http://schemas.ogf.org/nsi/2013/12/connection/service/%s"', $_[1]};

use GRNOC::Log;
use GRNOC::Config;
use GRNOC::WebService::Client;

use OESS::NSI::Constant;

use Data::Dumper;

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


sub process_queue {
    my ($self) = @_;

    log_debug("Processing Provisioning Queue.");
    warn "Processing provisioning queue: " . Data::Dumper::Dumper($self->{'provisioning_queue'});
    while(my $message = shift(@{$self->{'provisioning_queue'}})){
        my $type = $message->{'type'};

        if($type == OESS::NSI::Constant::PROVISIONING_SUCCESS){
            log_debug("Handling Reservation Success Message");

            $self->_provisioning_success($message->{'args'});
            next;
        }
        elsif($type == OESS::NSI::Constant::PROVISIONING_FAILED){
            log_debug("Handling Reservation Fail Message");

            $self->_provisioning_failed($message->{'args'});
            next;
        }elsif($type == OESS::NSI::Constant::TERMINATION_SUCCESS){
            log_debug("handling reservation commit success");

            $self->_terminate_success($message->{'args'});
            next;
        }

    }
}

sub provision{
    my ($self, $args) = @_;
    warn "PROVISIONING\n";
    
    warn Data::Dumper::Dumper($args);
    my $connection_id = $args->{'connectionId'};
    
    if(!defined($connection_id) || $connection_id eq ''){
        log_error("Missing connection id!");
        warn "FAILED!\n";
        return OESS::NSI::Constant::MISSING_REQUEST_PARAMETERS;
    }
    
    push(@{$self->{'provisioning_queue'}}, {type => OESS::NSI::Constant::PROVISIONING_SUCCESS, args => $args});
    
    return OESS::NSI::Constant::SUCCESS;
}    


sub terminate{
    my ($self, $args) = @_;

    my $connection_id = $args->{'connectionId'};

    if(!defined($connection_id) || $connection_id eq ''){
        log_error("Missing connection id!");
        warn "FAILED!\n";
        return OESS::NSI::Constant::MISSING_REQUEST_PARAMETERS;
    }

    push(@{$self->{'provisioning_queue'}}, {type => OESS::NSI::Constant::TERMINATION_SUCCESS, args => $args});

    return OESS::NSI::Constant::SUCCESS;
    
}

sub _provisioning_success{
    my ($self, $data) = @_;

    my $soap = SOAP::Lite->new->proxy($data->{'header'}->{'replyTo'})->ns('http://schemas.ogf.org/sni/2013/12/framework/types','ftypes')->ns('http://schemas.ogf.org/nsi/2013/12/framework/headers','header')->ns('http://schemas.ogf.org/nsi/2013/12/connection/types','ctypes');
    my $header = SOAP::Header->name("header:nsiHeader" => \SOAP::Data->value(
                                        SOAP::Data->name(protocolVersion => $data->{'header'}->{'protocolVersion'}),
                                        SOAP::Data->name(correlationId => $data->{'header'}->{'correlationId'}),
                                        SOAP::Data->name(requesterNSA => $data->{'header'}->{'requesterNSA'}),
                                        SOAP::Data->name(providerNSA => $data->{'header'}->{'providerNSA'})
                                    ));

    my $soap_response = $soap->provisionConfirmed($header, SOAP::Data->name(connectionId => $data->{'connectionId'}));
}

sub _terminate_success{

    my ($self, $data) = @_;

    my $soap = SOAP::Lite->new->proxy($data->{'header'}->{'replyTo'})->ns('http://schemas.ogf.org/sni/2013/12/framework/types','ftypes')->ns('http://schemas.ogf.org/nsi/2013/12/framework/headers','header')->ns('http://schemas.ogf.org/nsi/2013/12/connection/types','ctypes');
    my $header = SOAP::Header->name("header:nsiHeader" => \SOAP::Data->value(
                                        SOAP::Data->name(protocolVersion => $data->{'header'}->{'protocolVersion'}),
                                        SOAP::Data->name(correlationId => $data->{'header'}->{'correlationId'}),
                                        SOAP::Data->name(requesterNSA => $data->{'header'}->{'requesterNSA'}),
                                        SOAP::Data->name(providerNSA => $data->{'header'}->{'providerNSA'})
                                    ));

    my $soap_response = $soap->terminateConfirmed($header, SOAP::Data->name(connectionId => $data->{'connectionId'}));

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

    $self->{'websvc'} = $websvc;

    $self->{'websvc_user'}     = $self->{'config'}->get('/config/oess-service/@username');
    $self->{'websvc_pass'}     = $self->{'config'}->get('/config/oess-service/@password');
    $self->{'websvc_realm'}    = $self->{'config'}->get('/config/oess-service/@realm');
    $self->{'websvc_location'} = $self->{'config'}->get('/config/oess-service/@web-service');

    $self->{'websvc'}->set_credentials(
        'uid' => $self->{'websvc_user'},
        'passwd' => $self->{'websvc_pass'}
        );

    $self->{'workgroup_id'} = $self->{'config'}->get('/config/oess-service/@workgroup-id');

    $self->{'provisioning_queue'} = [];
}

1;
