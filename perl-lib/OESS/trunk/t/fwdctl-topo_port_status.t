#!/usr/bin/perl -T

use strict;

use FindBin;
my $path;

BEGIN {
    if($FindBin::Bin =~ /(.*)/){
            $path = $1;
      }
}

use lib "$path";
use OESS::FWDCTL;
use OESSDatabaseTester;

use Test::More tests => 1;
use Test::Deep;
use Data::Dumper;
use OESS::DBus;
use Time::HiRes qw(tv_interval gettimeofday);

#link statuses
use constant OESS_LINK_UP       => 1;
use constant OESS_LINK_DOWN     => 0;
use constant OESS_LINK_UNKNOWN  => 2;

my $dbus = OESS::DBus->new( service => "org.nddi.openflow", instance => "/controller1");
Log::Log4perl::init_and_watch('/etc/oess/logging.conf',10);

my $log = Log::Log4perl->get_logger("FWDCTL");

if (! defined $dbus) {
    exit(1);
}

my $bus = Net::DBus->system;
my $service = $bus->export_service("org.nddi.fwdctl");
my $fwdctl = OESS::FWDCTL->new($service,$dbus->{'dbus'},OESSDatabaseTester::getConfigFilePath());

$fwdctl->_sync_database_to_network();

my $dpid = 155568969984;
my $reason = 0; #add
my $info = { name => 'e1/2',
             port_no => 2,
             link => 1
};

my $start = [gettimeofday];
$fwdctl->topo_port_status($dpid,$reason,$info);
my $elapsed = tv_interval( $start,[gettimeofday] );


warn "Elapsed time: " . $elapsed;
ok($elapsed < 10);
