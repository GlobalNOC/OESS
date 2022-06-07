#!perl -T

use Test::More tests => 35;

BEGIN {
    use_ok( 'OESS::Database' );
    use_ok( 'OESS::Topology' );
    use_ok( 'OESS::DBus' );
    use_ok( 'OESS::FlowRule' );
    use_ok( 'OESS::Circuit' );
    use_ok( 'OESS::Cloud' );
    use_ok( 'OESS::Cloud::AWS' );
    use_ok( 'OESS::Cloud::Azure' );
    use_ok( 'OESS::Cloud::AzurePeeringConfig' );
    use_ok( 'OESS::Cloud::AzureStub' );
    use_ok( 'OESS::Cloud::AzureSyncer' );
    use_ok( 'OESS::Cloud::AzureInterfaceSelector' );
    use_ok( 'OESS::Cloud::GCP' );
    use_ok( 'OESS::Cloud::Oracle' );
    use_ok( 'OESS::Cloud::OracleStub' );
    use_ok( 'OESS::Cloud::OracleSyncer' );
    use_ok( 'OESS::Cloud::PeeringConfig' );
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
    use_ok( 'OESS::NSO::Client' );
    use_ok( 'OESS::NSO::ClientStub' );
    use_ok( 'OESS::NSO::ConnectionCache' );
    use_ok( 'OESS::NSO::Discovery' );
    use_ok( 'OESS::NSO::FWDCTL' );
    use_ok( 'OESS::NSO::FWDCTLService' );
}


