#!/usr/bin/perl
use strict;
use warnings;

use FindBin;
my $path;

BEGIN { if ($FindBin::Bin =~ /(.*)/) { $path = $1; } }
use lib "$path/..";

use Data::Dumper;

use Test::More skip_all => 'Work this in later';
# use Test::More tests => 4;

use OESS::DB;
use OESSDatabaseTester;
use OESS::Endpoint;

# 1. Verify that when a GCP interface is specified the interface
# associated with cloud_account_id is used.

# 2. Verify that when a vlan is already in use, on the interface that
# is associated with cloud_account_id, an error is generated.

# NOTE: This request may be used for testing AWS, GCP, and Partner
# interconnects.
my $req = {
  method         => 'provision',
  name           => 'Cloud Connect Demo',
  description    => 'Cloud Connect Demo',
  local_asn      => 1,
  workgroup_id   => 1,
  provision_time => -1,
  remove_time    => -1,
  vrf_id         => -1,
  endpoint       => [
      {
          'bandwidth' => '0',
          'tag' => '1005',
          'peerings' => [
              {'asn' => '7','key' => '','local_ip' => '192.168.2.2/24','peer_ip' => '192.168.2.1/24','version' => 4}
          ],
          'cloud_account_id' => '',
          'workgroup_id'   => 1,
          'entity' => 'Indiana University'
      },
      {
          'bandwidth' => '0',
          'tag' => '1001',
          'peerings' => [
              {'asn' => '','key' => '','local_ip' => '','peer_ip' => '','version' => 4}
          ],
          'cloud_account_id' => '123456789123',
          'workgroup_id'   => 1,
          'entity' => 'AWS vInterface'
      },
      {
          'bandwidth' => '50',
          'tag' => '50',
          'peerings' => [
              {'asn' => '','key' => '','local_ip' => '','peer_ip' => '','version' => 4}
          ],
          'cloud_account_id' => '12345678-1234-1234-1234-123456789abc/us-east4/1',
          'workgroup_id'   => 1,
          'entity' => 'GCP'
      },
      {
          'bandwidth' => '50',
          'tag' => '50',
          'peerings' => [
              {'asn' => '','key' => '','local_ip' => '','peer_ip' => '','version' => 4}
          ],
          'cloud_account_id' => '12345678-1234-1234-1234-123456789abc/us-east4/2',
          'workgroup_id'   => 1,
          'entity' => 'GCP'
      }
  ]
};

my $db = OESS::DB->new(config => "$path/../conf/database.xml" );

my $endpoint = undef;

$endpoint = OESS::Endpoint->new(db => $db, type => 'vrf', model => $req->{endpoint}->[2]);
ok(defined $endpoint, "Endpoint object created.");
ok($endpoint->interface->interface_id == 21, "GCP Zone1 interface selected.");

$endpoint = OESS::Endpoint->new(db => $db, type => 'vrf', model => $req->{endpoint}->[3]);
ok(defined $endpoint, "Endpoint object created.");
ok($endpoint->interface->interface_id == 35961, "GCP Zone2 interface selected.");
