package OESS::Syslogger;

#For events Syslogger is registering to be available for listeners in things like the webservice and the scheduler/elsewhere we're running this syslogger DBus server

use Net::DBus::Exporter qw (org.nddi.syslogger);
use Net::DBus qw(:typing);
use Data::Dumper();
use base qw(Net::DBus::Object);

sub new {

	my $class = shift;
   	my $service = shift;

   	$self = $class->SUPER::new($service, "/controller1");

	

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

    

sub circuit_decomission {
	my $self = shift;
	my $circuit = shift;

	$self->emit_signal("signal_circuit_decomission", $circuit);

}


1;
