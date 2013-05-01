#!/usr/bin/perl
#------ NDDI OESS Syslogger Interaction Module
##-----
##----- $HeadURL: $
##----- $Id: $
##----- $Date: $
##----- $LastChangedBy: $
##-----
##----- Provides DBus methods for interacting with Syslog 
##-------------------------------------------------------------------------
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

=head1 NAME

OESS::Syslogger - Interacting with DBus events that need to be syslogged

=head1 VERSION

Version 1.0.7

=cut

    our $VERSION = '1.0.7';


=head1 SYNOPSIS

=cut

package OESS::Syslogger;

use strict;
use Net::DBus::Exporter qw (org.nddi.syslogger);
use Net::DBus qw(:typing);
use Data::Dumper();
use base qw(Net::DBus::Object);

sub new {

	my $class = shift;
   	my $service = shift;

   	my $self = $class->SUPER::new($service, "/controller1");

	

	bless $self, $class;

	dbus_signal("signal_circuit_provision", [["dict","string",["variant"]]],['string']);
	dbus_signal("signal_circuit_modify", [["dict","string",["variant"]]]);
	dbus_signal("signal_circuit_decommission",  [["dict","string",["variant"]]],['string']);

	dbus_method("circuit_provision", [["dict","string",["variant"]]],['string']);
	dbus_method("circuit_modify", [["dict","string",["variant"]]],['string']);
	dbus_method("circuit_decommission",  [["dict","string",["variant"]]],['string']);


		
	return $self;

}



sub circuit_provision {
	my $self = shift;
	my $circuit = shift;

	$self->emit_signal("signal_circuit_provision", $circuit);

}



sub circuit_modify {
	my $self = shift;
	my $circuit = shift;
	
	$self->emit_signal("signal_circuit_modify", $circuit);

}

    

sub circuit_decommission {
	my $self = shift;
	my $circuit = shift;

	$self->emit_signal("signal_circuit_decommission", $circuit);

}


1;
