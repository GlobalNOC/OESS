use strict;
use warnings;

use Data::Dumper;

use OESS::Mock;
use OESS::MPLS::Device::Juniper::MX;

use Test::More tests => 3;


my $device = OESS::MPLS::Device::Juniper::MX->new(
    config        => '/etc/oess/database.xml',
    loopback_addr => '127.0.0.1',
    mgmt_addr     => '127.0.0.1',
    name          => 'vmx-r0.testlab.grnoc.iu.edu',
    node_id       => 1
);

my $mock = OESS::Mock->new;

my $state = $device->connected();
ok($state == 0, "device disconnected");

$device->{jnx} = $mock;
ok($state == 0, "device disconnected");

$mock->{conn_obj} = 1;
$state = $device->connected();
ok($state == 1, "device connected");
