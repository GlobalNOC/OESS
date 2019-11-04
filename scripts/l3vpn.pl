#!/usr/bin/perl
use strict;
use warnings;
use GRNOC::WebService::Client;
use Getopt::Long;

my $status = 1;
my $vrfid = '';
my $status_str = 'Endpoints with following peer ips are down:';	
my $url = '';
my $idpurl = '';
my $uname = '';
my $passwd = '';
GetOptions ('vrfid=i' => \$vrfid, 'url=s' => \$url, 'idpurl=s' => \$idpurl, 'uname=s' => \$uname, 'passwd=s' => \$passwd);


my $websvc = GRNOC::WebService::Client->new( url => $url,
                                             realm => $idpurl,
                                             uid => $uname,
                                             passwd => $passwd,
                                             timeout => 60 );

my $results = $websvc->get_vrf_details(vrf_id => $vrfid);
$results = $results->{'results'};

my $endpoints = shift(@$results);
$endpoints = $endpoints->{'endpoints'};

foreach my $endpoint (@$endpoints){
        my $peers = $endpoint->{'peers'};

        foreach my $peer (@$peers) {
                if(defined($peer->{'operational_state'})){
                        if($peer->{'operational_state'} eq 'down'){
                                $status_str = $status_str . ' ' . $peer->{peer_ip};
                                $status = 0;
                        }
                }
        }

}

if($status){
        print 'vrfs work fine!';
        exit(0);
}
else{
        print $status_str . "\n";
        exit(2);
}





