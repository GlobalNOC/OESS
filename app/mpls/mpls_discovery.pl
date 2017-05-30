#!/usr/bin/perl

use strict;
use warnings;
use AnyEvent;

use English;
use Getopt::Long;
use Proc::Daemon;
use Data::Dumper;

use OESS::Database;
use OESS::MPLS::Discovery;

my $pid_file = "/var/run/oess/mpls_discovery.pid";

sub core{
    #basic init stuffs
    Log::Log4perl::init_and_watch('/etc/oess/logging.conf',10);

    my $discovery = OESS::MPLS::Discovery->new();
    AnyEvent->condvar->recv;
}

sub main{
    my $is_daemon = 0;
    my $verbose;
    my $username;
    #remove the ready file

    #--- see if the pid file exists. if not then just continue running.
    if(-e $pid_file){
        #--- read the file to get the PID
        my $pid = `head -n 1 $pid_file`;
        chomp $pid;

        my $run_test = `ps -p $pid | grep $pid`;

        #--- if run test is empty then the pid didn't exist. If it isn't empty then the process is already running.
        if($run_test){
            print "Found $0 process: $pid already running. Aborting.\n";
            exit(0);
        }
        else{
            print "Pid File: $pid_file already exists but it looks like process $pid is dead. Continuing startup.\n";
        }
    }

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
                                        pid_file => $pid_file,
                                        child_STDOUT => '/var/log/oess/mpls.out',
                                        child_STDERR => '/var/log/oess/mpls.log',
                );
        } else {
            $daemon = Proc::Daemon->new(
                pid_file => $pid_file
                );
        }

        # Init returns the PID (scalar) of the daemon to the parent, or
        # the PIDs (array) of the daemons created if exec_command has
        # more then one program to execute.
        #
        # Init returns 0 to the child (daemon).
        my $kid_pid = $daemon->Init;
        if ($kid_pid) {
            `chmod 0644 $pid_file`; # How to wait until the child process is ready.
            return;
        } else {
            core();
        }
    }
    #not a daemon, just run the core;
    else {
        $SIG{HUP} = sub{ exit(0); };
        core();
    }

}

main();

1;
