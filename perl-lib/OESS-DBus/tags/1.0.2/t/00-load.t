#!perl -T

use Test::More tests => 1;

BEGIN {
        use_ok( 'OESS::DBus' );
}
diag( "Testing OESS::DBus $OESS::DBus::VERSION, Perl $], $^X" );
