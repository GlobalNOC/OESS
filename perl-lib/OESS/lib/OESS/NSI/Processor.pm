#!/usr/bin/perl

package OESS::NSI::Processor;

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
use Data::Dumper;

sub new {
    my $class = shift;
    my $service = shift;
    my $config_file = shift;
    
    my $self = $class->SUPER::new($service, '/controller1');
    bless($self,$class);

    $self->{'config_file'} = $config_file;
    $self->_init();

    #-- dbus methods
    dbus_method("process_request", ["string", ["dict", "string", ["variant"]]], ["int32"]);

    return $self;
}

sub process_request {
    my ($self, $request, $data) = @_;

    log_debug("Received method call: $request");


    if($request =~ /^reserve$/){
        return $self->{'reservation'}->reserve($data);
    }elsif($request =~ /^reserveCommit$/){
        return $self->{'reservation'}->reserveCommit($data);
    }elsif($request =~ /^provision$/){
        return $self->{'provisioning'}->provision($data);
    }elsif($request =~ /^terminate$/){
        return $self->{'provisioning'}->terminate($data);
    }elsif($request =~ /^release$/){
        return $self->{'reservation'}->release($data);
    }

    return OESS::NSI::Constant::UNKNOWN_REQUEST;
}

sub process_queues {
    my ($self) = @_;

    $self->{'reservation'}->process_queue();
    $self->{'provisioning'}->process_queue();
}

sub _init {
    my ($self) = @_;

    $self->{'reservation'} = new OESS::NSI::Reservation(config_file => $self->{'config_file'});
    $self->{'provisioning'} = new OESS::NSI::Provisioning(config_file => $self->{'config_file'});

}

1;
