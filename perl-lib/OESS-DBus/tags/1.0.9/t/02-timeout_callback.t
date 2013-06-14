#!perl -T

use Test::More tests => 3;

BEGIN {
        use_ok( 'OESS::DBus' );
}

my $check = 0;

my $dbus = OESS::DBus->new(instance          => "super_fake_1234567",
			   service           => "also_fake_09876543",
			   timeout           => 5,
			   sleep_interval    => 1,
			   timeout_callback  => sub {
			                          $check = 1;
			                        }
                           );

is($dbus, undef, "verifying timed out connecting to fake service");

is($check, 1, "verifying that timeout callback was executed");
