#!/usr/bin/perl

use strict;
use warnings;
use OESS::Watchdog;
use Log::Log4perl;

use Proc::Daemon;
use English;
use Getopt::Long;

sub main{
    my $is_daemon = 0;
    my $verbose;
    my $username;

    my $logger = Log::Log4perl->init_and_watch('/etc/oess/logging.conf');

    my $result = GetOptions (
                             "user|u=s"  => \$username,
                             "verbose"   => \$verbose,
                             "daemon|d"  => \$is_daemon,
        );


    #now change username/
    if (defined $username) {
        my $new_uid=getpwnam($username);
        my $new_gid=getgrnam($username);
        $EGID=$new_gid;
        $EUID=$new_uid;
    }

    if ($is_daemon != 0) {
        my $daemon;
        if ($verbose) {
            $daemon = Proc::Daemon->new(
                pid_file => '/var/run/oess/oess-watchdog.pid',
                child_STDOUT => '/var/log/oess/oess-watchdog.out',
                child_STDERR => '/var/log/oess/oess-watchdog.log',
                );
        } else {
            $daemon = Proc::Daemon->new(
                pid_file => '/var/run/oess/oess-watchdog.pid'
                );
        }
        my $kid_pid = $daemon->Init;

        if ($kid_pid) {
            `chmod 0644 /var/run/oess/oess-watchdog.pid`;
            return;
        }

        my $watchdog = OESS::Watchdog->new();

        while(1){
            $watchdog->do_work();
            sleep($watchdog->{'interval'});
        }
    }

    #not a deamon, just run the core;
    else {
        $SIG{HUP} = sub{ exit(0); };
        my $watchdog = OESS::Watchdog->new();

        while(1){
            $watchdog->do_work();
            sleep($watchdog->{'interval'});
        }
    }
    
}

main();
