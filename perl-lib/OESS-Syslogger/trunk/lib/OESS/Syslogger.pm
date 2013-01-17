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

	dbus_signal("circuit_provision", [["dict","string",["variant"]]],['string']);
	dbus_signal("circuit_modify", [["dict","string",["variant"]]],['string']);
	dbus_signal("circuit_decommission",  [["dict","string",["variant"]]],['string']);

		warn Data::Dumper::Dumper($self);
	return $self;

}



sub circuit_provision {
	my $self = shift;
	my $circuit = shift;

}



sub circuit_modify {
	my $self = shift;
	my $circuit = shift;
	warn Data::Dumper::Dumper($circuit);
}

    

sub circuit_decomission {
	my $self = shift;
	my $circuit = shift;

}


1;
