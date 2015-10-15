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

package OESS::NSI::Reservation;

use strict;
use warnings;

use SOAP::Lite;

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

sub reserve {
    my ($self, $args) = @_;

    my $connection_id = $args->{'connectionId'};
    my $description = $args->{'description'};
    my $start_time = $args->{'criteria'}->{'schedule'}->{'startTime'};
    my $end_time = $args->{'criteria'}->{'schedule'}->{'endTime'};
    my $source_stp = $args->{'criteria'}->{'p2ps'}->{'sourceSTP'};
    my $dest_stp = $args->{'criteria'}->{'p2ps'}->{'destSTP'};
    my $directionality = $args->{'criteria'}->{'p2ps'}->{'directionality'};
    my $capacity = $args->{'criteria'}->{'p2ps'}->{'capacity'};
    my $reply_to = $args->{'header'}->{'replyTo'};
    
    if(!$description || !$source_stp || !$dest_stp || !$reply_to){
        return OESS::NSI::Constant::MISSING_REQUEST_PARAMETERS;
    }

    push(@{$self->{'reservation_queue'}}, {type => OESS::NSI::Constant::RESERVATION_SUCCESS, connection_id => 100, args => $args});

    return 100;
}

sub process_queue {
    my ($self) = @_;

    log_debug("Processing Reservation Queue.");

    while(my $message = shift(@{$self->{'reservation_queue'}})){
        my $type = $message->{'type'};

        if($type == OESS::NSI::Constant::RESERVATION_SUCCESS){
            log_debug("Handling Reservation Success Message");

            my $connection_id = $message->{'connection_id'};

            $self->_reserve_confirmed($message->{'args'}, $connection_id);
            next;
        }
        elsif($type == OESS::NSI::Constant::RESERVATION_FAIL){
            log_debug("Handling Reservation Fail Message");

            $self->_reserve_failed($message->{'args'});
            next;
        }
    }
}

sub _reserve_confirmed {
    my ($self, $data, $connection_id) = @_;

    log_debug("Sending Reservation Confirmation");

    my $soap = SOAP::Lite->new()->proxy($data->{'header'}->{'replyTo'})->uri('http://schemas.ogf.org/nsi/2013/12/connection/types')->ns('http://schemas.ogf.org/nsi/2013/12/framework/headers','header')->ns('http://schemas.ogf.org/nsi/2013/12/connection/types','ctypes');
    my $header = SOAP::Header->name(nsiHeader => \SOAP::Data->value(
                                        SOAP::Data->name(protocolVersion => $data->{'header'}->{'protocolVersion'}),
                                        SOAP::Data->name(correlationId => $data->{'header'}->{'correlationId'}),
                                        SOAP::Data->name(requesterNSA => $data->{'header'}->{'requesterNSA'}),
                                        SOAP::Data->name(providerNSA => $data->{'header'}->{'providerNSA'})
                                    )->type("header:nsiHeader"));

    my $soap_response = $soap->reserveConfirmed(
        $header,
        SOAP::Data->name(connectionId => $connectionId),
        SOAP::Data->name(criteria => )
        );
}

sub _reserve_failed {
    my ($self, $data) = @_;

    log_debug("Sending Reservation Failure");
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

    $self->{'reservation_queue'} = [];
}

1;
