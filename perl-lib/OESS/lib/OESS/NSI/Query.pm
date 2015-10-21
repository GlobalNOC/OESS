#!/usr/bin/perl

package OESS::NSI::Query;

use strict;
use warnings;

use SOAP::Lite on_action => sub { sprintf '"http://schemas.ogf.org/nsi/2013/12/connection/service/%s"', $_[1]};

use GRNOC::Log;
use GRNOC::Config;
use GRNOC::WebService::Client;

use OESS::NSI::Constant;
use OESS::Database;

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

    $websvc->{'debug'} = 1;

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

    $self->{'ssl'}->{'enabled'} = $self->{'config'}->get('/config/ssl/@enabled');
    if(defined($self->{'ssl'}->{'enabled'}) && $self->{'ssl'}->{'enabled'} ne '' && $self->{'ssl'}->{'enabled'} eq 'true'){
        $self->{'ssl'}->{'enabled'} = 1;
        $self->{'ssl'}->{'cert'} = $self->{'config'}->get('/config/ssl/@cert');
        $self->{'ssl'}->{'key'} = $self->{'config'}->get('/config/ssl/@key');
    }

    $self->{'workgroup_id'} = $self->{'config'}->get('/config/oess-service/@workgroup-id');

    $self->{'db'} = OESS::Database->new();

    $self->{'query_queue'} = [];
}

