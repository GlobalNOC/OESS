#!/usr/bin/perl

use strict;

#use lib ("../lib");

use OESS::DBus;
use OESS::Notification;
use Proc::Daemon;
use Sys::Syslog qw(:standard :macros);
use Getopt::Long;
use Data::Dumper;

#OESS Notification Daemon.

#create notification object globally
my $notification = OESS::Notification->new(
                                              config_file=>'/etc/oess/notification.xml'
                                         );


sub connect_to_dbus {

   my $prov_dbus = OESS::DBus->new(
        service  => 'org.nddi.syslogger',
        instance => '/controller1'
    );
   my $fwdctl_dbus = OESS::DBus->new(
                                    service =>'org.nddi.fwdctl',
                                    instance=>'/controller1'
                                    );

    if ( defined($prov_dbus) ) {
        $prov_dbus->connect_to_signal( "signal_circuit_provision",   \&notify_provision );
        $prov_dbus->connect_to_signal( "signal_circuit_decommission", \&notify_decomission );
        $prov_dbus->connect_to_signal( "signal_circuit_modify",      \&notify_modification );
    }
    else {
        #syslog( LOG_ERR, "Unable to connect to the DBus" );
        die;
    }
   if (defined ($fwdctl_dbus) ){
       #$fwdctl_dbus->connect_to_signal("signal_circuit_failover", \&notify_failover );

   }
   else {
       die;
   }

   #This is weird, but I believe because Net::DBUS::Reactor (in the internals of OESS::DBus) is a singleton, you're actually registering to one loop in the backend, so only one start_reactor is required..
   $fwdctl_dbus->start_reactor();

}




sub notify_failover{
    my ($circuit) = @_;

    my $circuit_notification_data = $notification->get_notification_data( circuit => $circuit );   
    $circuit->{'clr'} = $circuit_notification_data->{'clr'};
    foreach my $user ( @{$circuit_notification_data->{'affected_users'} } ){

        $notification->send_notification( 
                                           notification_type =>'failover',
                                           username => $circuit_notification_data->{'username'},
                                           contact_data => $user,
                                           circuit_data => $circuit
                                          
                                          );
    }

    

}

sub notify_provision{
    my ($circuit) = @_;

    my $circuit_notification_data = $notification->get_notification_data(  circuit =>$circuit );   
    $circuit->{'clr'} = $circuit_notification_data->{'clr'};
    foreach my $user ( @{$circuit_notification_data->{'affected_users'} } ){

        $notification->send_notification( 
                                           notification_type =>'provision',
                                           username => $circuit_notification_data->{'username'},
                                           contact_data => $user,
                                           circuit_data => $circuit
                                           
                                          );
    }


}

sub notify_decomission {
    my ($circuit) = @_;

    my $circuit_notification_data = $notification->get_notification_data(  circuit =>$circuit );   

    foreach my $user ( @{$circuit_notification_data->{'affected_users'} } ){
    $circuit->{'clr'} = $circuit_notification_data->{'clr'};
        $notification->send_notification( 
                                           notification_type =>'decommission',
                                           username => $circuit_notification_data->{'username'},
                                           contact_data => $user,
                                           circuit_data => $circuit
                                           
                                          );
    }



}

sub notify_modification {
    my ($circuit) = @_;

    my $circuit_notification_data = $notification->get_notification_data( circuit => $circuit );   
    $circuit->{'clr'} = $circuit_notification_data->{'clr'};
    foreach my $user ( @{$circuit_notification_data->{'affected_users'} } ){
        $notification->send_notification( 
                                           notification_type =>'modify',
                                           username => $circuit_notification_data->{'username'},
                                           contact_data => $user,
                                           circuit_data => $circuit
                                          
                                          );
    }

}

sub main{
    connect_to_dbus;
}


our ( $opt_f, $opt_u );
my $result = GetOptions(
    "foreground" => \$opt_f,
    "user=s"     => \$opt_u
);

if ($opt_f) {
    main();
}
else {
    my $daemon;
    if ($opt_u) {
        my $new_uid = getpwnam($opt_u);
        $daemon = Proc::Daemon->new(
            setuid   => $new_uid,
            pid_file => '/var/run/oess/oess_ckt_notify.pid'
        );
    }
    else {
        $daemon =
          Proc::Daemon->new(
            pid_file => '/var/run/oess/oess_ckt_notify.pid' );
    }
    my $kid = $daemon->Init;

    unless ($kid) {
        if ($opt_u) {
            my $new_uid = getpwnam($opt_u);
            my $new_gid = getgrnam($opt_u);
            $) = $new_gid;
            $> = $new_uid;
        }
        main();
    }
}

