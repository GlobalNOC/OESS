#!/usr/bin/perl
use strict;
use FindBin;
use Carp::Always;
use Data::Dumper;
my $path;

BEGIN {
    if($FindBin::Bin =~ /(.*)/){
	$path = $1;
    }
}
use lib "$path";
use lib "$path/../lib/";

use OESS::Traceroute;
use OESS::Circuit;
use OESSDatabaseTester;
use Test::More skip_all => 'Need to try using Dbus::MockObject / MockService';
my $circuit_id = 101;

Log::Log4perl::init_and_watch('t/conf/logging.conf',10);

my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );

my $circuit = OESS::Circuit->new( circuit_id => 101, db => $db);

my $bus = Net::DBus->system;
my $service = $bus->export_service("org.nddi.test.traceroute");
my $traceroute = OESS::Traceroute->new($service);

my $trace = OESS::Traceroute->new($service,{db => $db});

#get circuit_id;


#create circuit;
#my $circuit = OESS::Circuit->new(db => $db, circuit_id => $circuit_id);
ok(defined($circuit));
#diag Dumper($circuit);
my $endpoints = $circuit->get_endpoints;
ok(defined($endpoints));
diag Dumper ($endpoints);
#includes nox calls, going to test building traceroute flowrules first
#init_circuit_trace($circuit_id, $endpoints->[0]->{'interface_id'});

my $success =$trace->add_traceroute_transaction( circuit_id => $circuit_id,
                                                 ttl => 30,
                                                 remaining_endpoints => 1,#scalar @{$circuit->get_endpoints} -1,
                                                 source_endpoint => { dpid => 
                                                                      port_no => $endpoints->[0]->{'port_no'}
                                                 }
    );
ok($success, "added traceroute transaction for circuit");
my $rules = $trace->build_trace_rules($circuit_id);
ok(defined $rules);
is ( scalar @$rules, scalar @{$circuit->get_flows()}, "number of rules in circuit matches number of rules in traceroute");

#diag "traceroute transactions: ".Dumper ($trace->get_traceroute_transactions());

my $ttl = $trace->get_traceroute_transactions(circuit_id => $circuit_id);
diag Dumper($ttl);
is($ttl->{'ttl'},30, "TTL is set to 30");
$trace->{transactions}->{$circuit_id}->{'ttl'}--;
$ttl = $trace->get_traceroute_transactions(circuit_id => $circuit_id);
is ($ttl->{'ttl'},30,"ttl was decremented to 29");


