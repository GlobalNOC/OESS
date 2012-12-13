#!/usr/bin/perl
#
##----- NDDI OESS DBus Interaction Module                                            
##-----                                                                                  
##----- $HeadURL: svn+ssh://svn.grnoc.iu.edu/grnoc/oe-ss/perl-lib/OESS-DBus/trunk/lib/OESS/DBus.pm $
##----- $Id$
##----- $Date$
##----- $LastChangedBy$
##-----                                                                                
##----- Provides object oriented methods to interact with the DBus test
##
##-------------------------------------------------------------------------
##
##                                                                                       
## Copyright 2011 Trustees of Indiana University                                         
##                                                                                       
##   Licensed under the Apache License, Version 2.0 (the "License");                     
##  you may not use this file except in compliance with the License.                     
##   You may obtain a copy of the License at                                             
##                                                                                       
##       http://www.apache.org/licenses/LICENSE-2.0                                      
##                                                                                       
##   Unless required by applicable law or agreed to in writing, software                 
##   distributed under the License is distributed on an "AS IS" BASIS,                   
##   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.            
##   See the License for the specific language governing permissions and                 
##   limitations under the License.                                                      
#                                                 

package OESS::DBus;

use strict;
use warnings;
use Net::DBus::Exporter qw(org.nddi.fwdctl);
use Net::DBus qw(:typing);
use Net::DBus::Reactor;
use base qw(Net::DBus::Object);
use Sys::Syslog qw(:macros :standard);


our $VERSION = '1.0.5';

sub new{

    my $that = shift;
    my $class = ref($that) || $that;

    my %args = (
	timeout          => 30,
	timeout_callback => sub {},
	service          => undef,
	instance         => undef,
	sleep_interval   => 2,	
	@_
	);

    my $self = \%args;
    bless $self,$class;

    openlog("OESS::DBus", 'cons,pid', LOG_DAEMON);

    if(!defined($args{'service'})){
	$self->log("error initializing OESS::DBus, no service provided");
	return undef;
    }

    if(!defined($args{'instance'})){
	$self->log("error initializing OESS::DBus, no instance provided");
	return undef;
    }
    
    $self->{'dbus'} = $self->_connect_to_object();
    
    if(!defined($self->{'dbus'})){
	$self->log("error initializing OESS::DBus, unable to connect");
	return undef;
    }

    return $self;
    
}


sub start_reactor{
    my $self = shift;
    my %params = @_;
    
    $self->{'reactor'} = Net::DBus::Reactor->main();

    #add any timeouts
    if(defined($params{'timeouts'})){
	foreach my $timeout (@{$params{'timeouts'}}){
	    $self->{'reactor'}->add_timeout($timeout->{'interval'},$timeout->{'callback'});
	}
    }

    $self->{'reactor'}->run();
}

sub _connect_to_object{
    my $self = shift;

    my $timeout = $self->{'timeout'};
    my $obj;

    while($timeout != 0){
        eval{
            my $bus = Net::DBus->system;
            my $srv = undef;
            $srv = $bus->get_service($self->{'service'});
            $obj = $srv->get_object($self->{'instance'});
        };
        if($@){
	    #--- error
	    #--- only emit every 10 seconds to avoid spamming logs
	    if ($timeout % 10 == 0){
		$self->log("dbus connection error: $@ ... retry in few");
	    }
        }else{
	    #--- success
	    return $obj;
        }
	sleep($self->{'sleep_interval'});
	$timeout--;
    }    

    $self->log("dbus timed out connection");
    $self->{"timeout_callback"}();    

    return undef;
}


sub _set_error {
    my $self = shift;
    my $error = shift;
    
    $self->{'error'} = $error;
}

=head2 get_error

    returns any error and clears it

=cut

sub get_error{
    my $self = shift;

    my $err = $self->{'error'};
    $self->{'error'} = undef;
    return $err;
}


=head2 connect_to_signal

    given an event name, and a callback, hooks the callback up to the event

=cut

sub connect_to_signal{
    my $self = shift;
    my $event = shift;
    my $callback = shift;

    $self->{'dbus'}->connect_to_signal($event,$callback);
}

=head2 fire_signal
    
    first a signal over dbus
   
=cut

sub fire_signal{
    my $self = shift;
    my $event = shift;
    
    $self->{'dbus'}->$event(@_);
}


sub log {
    my $self   = shift;
    my $string = shift;

    my $pid = getppid();

    if($pid == 1){
	syslog(LOG_WARNING,$string);
    }else{
	warn $string;
    }    
}
