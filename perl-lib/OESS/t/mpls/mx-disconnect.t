use strict;
use warnings;

use Data::Dumper;

use OESS::Mock;
use OESS::MPLS::Device::Juniper::MX;

use Test::More tests => 2;


my $device = OESS::MPLS::Device::Juniper::MX->new(
    config        => '/etc/oess/database.xml',
    loopback_addr => '127.0.0.1',
    mgmt_addr     => '127.0.0.1',
    name          => 'vmx-r0.testlab.grnoc.iu.edu',
    node_id       => 1
);

my $mock = OESS::Mock->new;
$device->{jnx} = $mock;

$mock->new_sub(
    name => 'disconnect',
    result => 1
);

$device->disconnect();

my $err = $mock->sub_called(
    name  => 'disconnect',
    count => 1
);

ok(!defined $err, "disconnect called 1 time.");
warn "$err" if defined $err;

ok(!defined $device->{jnx}, "connection object was deleted.");
