#!perl -T

use Test::More tests => 17;

BEGIN {
        use_ok( 'OESS::Database' );
        use_ok( 'OESS::Topology' );
        use_ok( 'OESS::DBus' );
        use_ok( 'OESS::FlowRule' );
        use_ok( 'OESS::Circuit' );
        use_ok( 'OESS::Measurement' );
        use_ok( 'OESS::Notification' );
        use_ok( 'OESS::Traceroute');
	use_ok( 'OESS::MPLS::FWDCTL');
	use_ok( 'OESS::MPLS::Switch');
	use_ok( 'OESS::MPLS::Discovery');
	use_ok( 'OESS::MPLS::Device');
	use_ok( 'OESS::MPLS::Device::Juniper::MX');
	use_ok( 'OESS::MPLS::Discovery::Interface');
	use_ok( 'OESS::MPLS::Discovery::ISIS');
	use_ok( 'OESS::MPLS::Discovery::Paths');
	use_ok( 'OESS::MPLS::Topology');
}


