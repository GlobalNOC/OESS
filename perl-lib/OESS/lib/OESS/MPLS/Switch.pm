#!/usr/bin/perl

use strict;
use warnings;

package OESS::MPLS::Switch;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;

use AnyEvent;
use Data::Dumper;
use Log::Log4perl;
use Switch;
use Template;
use Net::Netconf::Manager;

use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;
use GRNOC::RabbitMQ::Client;
use GRNOC::WebService::Regex;

use OESS::MPLS::Device;

use JSON::XS;

sub new{
    my $class = shift;
    my %args = (
	rabbitMQ_host => undef,
	rabbitMQ_port => undef,
	rabbitMQ_user => undef,
	rabbitMQ_pass => undef,
	use_cache => 1,
	node => undef,
        @_
        );

    my $self = \%args;
    bless $self, $class;

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.MPLS.Switch.' . $self->{'id'});

    $self->{'node'}->{'node_id'} = $self->{'id'};
    
    if($self->{'use_cache'}){
	$self->_update_cache();
    }

    $self->create_device_object();
    if(!defined($self->{'device'})){
	$self->{'logger'}->error("Unable to create Device instance!");
	die;
    }
    
    if(!defined($self->{'topic'})){
	$self->{'topic'} = "MPLS.FWDCTL.Switch";
    }

    my $topic = $self->{'topic'} . "." .  $self->{'node'}->{'mgmt_addr'};
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

    #try and connect up right away
    $self->{'device'}->connect();
 
    AnyEvent->condvar->recv;
    return $self;
}

=head2 set_pending

Sets the in-memory state for a devices diff state. If durring a diff
the in-memory state is 0, but 1 is stored in the database, a diff will
be forced to occur.

=cut
sub set_pending {
    my $self  = shift;
    my $state = shift;

    $self->{'pending_diff'} = $state;
    $self->{'device'}->{'pending_diff'} = $state;
    return 1;
}

sub create_device_object{
    my $self = shift;

    my $host_info = $self->{'node'};

    switch($host_info->{'vendor'}){
        case "Juniper" {
            my $dev;
            if($host_info->{'model'} =~ /mx/i){
                $self->{'logger'}->info("create_device_object: " . Dumper($host_info));
                warn Data::Dumper::Dumper($host_info);
                $dev = OESS::MPLS::Device::Juniper::MX->new( %$host_info );
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
            $self->{'logger'}->error("Unsupported device type: ");
            return;
        }
    }
}

sub register_rpc_methods{
    my $self = shift;
    my $dispatcher = shift;

    my $method = GRNOC::RabbitMQ::Method->new( name => "add_vlan",
					       description => "adds a vlan for this switch",
                                               callback => sub { return {status => $self->add_vlan(@_) }});
    
    $method->add_input_parameter( name => "circuit_id",
                                  description => "circuit_id to be added",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::NUMBER_ID);
    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name => "remove_vlan",
                                            description => "removes a vlan for this switch",
                                            callback => sub { return {status => $self->remove_vlan(@_) }});

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

    $method = GRNOC::RabbitMQ::Method->new( name        => "get_interfaces",
                                            callback    => sub {
                                                $self->get_interfaces();
                                            },
                                            description => "returns a list of interfaces on the device");
    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name        => "get_isis_adjacencies",
                                            callback    => sub {
                                                $self->get_isis_adjacencies();
                                            },
                                            description => "returns a list of IS-IS adjacencies from this switch");
    $dispatcher->register_method($method);


    $method = GRNOC::RabbitMQ::Method->new( name        => "get_LSPs",
                                            callback    => sub {
                                                $self->get_LSPs();
                                            },
                                            description => "returns a list of LSPs and their details");
    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name        => "get_system_info",
					    callback    => sub {
						$self->get_system_info();
					    },
					    description => "returns the system information");
    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name        => "diff",
					    callback    => sub {
                                                my $node_id = $self->{'node'}->{'node_id'};
                                                my $status  = $self->diff(@_);
                                                return { node_id => $node_id, status  => $status };
                                            },
					    description => "Proxies diff signal to the underlying device object.");
    $method->add_input_parameter( name => "force_diff",
                                  description => "Set to 1 if size of diff should be ignored",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::INTEGER);
    $dispatcher->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new( name        => "get_diff_text",
					    callback    => sub {
                                                return { text => $self->get_diff_text(@_) };
                                            },
					    description => "Proxies diff signal to the underlying device object." );
    $dispatcher->register_method($method);
}

