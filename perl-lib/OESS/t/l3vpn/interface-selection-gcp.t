#!/usr/bin/perl


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
          'entity' => 'Indiana University'
      },
      {
          'bandwidth' => '0',
          'tag' => '1001',
          'peerings' => [
              {'asn' => '','key' => '','local_ip' => '','peer_ip' => '','version' => 4}
          ],
          'cloud_account_id' => '123456789123',
          'entity' => 'US East - Hosted VIF'
      },
      {
          'bandwidth' => '50',
          'tag' => '1001',
          'peerings' => [
              {'asn' => '','key' => '','local_ip' => '','peer_ip' => '','version' => 4}
          ],
          'cloud_account_id' => '12345678-1234-1234-1234-123456789abc/us-east4/1',
          'entity' => 'US East4'
      }
  ]
};

