package OESS::Syslogger;

#For events Syslogger is registering to be available for listeners in things like the webservice and the scheduler/elsewhere we're running this syslogger DBus server

use Net::DBus::Exporter qw (org.nddi.syslogger);
use base qw(Net::DBus::Object);

sub new {

	my $class = shift;
   	my $service = shift;

   	$self = $class->SUPER::new($service, "/controller1");

	
    


	bless $self, $class;
	return $self;

}

dbus_method("circuit_create", ["dict","string","string"]);

sub circuit_create {
	my $self = shift;
	my $circuit = shift;

}

dbus_method("circuit_modify", ["dict","string","string"]);

sub circuit_modify {
	my $self = shift;
	my $circuit = shift;
}

    dbus_method("circuit_decom",  ["dict","string","string"]);

sub circuit_decom {
	my $self = shift;
	my $circuit = shift;

}


1;
