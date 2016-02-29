#!/usr/bin/perl

package OESS::NSI::Processor;
$ENV{CRYPT_SSLEAY_CIPHER} = 'ALL';
use strict;
use warnings;

use Net::DBus::Exporter qw(org.nddi.nsi);
use Net::DBus qw(:typing);
use Net::DBus::Annotation qw(:call);
use base qw(Net::DBus::Object);

use GRNOC::Log;
use GRNOC::WebService::Client;

use OESS::NSI::Constant;
use OESS::NSI::Reservation;
use OESS::NSI::Provisioning;
use OESS::NSI::Query;
use Data::Dumper;

=head2 new

=cut

sub new {
    my $class = shift;
    my $service = shift;
    my $config_file = shift;
    
    my $self = $class->SUPER::new($service, '/controller1');
    bless($self,$class);

    $self->{'config_file'} = $config_file;
    $self->{'watched_circuits'} = [];
    $self->_init();

    #-- dbus methods
    dbus_method("process_request", ["string", ["dict", "string", ["variant"]]], ["int32"]);

    return $self;
}

=head2 circuit_provision

=cut

sub circuit_provision{
    my ($self, $circuit) = @_;

    foreach my $ckt_id (@{$self->{'watched_circuits'}}){
        if($circuit->{'circuit_id'} == $ckt_id){
            log_debug("Found a circuit that was modified! circuit_id: " . $circuit);
            $self->{'provisioning'}->dataPlaneStateChange($ckt_id);
        }
    }
}

=head2 circuit_modified

=cut

sub circuit_modified{
    my ($self, $circuit) = @_;
    foreach my $ckt_id (@{$self->{'watched_circuits'}}){
        if($circuit->{'circuit_id'} == $ckt_id){
            log_debug("found a circuit that was modified! circuit_id: " . $circuit);
            $self->{'provisioning'}->dataPlaneStateChange($ckt_id);
        }
    }
}

=head2 circuit_removed

=cut

sub circuit_removed{
    my ($self, $circuit) = @_;
    foreach my $ckt_id (@{$self->{'watched_circuits'}}){
        log_debug("Found a circuit that was removed! cicuit_id = " . $circuit);
        if($circuit->{'circuit_id'} == $ckt_id){
            $self->{'provisioning'}->dataPlaneStateChange($ckt_id);
        }
    }
}

=head2 process_request

=cut

sub process_request {
    my ($self, $request, $data) = @_;

    log_info("Received method call: $request");
    if($request =~ /^reserve$/){
        my $circuit = $self->{'reservation'}->reserve($data);
        if($circuit > 0 && $circuit < 99999){
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
