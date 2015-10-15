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

sub reserveCommit{
    my ($self, $args) = @_;
    
    push(@{$self->{'reservation_queue'}}, {type => OESS::NSI::Constant::RESERVATION_COMMIT_CONFIRMED, connection_id => 100, args => $args});

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
        }elsif($type == OESS::NSI::Constant::RESERVATION_COMMIT_CONFIRMED){
            log_debug("handling reservation commit success");
            
            $self->_reserve_commit_confirmed($message->{'args'});
            next;
        }elsif($type == OESS::NSI::Constant::RELEASE_SUCCESS){
            log_debug("handling release success");

            $self->_release_confirmed($message->{'args'});
        }
    }
}

sub release{
    my ($self, $args) = @_;

    push(@{$self->{'reservation_queue'}}, {type => OESS::NSI::Constant::RELEASE_SUCCESS, args => $args});
}

sub _build_p2ps{
    my $p2ps = shift;
    
    return SOAP::Data->name( p2ps => \SOAP::Data->value( SOAP::Data->name( capacity => $p2ps->{'capacity'} ),
                                                         SOAP::Data->name( directionality => $p2ps->{'directionality'} ),
                                                         SOAP::Data->name( sourceSTP => $p2ps->{'sourceSTP'} ),
                                                         SOAP::Data->name( destSTP => $p2ps->{'destSTP'} )))->uri('http://schemas.ogf.org/nsi/2013/12/services/point2point');
    
}

sub _build_schedule{
    my $schedule = shift;
    if($schedule->{'startTime'} ne ''){
        return SOAP::Data->name( schedule => \SOAP::Data->value( SOAP::Data->name( startTime => $schedule->{'startTime'})->type('ftypes:DateTimeType'),
                                                                 SOAP::Data->name( endTime => $schedule->{'endTime'})->type('ftypes:DateTimeType')));
    }

    return SOAP::Data->name( schedule => \SOAP::Data->value( SOAP::Data->name( endTime => $schedule->{'endTime'} )->type('ftypes:DateTimeType')));
}

sub _build_criteria{
    my $criteria = shift;
    
    return SOAP::Data->name(criteria => 
                            \SOAP::Data->value( _build_schedule( $criteria->{'schedule'}),
                                                SOAP::Data->name( serviceType => $criteria->{'serviceType'}->{'type'}),
                                                _build_p2ps( $criteria->{'p2ps'} )
                            ))->attr({ version => $criteria->{'version'}->{'version'}++});
    

}

sub _reserve_confirmed {
    my ($self, $data, $connection_id) = @_;

    log_debug("Sending Reservation Confirmation");
    warn Data::Dumper::Dumper($data);
    my $soap = SOAP::Lite->new->proxy($data->{'header'}->{'replyTo'})->ns('http://schemas.ogf.org/sni/2013/12/framework/types','ftypes')->ns('http://schemas.ogf.org/nsi/2013/12/framework/headers','header')->ns('http://schemas.ogf.org/nsi/2013/12/connection/types','ctypes');

    my $header = SOAP::Header->name("header:nsiHeader" => \SOAP::Data->value(
                                        SOAP::Data->name(protocolVersion => $data->{'header'}->{'protocolVersion'}),
                                        SOAP::Data->name(correlationId => $data->{'header'}->{'correlationId'}),
                                        SOAP::Data->name(requesterNSA => $data->{'header'}->{'requesterNSA'}),
                                        SOAP::Data->name(providerNSA => $data->{'header'}->{'providerNSA'})
                                    ));

    my $soap_response = $soap->reserveConfirmed($header, SOAP::Data->name(connectionId => $connection_id),
                                                SOAP::Data->name(globalReservationId => $data->{'globalReservationId'}),
                                                SOAP::Data->name(description => $data->{'description'}),
                                                _build_criteria($data->{'criteria'}) 
        );
                                                
}

sub _reserve_commit_confirmed{
    my ($self, $data) = @_;


    my $soap = SOAP::Lite->new->proxy($data->{'header'}->{'replyTo'})->ns('http://schemas.ogf.org/sni/2013/12/framework/types','ftypes')->ns('http://schemas.ogf.org/nsi/2013/12/framework/headers','header')->ns('http://schemas.ogf.org/nsi/2013/12/connection/types','ctypes');    
    my $header = SOAP::Header->name("header:nsiHeader" => \SOAP::Data->value(
                                        SOAP::Data->name(protocolVersion => $data->{'header'}->{'protocolVersion'}),
                                        SOAP::Data->name(correlationId => $data->{'header'}->{'correlationId'}),
                                        SOAP::Data->name(requesterNSA => $data->{'header'}->{'requesterNSA'}),
                                        SOAP::Data->name(providerNSA => $data->{'header'}->{'providerNSA'})
                                    ));

    my $soap_response = $soap->reserveCommitConfirmed($header, SOAP::Data->name(connectionId => $data->{'connectionId'}));
    
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

sub _release_confirmed{
    my ($self, $data) = @_;

    my $soap = SOAP::Lite->new->proxy($data->{'header'}->{'replyTo'})->ns('http://schemas.ogf.org/sni/2013/12/framework/types','ftypes')->ns('http://schemas.ogf.org/nsi/2013/12/framework/headers','header')->ns('http://schemas.ogf.org/nsi/2013/12/connection/types','ctypes');
    my $header = SOAP::Header->name("header:nsiHeader" => \SOAP::Data->value(
                                        SOAP::Data->name(protocolVersion => $data->{'header'}->{'protocolVersion'}),
                                        SOAP::Data->name(correlationId => $data->{'header'}->{'correlationId'}),
                                        SOAP::Data->name(requesterNSA => $data->{'header'}->{'requesterNSA'}),
                                        SOAP::Data->name(providerNSA => $data->{'header'}->{'providerNSA'})
                                    ));

    my $soap_response = $soap->releaseConfirmed($header, SOAP::Data->name(connectionId => $data->{'connectionId'}));
}

1;
