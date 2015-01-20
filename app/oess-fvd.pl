#!/usr/bin/perl

use strict;
use OESS::FV;
use Getopt::Long;
use Proc::Daemon;
use Data::Dumper;
use English;
use Log::Log4perl;

sub main{

    my $is_daemon = 0;
    my $verbose;
    my $username;

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
                                        pid_file => '/var/run/oess/oess-fvd.pid',
                                        child_STDOUT => '/var/log/oess/oess-fvd.out',
                                        child_STDERR => '/var/log/oess/oess-fvd.log',
                );
        } else {
            $daemon = Proc::Daemon->new(
                                        pid_file => '/var/run/oess/oess-fvd.pid'
                );
        }
        my $kid_pid = $daemon->Init;

        if ($kid_pid) {
            `chmod 0644 /var/run/oess/oess-fvd.pid`;
            return;
        }
        my $logger = Log::Log4perl->init_and_watch('/etc/oess/logging.conf');
        my $bfd = OESS::FV->new();
    }
    #not a deamon, just run the core;
    else {
        $SIG{HUP} = sub{ exit(0); };
        my $logger = Log::Log4perl->init_and_watch('/etc/oess/logging.conf');
        my $bfd = OESS::FV->new();
    }

}

main();
