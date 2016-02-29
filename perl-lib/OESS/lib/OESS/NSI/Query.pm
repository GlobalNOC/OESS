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
        'passwd' => $self->{'websvc_pass'},
        'realm' => $self->{'websvc_realm'}
        );

    $self->{'ssl'} = $self->{'config'}->get('/config/ssl');
    if(defined($self->{'ssl'}->{'enabled'}) && $self->{'ssl'}->{'enabled'} ne '' && $self->{'ssl'}->{'enabled'} eq 'true'){
        $self->{'ssl'}->{'enabled'} = 1;
    }

    $self->{'workgroup_id'} = $self->{'config'}->get('/config/oess-service/@workgroup-id');

    $self->{'db'} = OESS::Database->new();

    $self->{'query_queue'} = [];
}

=head2 process_queue

=cut

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

=head2 query_summary

=cut

sub query_summary{
    my $self = shift;
    my $args = shift;
    push(@{$self->{'query_queue'}}, {type => OESS::NSI::Constant::QUERY_SUMMARY, args => $args});
    return OESS::NSI::Constant::SUCCESS;
}

=head2 get_current_circuits

=cut

sub get_current_circuits{
    my $self = shift;

    $self->{'websvc'}->set_url($self->{'websvc_location'} . "data.cgi");
    my $current_circuits = $self->{'websvc'}->foo( action => "get_existing_circuits",
                                                   workgroup_id => $self->{'workgroup_id'});

    if(defined($current_circuits) && defined($current_circuits->{'results'})){
        return $current_circuits->{'results'};
    }

    log_error("Unable to fetch current circuits for NSI workgroup");
    return;
    
}

=head2 do_query_summarysync

=cut

sub do_query_summarysync{
    my $self = shift;
    my $args = shift;
    
    $self->{'websvc'}->set_url($self->{'websvc_location'} . "data.cgi");
    my $current_circuits = $self->{'websvc'}->foo( action => "get_existing_circuits",
                                                   workgroup_id => $self->{'workgroup_id'});
    
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
    
    my $resp;
    foreach my $ckt (@ckts){
        my $value = $self->_build_summary_response($ckt, $args->{'header'});

        warn "VALUE: " . Data::Dumper::Dumper($value);
        if(!defined($resp)){
            $resp = SOAP::Data->value( $value);
        }else{
            $resp->value( \SOAP::Data->value( $resp->value, $value));
        }
    }
    
    return $resp->value;
}

sub _do_query_summary{
    my $self = shift;
    my $args = shift;

    my @summaryRes = $self->do_query_summarysync($args);

    my $soap = OESS::NSI::Utils::build_client( proxy => $args->{'header'}->{'replyTo'},ssl => $self->{'ssl'});

    my $nsiheader = OESS::NSI::Utils::build_header($args->{'header'});
    eval{
        $soap->querySummaryConfirmed($nsiheader,SOAP::Data->name( reserved => \@summaryRes));
    };
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
                                                 SOAP::Data->name( reservationState => $reservationState)->type(''),
                                                 SOAP::Data->name( provisionState => $provisionState)->type(''),
                                                 SOAP::Data->name( lifecycleState => $lifecycleState)->type(''),
                                                 SOAP::Data->name( dataPlaneStatus => \SOAP::Data->value( SOAP::Data->name( active => $active)->type(''),
                                                                                                          SOAP::Data->name( version => $version)->type(''),
                                                                                                          SOAP::Data->name( versionConsistent => $versionConsistent)->type('')))));
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

    return SOAP::Data->name( p2ps => \SOAP::Data->value( SOAP::Data->name( capacity => $ckt->{'bandwidth'} )->type(''),
                                                         SOAP::Data->name( directionality => 'bidirectional' )->type(''),
                                                         SOAP::Data->name( sourceSTP => $self->_build_urn( $ep1) )->type(''),
                                                         SOAP::Data->name( destSTP => $self->_build_urn($ep2) )->type('')
                             ))->type('');

}

sub _build_schedule{
    my $self = shift;
    my $ckt = shift;

    if($ckt->{'start_time'} ne ''){
        return SOAP::Data->name( schedule => \SOAP::Data->value( SOAP::Data->name( startTime => $ckt->{'start_time'})->type(''),
                                                                 SOAP::Data->name( endTime => $ckt->{'remove_time'})->type('')))->type('');
    }

    return SOAP::Data->name( schedule => \SOAP::Data->value( SOAP::Data->name( endTime => $ckt->{'remove_time'} )->type('')))->type('');
}

sub _build_criteria{
    my $self = shift;
    my $ckt = shift;
    
    return SOAP::Data->name(criteria =>
                            \SOAP::Data->value( #$self->_build_schedule( $ckt ),
                                                SOAP::Data->name( serviceType => '')->type(''),
                                                $self->_build_p2ps( $ckt )
                            ))->attr({ version => 0});
    
}


sub _build_summary_response{
    my $self = shift;
    my $ckt = shift;
    my $header = shift;

    my $resp = SOAP::Data->name( reservation => \SOAP::Data->value( SOAP::Data->name(connectionId => $ckt->{'circuit_id'})->type(''),
                                                                    SOAP::Data->name( globalReservationId => $ckt->{'gri'})->type(''),
                                                                    SOAP::Data->name( description => $ckt->{'description'})->type(''),
                                                                    $self->_build_criteria( $ckt ),
                                                                    SOAP::Data->name( requesterNSA => $header->{'requesterNSA'})->type(''),
                                                                    $self->_build_connectionStates( $ckt ),
                                                                    SOAP::Data->name( notificationId => 1)->type(''),
                                                                    SOAP::Data->name( resultId => 1)->type('')
                                 ));#->type('');
                                                   
    return $resp;

}

1;
