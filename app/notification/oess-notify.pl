#!/usr/bin/perl
#------ NDDI OESS Notfication Daemon
##-----
##----- $HeadURL:
##----- $Id:
##-----
##----- Daemon listens to events from circuit provisioning,modification, and failovers and sends notifications.
##---------------------------------------------------------------------
##
## Copyright 2013 Trustees of Indiana University
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

use strict;
use OESS::DBus;
use OESS::Notification;
use Proc::Daemon;
use Log::Log4perl;
use Getopt::Long;
use Data::Dumper;

#OESS Notification Daemon.
my $log;

sub connect_to_dbus {

    Log::Log4perl::init_and_watch('/etc/oess/logging.conf',10);
    $log = Log::Log4perl->get_logger("NOTIFY");

    my $fwdctl_dbus = OESS::DBus->new(
        service  => 'org.nddi.fwdctl',
        instance => '/controller1',
        timeout => -1,
        sleep_interval => .1
    );

    my $dbus = OESS::DBus->new(
        service  => 'org.nddi.openflow',
        instance => '/controller1'
    );

    ##dbus registers events to listen for on creation / scheduled
    my $bus     = Net::DBus->system;
    my $service = $bus->export_service("org.nddi.notification");

    #OESS::Notification listens on 'org.nddi.notification'
    my $notification = OESS::Notification->new(
        service     => $service,
        config_file => '/etc/oess/database.xml'
    );

    if ( !defined $notification ) {    
        die("could not export org.nddi.notification service");
    }

    #closure allows us to have notification object in scope when fwdctl events fire
    my $callback = sub {
        my ($circuit) = @_;
        $notification->circuit_notification($circuit);
    };

    if ( defined($fwdctl_dbus) ) {
        warn "connecting to signal_circuit_failover signal";
        $fwdctl_dbus->connect_to_signal( "circuit_notification", $callback );
    }
    else {
        die;
    }

    $fwdctl_dbus->start_reactor();

}

sub main {
    connect_to_dbus;
}

our ( $opt_f, $opt_u );
my $result = GetOptions(
    "foreground" => \$opt_f,
    "user=s"     => \$opt_u
);

if ($opt_f) {
    $SIG{HUP} = sub { die; };
    main();
}
else {
    my $daemon;
    if ($opt_u) {
        my $new_uid = getpwnam($opt_u);
        $daemon = Proc::Daemon->new(
            setuid   => $new_uid,
            pid_file => '/var/run/oess/oess-notify.pid'
        );
    }
    else {
        $daemon =
          Proc::Daemon->new( pid_file => '/var/run/oess/oess-notify.pid' );
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
    `chmod 0644 /var/run/oess/oess-notify.pid`;
}

