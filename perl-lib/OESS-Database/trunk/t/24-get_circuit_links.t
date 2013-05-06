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
use OESSDatabaseTester;

use Test::More tests => 4;
use Test::Deep;
use OESS::Database;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

my $links = $db->get_circuit_links( circuit_id => 4011);
#warn Dumper ($links);
#ok($#{$links} == 1, "Total number of links match");

cmp_deeply($links, [
                    {
            'interface_z' => 'e1/2',
            'port_no_z' => '2',
            'node_z' => 'Node 71',
            'port_no_a' => '1',
            'node_a' => 'Node 41',
            'name' => 'Link 61',
            'interface_a' => 'e1/1'
          },
                    {
            'interface_z' => 'e5/1',
            'port_no_z' => '193',
            'node_z' => 'Node 111',
            'port_no_a' => '2',
            'node_a' => 'Node 41',
            'name' => 'Link 101',
            'interface_a' => 'e1/2'
          },
                    {
            'interface_z' => 'e1/1',
            'port_no_z' => '1',
            'node_z' => 'Node 141',
            'port_no_a' => '1',
            'node_a' => 'Node 71',
            'name' => 'Link 151',
            'interface_a' => 'e1/1'
          },
                    {
            'interface_z' => 'e3/1',
            'port_no_z' => '97',
            'node_z' => 'Node 141',
            'port_no_a' => '97',
            'node_a' => 'Node 11',
            'name' => 'Link 171',
            'interface_a' => 'e3/1'
          },
          {
            'interface_z' => 'e1/1',
            'port_no_z' => '1',
            'node_z' => 'Node 111',
            'port_no_a' => '1',
            'node_a' => 'Node 31',
            'name' => 'Link 221',
            'interface_a' => 'e1/1'
          }
        ], "Links returned as expected"
);

my $backup_links = $db->get_circuit_links( circuit_id =>4011 , type=>'backup' );
warn Dumper ($backup_links);
cmp_deeply ($backup_links, [
                            {
            'interface_z' => 'e1/2',
            'port_no_z' => '2',
            'node_z' => 'Node 21',
            'port_no_a' => '97',
            'node_a' => 'Node 31',
            'name' => 'Link 1',
            'interface_a' => 'e3/1'
          },
                            {
            'interface_z' => 'e5/1',
            'port_no_z' => '193',
            'node_z' => 'Node 101',
            'port_no_a' => '97',
            'node_a' => 'Node 21',
            'name' => 'Link 21',
            'interface_a' => 'e3/1'
          },
                            {
            'interface_z' => 'e3/2',
            'port_no_z' => '98',
            'node_z' => 'Node 11',
            'port_no_a' => '97',
            'node_a' => 'Node 61',
            'name' => 'Link 181',
            'interface_a' => 'e3/1'
          },
                            {
            'interface_z' => 'e1/1',
            'port_no_z' => '1',
            'node_z' => 'Node 51',
            'port_no_a' => '1',
            'node_a' => 'Node 61',
            'name' => 'Link 191',
            'interface_a' => 'e1/1'
          },
                            {
            'interface_z' => 'e3/1',
            'port_no_z' => '97',
            'node_z' => 'Node 101',
            'port_no_a' => '97',
            'node_a' => 'Node 91',
            'name' => 'Link 231',
            'interface_a' => 'e3/1'
          },
                            {
            'interface_z' => 'e1/1',
            'port_no_z' => '1',
            'node_z' => 'Node 5721',
            'port_no_a' => '2',
            'node_a' => 'Node 91',
            'name' => 'Link 521',
            'interface_a' => 'e1/2'
          },
                            {
            'interface_z' => 'e3/2',
            'port_no_z' => '98',
            'node_z' => 'Node 51',
            'port_no_a' => '97',
            'node_a' => 'Node 5721',
            'name' => 'Link 531',
            'interface_a' => 'e3/1'
          }
        ], "backup links match");

my $decom_ckt_links = $db->get_circuit_links( circuit_id => 221, show_historical => 1);
warn Dumper ($decom_ckt_links);

cmp_deeply($decom_ckt_links,[
                             {
            'interface_z' => 'e1/2',
            'port_no_z' => '2',
            'node_z' => 'Node 71',
            'port_no_a' => '1',
            'node_a' => 'Node 41',
            'name' => 'Link 61',
            'interface_a' => 'e1/1'
          },
                             {
            'interface_z' => 'e5/1',
            'port_no_z' => '193',
            'node_z' => 'Node 111',
            'port_no_a' => '2',
            'node_a' => 'Node 41',
            'name' => 'Link 101',
            'interface_a' => 'e1/2'
          },
                             {
            'interface_z' => 'e1/1',
            'port_no_z' => '1',
            'node_z' => 'Node 141',
            'port_no_a' => '1',
            'node_a' => 'Node 71',
            'name' => 'Link 151',
            'interface_a' => 'e1/1'
          }
        ]    
, "Got decommissioned primary links"
           );

my $decom_backup_ckt_links = $db->get_circuit_links( circuit_id => 221, type=>'backup', show_historical => 1);
cmp_deeply($decom_backup_ckt_links,[
                                    {
            'interface_z' => 'e15/6',
            'port_no_z' => '678',
            'node_z' => 'Node 91',
            'port_no_a' => '676',
            'node_a' => 'Node 51',
            'name' => 'Link 71',
            'interface_a' => 'e15/4'
          },
                                    {
            'interface_z' => 'e3/1',
            'port_no_z' => '97',
            'node_z' => 'Node 141',
            'port_no_a' => '97',
            'node_a' => 'Node 11',
            'name' => 'Link 171',
            'interface_a' => 'e3/1'
          },
                                    {
            'interface_z' => 'e3/2',
            'port_no_z' => '98',
            'node_z' => 'Node 11',
            'port_no_a' => '97',
            'node_a' => 'Node 61',
            'name' => 'Link 181',
            'interface_a' => 'e3/1'
          },
                                    {
            'interface_z' => 'e1/1',
            'port_no_z' => '1',
            'node_z' => 'Node 51',
            'port_no_a' => '1',
            'node_a' => 'Node 61',
            'name' => 'Link 191',
            'interface_a' => 'e1/1'
          }
        ],"got decom backup links"
);
#warn Dumper($decom_ckt_links);
#ok ($decom_ckt_links, 'links exist');


