#!perl -T

use Test::More tests => 2;

BEGIN {
        use_ok( 'OESS::DBus' );
}
diag( "Testing OESS::DBus $OESS::DBus::VERSION, Perl $], $^X" );
my @methods = qw/get_error connect_to_signal fire_signal log start_reactor/;

can_ok("OESS::DBus",@methods);