sub _update_cache{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    $self->{'logger'}->info("Loading circuits from cache file.");
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

    my $data = decode_json($str);
    $self->{'logger'}->debug("Fetched data!");
    $self->{'node'} = $data->{'nodes'}->{$self->{'id'}};
    $self->{'logger'}->info("_update_cache: " . Dumper($self->{'node'}));

    $self->{'settings'} = $data->{'settings'};

    foreach my $ckt (keys %{ $self->{'ckts'} }){
        delete $self->{'ckts'}->{$ckt};
    }

    foreach my $ckt (keys %{ $data->{'ckts'}}){
        $ckt = int($ckt);
        $self->{'logger'}->debug("processing cache for circuit: " . $ckt);

        $self->{'ckts'}->{$ckt} = $data->{'ckts'}->{$ckt};

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

=head2 add_vlan

    Adds a VLAN to this switch

=cut


sub add_vlan{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;
    $self->{'logger'}->error("ADDING VLAN");
    $self->{'logger'}->debug("in add_vlan");

    my $circuit = $p_ref->{'circuit_id'}{'value'};

    $self->{'logger'}->debug("Adding VLAN: " . $circuit);

    $self->_update_cache();
    
    my $vlan_obj = $self->_generate_commands( $circuit );

    return $self->{'device'}->add_vlan($vlan_obj);
}

=head2 get_system_info

=cut

sub get_system_info{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    return $self->{'device'}->get_system_information();
}


=head2 remove_vlan

removes a VLAN from this switch

=cut

sub remove_vlan{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    $self->{'logger'}->debug("in remove_vlan");

    my $circuit = $p_ref->{'circuit_id'}{'value'};

    $self->{'logger'}->debug("Removing VLAN: " . $circuit);

    $self->_update_cache();

    my $vlan_obj = $self->_generate_commands( $circuit );

    my $res = $self->{'device'}->remove_vlan($vlan_obj);
    $self->{'logger'}->debug("after remove vlan");
    $self->{'logger'}->debug("Results: " . Data::Dumper::Dumper($res));
    return $res;
}

=head2 diff

Proxies diff signal to the underlying device object.

=cut
sub diff {
    my $self  = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    $self->{'logger'}->debug("Calling Switch.diff");
    $self->_update_cache();

    my $circuits = [];
    foreach my $ckt (keys %{ $self->{'ckts'} }){
        push(@{$circuits}, $self->{'ckts'}->{$ckt});
    }

    return $self->{'device'}->diff($circuits, $p_ref->{'force_diff'}{'value'});
}

sub get_diff_text {
    my $self  = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    return $self->{'device'}->get_diff_text();
}

=head2 get_interfaces

returns a list of interfaces from the device

=cut

sub get_interfaces{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    return $self->{'device'}->get_interfaces();
}

=head2 get_isis_adjacencies

    returns a list of isis_adjacencies on the device

=cut

sub get_isis_adjacencies{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    return $self->{'device'}->get_isis_adjacencies();
}

=head2 get_LSPs

    returns the details of all of the LSPs on the device

=cut

sub get_LSPs{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    return $self->{'device'}->get_LSPs();
}

sub _generate_commands{
    my $self = shift;
    my $ckt_id = shift;

    my $obj = $self->{'ckts'}->{$ckt_id};
    $obj->{'circuit_id'} = $ckt_id;
    return $obj;
}


1;
