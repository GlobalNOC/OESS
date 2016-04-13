#!/usr/bin/perl

use strict;
use warnings;

package OESS::MPLS::Switch;


use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;

use Switch;
use Template;
use Net::Netconf::Manager;
use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;
use GRNOC::RabbitMQ::Client;
use OESS::MPLS::Device;

sub new{
    my $class = shift;
    my %args = (
        @_
        );

    my $self = \%args;

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.MPLS.Switch.' . $self->{'id'});
    bless $self, $class;

    $self->_update_cache();

    $self->create_device_object();
    if(!defined($self->{'device'})){
	$self->{'logger'}->error("Unable to create Device instance!");
	die;
    }
    
    my $topic = 'MPLS.FWDCTL.Switch.' . $self->{'host_info'}->{'mgmt_addr'};

    $self->{'logger'}->error("Listening to topic: " . $topic);

    my $dispatcher = GRNOC::RabbitMQ::Dispatcher->new( host => $args{'rabbitMQ_host'},
                                                       port => $args{'rabbitMQ_port'},
                                                       user => $args{'rabbitMQ_user'},
                                                       pass => $args{'rabbitMQ_pass'},
                                                       topic => $topic,
                                                       queue => $topic,
                                                       exchange => 'OESS');

    $self->register_rpc_methods( $dispatcher );

    #attempt to reconnect!
    $self->{'connect_timer'} = AnyEvent->timer( after => 10, interval => 60,
                                                cb => sub {
                                                    if($self->{'device'}->connected()){
                                                        return;
                                                    }
                                                    $self->{'device'}->connect();
                                                });

    return $self;
}

sub create_device_object{
    my $self = shift;

    my $host_info = $self->{'host_info'};

    switch($host_info->{'vendor'}){
	case "Juniper" {
	    my $dev;
	    if($host_info->{'model'} =~ /MX/){
		$dev = OESS::MPLS::Device::Juniper::MX->new( $host_info );
	    }else{
		$self->{'logger'}->error("Juniper " . $host_info->{'model'} . " is not supported");
		return;
	    }
	    
	    if(!defined($dev)){
		$self->{'logger'}->error("Unable to instantiate Device!");
		return;
	    }

	    $self->{'device'} = $dev;

	}else{
	    $self->{'logger'}->error("Unsupported device type: " . $host_info->{'host_inof'});
	    return;
	}
    }
}

sub register_rpc_methods{
    my $self = shift;
    my $dispatcher = shift;

    my $method = GRNOC::RabbitMQ::Method->new( name => "add_vlan",
                                              async => 1,
                                              description => "adds a vlan for this switch",
                                               callback => sub { $self->add_vlan(@_) });

    $method->add_input_parameter( name => "circuit_id",
                                  description => "circuit_id to be added",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::NUMBER_ID);
    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => "remove_vlan",
                                            async => 1,
                                            description => "removes a vlan for this switch",
                                            callback => sub { $self->remove_vlan(@_) }     );
    $method->add_input_parameter( name => "circuit_id",
                                  description => "circuit_id to be removed",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::NUMBER_ID);
    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => "echo",
                                            description => " just an echo to check to see if we are aliave",
                                            callback => sub { return {status => 1, msg => "I'm alive!"}});
    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => "force_sync",
                                            description => " handle force_sync event",
                                            callback => sub { $self->{'logger'}->warn("received a force_sync command");
                                                              $self->_update_cache();
                                                              $self->{'needs_diff'} = time();
                                                              return {status => 1, msg => "diff scheduled!"}; });
    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => "update_cache",
                                            description => " handle thes update cahce call",
                                            callback => sub { $self->_update_cache();
                                                              return {status => 1, msg => "cache updated"}});
    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name        => "stop",
                                            callback    => sub {
                                                $self->stop();
                                                $self->{'logger'}->info("FWDCTL has stopped; Now exiting.");
                                            },
                                            description => "Notification that FWDCTL has exited",
                                            topic       => "OF.FWDCTL.event" );
    $dispatcher->register_method($method);

}

sub _update_cache{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    $self->{'logger'}->debug("Retrieve file: " . $self->{'share_file'});

    if(!-e $self->{'share_file'}){
        $self->{'logger'}->error("No Cache file exists!!!");
        return;
    }

    my $str;
    open(my $fh, "<", $self->{'share_file'});
    while(my $line = <$fh>){
        $str .= $line;
    }

    my $data = from_json($str);
    $self->{'logger'}->debug("Fetched data!");
    $self->{'node'} = $data->{'nodes'}->{$self->{'host_info'}->{'mgmt_addr'}};
    $self->{'settings'} = $data->{'settings'};

    foreach my $ckt (keys %{ $self->{'ckts'} }){
        delete $self->{'ckts'}->{$ckt};
    }

    foreach my $ckt (keys %{ $data->{'ckts'}}){
        $ckt = int($ckt);
        $self->{'logger'}->debug("processing cache for circuit: " . $ckt);

        $self->{'ckts'}->{$ckt}->{'details'} = $data->{'ckts'}->{$ckt}->{'details'};

    }

    $self->{'logger'} = Log::Log4perl->get_logger('MPLS.FWDCTL.Switch.' . $self->{'node'}->{'name'}) if($self->{'node'}->{'name'});

    $self->{'settings'} = $data->{'settings'};
}

=head2 echo
Always returns 1.
=cut
sub echo {
    my $self = shift;
    return {status => 1};
}

=head2 stop
Sends a shutdown signal on OF.FWDCTL.event.stop. Child processes
should listen for this signal and cleanly exit when received.
=cut
sub stop {
    my $self = shift;

    exit(1);
}

1;


1;
