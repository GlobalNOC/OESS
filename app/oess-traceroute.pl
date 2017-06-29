#!/usr/bin/perl

use strict;

use Data::Dumper;
use English;
use Getopt::Long;
use Log::Log4perl;
use OESS::Traceroute;
use Proc::Daemon;


sub main{

    my $is_daemon = 0;
    my $verbose;
    my $username;

    my $result = GetOptions ("user|u=s"  => \$username,
                             "verbose"   => \$verbose,
                             "daemon|d"  => \$is_daemon);

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
            $daemon = Proc::Daemon->new(pid_file     => '/var/run/oess/oess-traceroute.pid',
                                        child_STDOUT => '/var/log/oess/oess-traceroute.out',
                                        child_STDERR => '/var/log/oess/oess-traceroute.log');
        } else {
            $daemon = Proc::Daemon->new(pid_file => '/var/run/oess/oess-traceroute.pid');
        }

        my $kid_pid = $daemon->Init;
        if ($kid_pid) {
            `chmod 0644 /var/run/oess/oess-traceroute.pid`;
            return;
        }
    } else { # Not a daemon, just run the core;
        $SIG{HUP} = sub{ exit(0); };
    }

    my $logger     = Log::Log4perl->init_and_watch('/etc/oess/logging.conf');
    my $traceroute = OESS::Traceroute->new();
    $traceroute->start();
}

main();
