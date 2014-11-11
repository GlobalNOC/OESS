#!perl -T

use strict;
use warnings;
use Test::More tests => 2;

BEGIN {
        use_ok( 'OESS::DBus' );
}


my $dbus = OESS::DBus->new(instance       => "super_fake_1234567",
			   service        => "also_fake_09876543",
			   timeout        => 2,
			   sleep_interval => 1
                           );
			   
is($dbus, undef, "verifying timed out connecting to fake service");
