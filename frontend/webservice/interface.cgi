#!/usr/bin/perl

use strict;
use warnings;

use GRNOC::WebService::Method;
use GRNOC::WebService::Dispatcher;
use OESS::DB;
use OESS::Interface;
use OESS::VRF;

my $db = OESS::DB->new();
my $svc = GRNOC::WebService::Dispatcher->new();


sub register_ro_methods{

    my $method = GRNOC::WebService::Method->new(
        name => "get_available_vlans",
        description => "returns a list of available vlan tags ",
        callback => sub { get_available_vlans(@_) }
        );

    $method->add_input_parameter( name => 'interface_id',
                                  pattern => $GRNOC::WebService::Regex::INTEGER,
                                  required => 1,
                                  description => 'Interface ID to fetch details'
        );
    
    $method->add_input_parameter( name => 'workgroup_id',
                                  pattern => $GRNOC::WebService::Regex::INTEGER,
                                  required => 1,
                                  description => 'Workgroup ID to fetch details'
        );

    $method->add_input_parameter( name => 'vrf_id',
                                  patern => $GRNOC::WebService::Regex::INTEGER,
                                  required => 0,
                                  description => 'VRF ID of the VRF being edited (if one is being edited)');
    
    $method->add_input_parameter( name => 'circuit_id',
                                  patern => $GRNOC::WebService::Regex::INTEGER,
                                  required => 0,
                                  description => 'VRF ID of the VRF being edited (if one is being edited)');

    $svc->register_method($method);


    $method = GRNOC::WebService::Method->new(
        name => "is_vlan_available",
        description => "returns 1 or 0 if the vlan tag is available",
        callback => sub { is_vlan_available(@_) });

    $method->add_input_parameter( name => "interface_id",
                                  pattern => $GRNOC::WebService::Regex::INTEGER,
                                  required => 1,
                                  description => "Interface ID to check and see if VLAN tag is available");
    $method->add_input_parameter( name => 'workgroup_id',
                                  pattern => $GRNOC::WebService::Regex::INTEGER,
                                  required => 1,
                                  description => 'Workgroup ID to fetch details'
        );
    
    $method->add_input_parameter( name => 'vlan',
                                  pattern => $GRNOC::WebService::Regex::INTEGER,
                                  required => 1,
                                  description => 'VLAN to check and see if it is avaialble'
        );
    

    $svc->register_method($method);
}

sub register_rw_methods{
    
}

sub get_available_vlans{
    my $method = shift;
    my $params = shift;

    my $interface_id = $params->{'interface_id'}{'value'};
    my $workgroup_id = $params->{'workgroup_id'}{'value'};

    my $vrf_id = $params->{'vrf_id'}{'value'};
    my $circuit_id = $params->{'circuit_id'}{'value'};

    my $interface = OESS::Interface->new(interface_id => $interface_id, db => $db);
    if(!defined($interface)){
        $method->set_error("Unable to build interface $interface_id: " . $db->get_error);
        return;
    }

    my $already_used_vlan;
    if(defined($vrf_id)){
        my $vrf = OESS::VRF->new( vrf_id => $vrf_id, db => $db);
        if(!defined($vrf)){
            $method->set_error("unable to find VRF: $vrf_id");
            return;
        }
        
        foreach my $ep (@{$vrf->endpoints()}){
            if($ep->interface()->interface_id() == $interface_id){
                $already_used_vlan = $ep->tag();
            }
        }
    }
    

    my @allowed_vlans;
    for(my $i=1;$i<=4095;$i++){
        if(defined($already_used_vlan) && $already_used_vlan == $i){
            push(@allowed_vlans,$i);
            next;
        }
        if($interface->vlan_valid( workgroup_id => $workgroup_id, vlan => $i )){
            push(@allowed_vlans,$i);
        }
        
    }

    return {results => {available_vlans => \@allowed_vlans}};
}

sub is_vlan_available{
    my $method = shift;
    my $params = shift;

    my $interface_id = $params->{'interface_id'}{'value'};
    my $workgroup_id = $params->{'workgroup_id'}{'value'};
    my $vlan = $params->{'vlan'}{'value'};

    my $interface = OESS::Interface->new(interface_id => $interface_id, db => $db);
    if(!defined($interface)){
        $method->set_error("Unable to build interface $interface_id: " . $db->get_error);
        return;
    }

    return {results => {allowed => $interface->vlan_valid( workgroup_id => $workgroup_id, vlan => $vlan )}};
}

sub main{

    register_ro_methods();
    register_rw_methods();
    $svc->handle_request();
}

main();
