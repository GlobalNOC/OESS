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
#my $notification = OESS::Notification->new(

#                                         );


sub connect_to_dbus {

  # my $prov_dbus = OESS::DBus->new(
   #     service  => 'org.nddi.syslogger',
   #     instance => '/controller1'
   # );
   my $fwdctl_dbus = OESS::DBus->new(
                                    service =>'org.nddi.fwdctl',
                                    instance=>'/controller1'
                                    );

   my $dbus = OESS::DBus->new(service => 'org.nddi.openflow', instance => '/controller1');
   
   ##dbus registers events to listen for on creation / scheduled
   my $bus = Net::DBus->system;
   my $service = $bus->export_service("org.nddi.notification");
   
   my $notification = OESS::Notification->new(service =>$service,
                                               config_file=>'/etc/oess/notification.xml');
   #warn Dumper ($object);
   #warn Dumper $object->{'ws'};
   if (!defined $notification){
        #fuuu
        die("could not export org.nddi.notification service");
    }


    #if ( defined($prov_dbus) ) {
     #   $prov_dbus->connect_to_signal( "signal_circuit_provision",   \&notify_provision );
     #   $prov_dbus->connect_to_signal( "signal_circuit_decommission", \&notify_decomission );
     #   $prov_dbus->connect_to_signal( "signal_circuit_modify",      \&notify_modification );
    #}
    #else {
        #syslog( LOG_ERR, "Unable to connect to the DBus" );
     #   die;
    #}

   my $callback =  sub {
           my ($circuit,$success) = @_;
           $notification->notify_failover($circuit,$success);

       };
   
   if (defined ($fwdctl_dbus) ){
       warn "connecting to signal";
       

       $fwdctl_dbus->connect_to_signal("signal_circuit_failover", $callback );

   }
   else {
       die;
   }

   $fwdctl_dbus->start_reactor();

}




# sub notify_failover{
#     my ($circuit,$success) = @_;
        
#     my $circuit_notification_data = $notification->get_notification_data( circuit => $circuit );   
#     #$circuit->{'clr'} = $circuit_notification_data->{'clr'};
#     #warn "$success";
#     foreach my $user ( @{$circuit_notification_data->{'affected_users'} } ){

#         $notification->send_notification( 
#                                            notification_type =>"failover_$success",
#                                            username => $circuit_notification_data->{'username'},
#                                            contact_data => $user,
#                                            circuit_data => $circuit_notification_data->{'circuit'}
                                          
#                                           );
#     }

    

# }

# sub notify_provision{
#     my ($circuit) = @_;

#     my $circuit_notification_data = $notification->get_notification_data(  circuit =>$circuit );   
#     $circuit->{'clr'} = $circuit_notification_data->{'clr'};
#     foreach my $user ( @{$circuit_notification_data->{'affected_users'} } ){

#         $notification->send_notification( 
#                                            notification_type =>'provision',
#                                            username => $circuit_notification_data->{'username'},
#                                            contact_data => $user,
#                                            circuit_data => $circuit
                                           
#                                           );
#     }


# }

# sub notify_decomission {
#     my ($circuit) = @_;

#     my $circuit_notification_data = $notification->get_notification_data(  circuit =>$circuit );   

#     foreach my $user ( @{$circuit_notification_data->{'affected_users'} } ){
#     $circuit->{'clr'} = $circuit_notification_data->{'clr'};
#         $notification->send_notification( 
#                                            notification_type =>'decommission',
#                                            username => $circuit_notification_data->{'username'},
#                                            contact_data => $user,
#                                            circuit_data => $circuit
                                           
#                                           );
#     }



# }

# sub notify_modification {
#     my ($circuit) = @_;

#     my $circuit_notification_data = $notification->get_notification_data( circuit => $circuit );   
#     $circuit->{'clr'} = $circuit_notification_data->{'clr'};
#     foreach my $user ( @{$circuit_notification_data->{'affected_users'} } ){
#         $notification->send_notification( 
#                                            notification_type =>'modify',
#                                            username => $circuit_notification_data->{'username'},
#                                            contact_data => $user,
#                                            circuit_data => $circuit
                                          
#                                           );
#     }

# }

sub main{
    connect_to_dbus;
}
#sub fwdctl_failover_callback{
#    my $notification = shift;
#    my ($circuit,$success) = @_;

    
    
#}
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

