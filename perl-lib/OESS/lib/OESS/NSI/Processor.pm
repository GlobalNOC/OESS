#!/usr/bin/perl

package OESS::NSI::Processor;
$ENV{CRYPT_SSLEAY_CIPHER} = 'ALL';

use strict;
use warnings;

use Data::Dumper;
use JSON;

use GRNOC::Log;
use GRNOC::WebService::Client;

use OESS::NSI::Constant;
use OESS::NSI::Reservation;
use OESS::NSI::Provisioning;
use OESS::NSI::Query;

=head2 new

=cut

sub new {
    my $class = shift;
    my $service = shift;
    my $config_file = shift;
    
    my $self = {};
    bless($self,$class);

    $self->{'config_file'} = $config_file;
    $self->{'watched_circuits'} = [];
    $self->_init();

    return $self;
}

=head2 circuit_provision

=cut

sub circuit_provision{
    my ($self, $method, $params) = @_;

    foreach my $ckt_id (@{$self->{'watched_circuits'}}){
        if ($params->{'circuit'}->{'value'}->{'circuit_id'} == $ckt_id) {
            log_info("Circuit $ckt_id was provisioned.");
            $self->{'provisioning'}->dataPlaneStateChange($ckt_id);
        } else {
            log_debug("Ignoring provisioned circuit $ckt_id.");
        }
    }
}

=head2 circuit_modified

=cut

sub circuit_modified{
    my ($self, $method, $params) = @_;

    foreach my $ckt_id (@{$self->{'watched_circuits'}}){
        if ($params->{'circuit'}->{'value'}->{'circuit_id'} == $ckt_id) {
            log_info("Circuit $ckt_id was modified.");
            $self->{'provisioning'}->dataPlaneStateChange($ckt_id);
        } else {
            log_debug("Ignoring modified circuit $ckt_id.");
        }
    }
}

=head2 circuit_removed

=cut

sub circuit_removed{
    my ($self, $method, $params) = @_;

    foreach my $ckt_id (@{$self->{'watched_circuits'}}){
        if($params->{'circuit'}->{'value'}->{'circuit_id'} == $ckt_id){
            log_info("Circuit $ckt_id was removed.");
            $self->{'provisioning'}->dataPlaneStateChange($ckt_id);
        } else {
            log_debug("Ignoring removed circuit $ckt_id.");
        }
    }
}

=head2 process_request

=cut

sub process_request {
    my ($self, $method, $params) = @_;

    my $request = $params->{'method'}->{'value'};
    my $data    = $params->{'data'}->{'value'};

    log_info("Received method call: $request");
    log_info(Dumper($request));
    warn Dumper("REceived Method call: $request");
    $data = decode_json $data;

    log_info("Received method data: $data");
    log_info(Dumper($data));

    if($request =~ /^reserve$/){
        my $circuit = $self->{'reservation'}->reserve($data);
        if($circuit > 0 && $circuit < 9999999){
            log_debug("adding circuit $circuit to watch list");
            push(@{$self->{'watched_circuits'}},$circuit);
        }
        return $circuit;
    }elsif($request =~ /^reserveCommit$/){
        return $self->{'reservation'}->reserveCommit($data);
    }elsif($request =~ /^reserveAbort$/){
        return $self->{'reservation'}->reserveAbort($data);
    }elsif($request =~ /^provision$/){
        return $self->{'provisioning'}->provision($data);
    }elsif($request =~ /^terminate$/){
        return $self->{'provisioning'}->terminate($data);
    }elsif($request =~ /^release$/){
        return $self->{'provisioning'}->release($data);
    }elsif($request =~ /^querySummary$/){
        return $self->{'query'}->querySummary($data);
    }

    log_error("Unknown Request Type: " . $request);
    return OESS::NSI::Constant::UNKNOWN_REQUEST;
}

=head2 process_queues

=cut

sub process_queues {
    my ($self) = @_;

    log_debug("processing queues");
    $self->{'reservation'}->process_queue();
    $self->{'provisioning'}->process_queue();
    $self->{'query'}->process_queue();
}

sub _init {
    my ($self) = @_;

    $self->{'reservation'} = new OESS::NSI::Reservation(config_file => $self->{'config_file'});
    $self->{'provisioning'} = new OESS::NSI::Provisioning(config_file => $self->{'config_file'});
    $self->{'query'} = new OESS::NSI::Query(config_file => $self->{'config_file'} );

    my $circuits = $self->{'query'}->get_current_circuits();

    log_debug("loading circuits into watch list");
    foreach my $circuit (@$circuits){
        push(@{$self->{'watched_circuits'}},$circuit->{'circuit_id'});
        log_debug("loaded circuit: " . $circuit->{'circuit_id'} . " to watch list");
    }

}

1;