sub process_queue {
    my ($self) = @_;

    log_debug("Processing Query Queue.");

    while(my $message = shift(@{$self->{'query_queue'}})){
        my $type = $message->{'type'};

        if($type == OESS::NSI::Constant::QUERY_SUMMARY){
            log_debug("Handling Reservation Success Message");
            $self->_do_query_summary($message->{'args'});
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

sub query_summary{
    my $self = shift;
    my $args = shift;
    push(@{$self->{'query_queue'}}, {type => OESS::NSI::Constant::QUERY_SUMMARY, args => $args});
    return OESS::NSI::Constant::SUCCESS;
}

sub do_query_summarysync{
    my $self = shift;
    my $args = shift;
    
    $self->{'websvc'}->set_url($self->{'websvc_location'} . "data.cgi");
    my $current_circuits = $self->{'websvc'}->foo( action => "get_existing_circuits",
                                                   workgroup_id => $self->{'workgroup_id'});
    
    warn Data::Dumper::Dumper($args);

    warn Data::Dumper::Dumper($current_circuits);
    my @ckts = ();
    
    if(!defined($current_circuits) || defined($current_circuits->{'error'}) || !defined($current_circuits->{'results'})){
        log_error("Unable to fetch current circuits for NSI workgroup");
        return OESS::NSI::Constant::ERROR;
    }else{
        foreach my $ckt (@{$current_circuits->{'results'}}){
            foreach my $cId (@{$args->{'connectionIds'}}){
                if($ckt->{'circuit_id'} == $cId){
                    push(@ckts, $ckt);
                }
            }
        }
    }
    
    my $resp = new SOAP::Data;
    foreach my $ckt (@ckts){
        $resp->value($resp->value(),$self->_build_summary_response($ckt, $args->{'header'}));
    }
    
    $resp->type("{http://schemas.ogf.org/nsi/2013/12/connection/types}QuerySummaryConfirmedType");

    return $resp;
}

sub _do_query_summary{
    my $self = shift;
    my $args = shift;

    my @summaryRes = $self->do_query_summarysync($args);

    my $soap = SOAP::Lite->new->proxy($args->{'header'}->{'replyTo'})
        ->ns('http://schemas.ogf.org/sni/2013/12/framework/types','ftypes')
        ->ns('http://schemas.ogf.org/nsi/2013/12/framework/headers','header')
        ->ns('http://schemas.ogf.org/nsi/2013/12/connection/types','ctypes');
    
    if($self->{'ssl'}->{'enabled'}){
        $soap->transport->ssl_opts( SSL_cert_file => $self->{'ssl'}->{'cert'},
                                    SSL_key_file => $self->{'ssl'}->{'key'});
    }
    
    my $header = SOAP::Header->name("header:nsiHeader" => \SOAP::Data->value(
                                        SOAP::Data->name(protocolVersion => $args->{'header'}->{'protocolVersion'}),
                                        SOAP::Data->name(correlationId => $args->{'header'}->{'correlationId'}),
                                        SOAP::Data->name(requesterNSA => $args->{'header'}->{'requesterNSA'}),
                                        SOAP::Data->name(providerNSA => $args->{'header'}->{'providerNSA'})
                                    ));
    
    $soap->querySummaryConfirmed(SOAP::Data->name( reserved => \@summaryRes));
                                 
}


sub _build_connectionStates{
    my $self = shift;
    my $ckt = shift;
    
    my $reservationState;
    my $provisionState;
    my $lifecycleState;
    
    my $active;
    my $version = 0;
    my $versionConsistent = "true";   

    if($ckt->{'circuit_state'} eq 'active'){
        $reservationState = 'reserveState';
        $provisionState = 'Provisioned';
        $lifecycleState = 'Created';
        $active = 'true';
    }elsif($ckt->{'circuit_state'} eq 'reserved'){
        $reservationState = 'reserveState';
        $provisionState = '';
        $lifecycleState= 'Created';
        $active = 'false';
    }elsif($ckt->{'circuit_state'} eq 'deploying'){
        $reservationState = 'reserveState';
        $provisionState = 'Provisioning';
        $lifecycleState= 'Created';
        $active = 'false';
    }elsif($ckt->{'circuit_state'} eq 'decom'){
        $reservationState = '';
        $provisionState = 'Released';
        $lifecycleState= 'Terminated';
        $active = 'false';
    }

    my $connection_state = SOAP::Data->name( connectionStates => \SOAP::Data->value(
                                                 SOAP::Data->name( reservationState => $reservationState),
                                                 SOAP::Data->name( provisionState => $provisionState),
                                                 SOAP::Data->name( lifecycleState => $lifecycleState),
                                                 SOAP::Data->name( dataPlaneStatus => \SOAP::Data->value( SOAP::Data->name( active => $active),
                                                                                                          SOAP::Data->name( version => $version),
                                                                                                          SOAP::Data->name( versionConsistent => $versionConsistent)))));
    return $connection_state;
    
}

sub _build_urn{
    my $self = shift;
    my $ep = shift;

    my $urn;

    my $domain = $self->{'db'}->get_local_domain_name();
    
    $urn = "urn:ogf:network:nsi." . $domain . ":" . $ep->{'node_name'} . ":" . $ep->{'interface'} . ":*?vlan=" . $ep->{'tag'};

    return $urn;
}

sub _build_p2ps{
    my $self = shift;
    my $ckt = shift;

    my $ep1 = $ckt->{'endpoints'}->[0];
    my $ep2 = $ckt->{'endpoints'}->[1];

    return SOAP::Data->name( p2ps => \SOAP::Data->value( SOAP::Data->name( capacity => $ckt->{'bandwidth'} ),
                                                         SOAP::Data->name( directionality => 'bidirectional'),
                                                         SOAP::Data->name( sourceSTP => $self->_build_urn( $ep1) ),
                                                         SOAP::Data->name( destSTP => $self->_build_urn($ep2))))->uri('http://schemas.ogf.org/nsi/2013/12/services/point2point');

}

sub _build_schedule{
    my $self = shift;
    my $ckt = shift;

    if($ckt->{'start_time'} ne ''){
        return SOAP::Data->name( schedule => \SOAP::Data->value( SOAP::Data->name( startTime => $ckt->{'start_time'})->type('ftypes:DateTimeType'),
                                                                 SOAP::Data->name( endTime => $ckt->{'remove_time'})->type('ftypes:DateTimeType')));
    }

    return SOAP::Data->name( schedule => \SOAP::Data->value( SOAP::Data->name( endTime => $ckt->{'remove_time'} )->type('ftypes:DateTimeType')));
}

sub _build_criteria{
    my $self = shift;
    my $ckt = shift;
    
    return SOAP::Data->name(criteria =>
                            \SOAP::Data->value( $self->_build_schedule( $ckt ),
                                                SOAP::Data->name( serviceType => ''),
                                                $self->_build_p2ps( $ckt )))->attr({ version => 0});
    
}


sub _build_summary_response{
    my $self = shift;
    my $ckt = shift;
    my $header = shift;

    my $resp = SOAP::Data->name( reservation => \SOAP::Data->value( SOAP::Data->name(connectionId => $ckt->{'circuit_id'}),
                                                                    SOAP::Data->name( globalReservationId => $ckt->{'gri'}),
                                                                    SOAP::Data->name( description => $ckt->{'description'}),
                                                                    $self->_build_criteria( $ckt ),
                                                                    SOAP::Data->name( requesterNSA => $header->{'requesterNSA'}),
                                                                    $self->_build_connectionStates( $ckt ),
                                                                    SOAP::Data->name( notificationId => 1),
                                                                    SOAP::Data->name( resultId => 1)))->type("{http://schemas.ogf.org/nsi/2013/12/connection/types}QuerySummaryResultType");
                                                   
    return $resp;

}

1;
