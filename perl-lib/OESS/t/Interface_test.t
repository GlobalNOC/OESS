#!/usr/bin/perl

use OESS::Interface;
use Test::More tests => 12;
use Log::Log4perl;
use OESS::DB::Interface;
use OESS::DB;
use OESS::Database;
use Data::Dumper;
use Test::Deep;
use OESS::DB::Interface;


# Initialize logging
Log::Log4perl->init("/etc/oess/logging.conf");

# Initialize DB
my $db = OESS::DB->new();
my $database = OESS::Database->new();
#Test Query
#my $query = "SELECT TOP 5 FROM node ORDER BY name";

my $interface_id = $db->execute_query("SELECT interface_id from interface_acl LIMIT 1");

$interface_id = (@$interface_id[0]->{'interface_id'});


# Initialize instance of interfaceusing interface id
my $interface = OESS::Interface->new(	db 	=> $db,
					interface_id => $interface_id
						);

ok(defined($interface)
	,"Object  of type interface initiated");

$query = "SELECT * FROM interface where interface_id=".$interface_id;
my $test_interface = ($db->execute_query($query))[0][0];
#warn Dumper ($test_interface);

ok($interface->operational_state eq ($test_interface->{'operational_state'})
	, "The method operational_state() returns the right information");

ok($interface->interface_id() eq ($interface_id)
	, "The method interface_id() returns correct information");

ok($interface->name() eq ($test_interface->{'name'})
	, " The method name() returns correct information");

$a = $interface->cloud_interconnect_type;
$b = $test_interface->{'cloud_interconnect_type'};
ok($a eq $b , "The method cloud_interconnect_type() returns correct information");

ok($interface->description() eq $test_interface->{'description'}, "The method description() returns correct information");

#ok($interface->port_number() eq $test_interface->{'port_number'}, "The method port_number() returns correct information");

my $acls = OESS::ACL->new( db => $db, interface_id => $interface_id);
cmp_deeply($interface->acls()->{'acls'} 
		, $acls->{'acls'}
		," The method acls() returns correct object");


ok(($interface->node)->node_id eq ($test_interface->{'node_id'}), "The method node() returns the correct node");


cmp_deeply($interface->mpls_vlan_tag_range(), $test_interface->{'mpls_vlan_tag_range'}
		, "The method mpls_vlan_tag_range() returns the expected result");

### Test : used_vlans ###
my $used_vlans = $db->execute_query("select vrf_ep.tag from vrf_ep join vrf 
			on vrf_ep.vrf_id = vrf.vrf_id where vrf.state = 'active' 
			and vrf_ep.state = 'active' and vrf_ep.interface_id = ?",[$interface_id]);

my $parameter = "extern_vlan_id";
my $circuit_vlans =  ($database->_execute_query("SELECT $parameter 
			FROM circuit_edge_interface_membership WHERE interface_id=".$interface_id))[0];
foreach my $vlan  (@$circuit_vlans){
	push(@$used_vlans,$vlan->{$parameter});
}
cmp_deeply($used_vlans, $interface->used_vlans, "The method used_vlans() returns expected output");


### Test : vlan_in_use ###
my $test1 = $interface->vlan_in_use(@$used_vlans[0]);
my $test2 = not $interface->vlan_in_use(5555);
ok($test1 and $test2,"The method vlan_in_use() does return 1 if vlan is present or 0 when it is not" );


### Test : vlan_valid ###
$test1 = $interface->vlan_in_use("1234");
$test2 = not $interface->vlan_in_use(@$used_vlans[0]);

my $test_vlan;
foreach my $vlan (@$used_vlans)
{
if ($vlan >= $acls->{'acls'}[0]->{'start'} and $vlan <= $acls->{'acls'}[0]->{'end'})
	{
		$test_vlan = $vlan;
	}
}
if(!defined($test_vlan))
{
	warn Dumper("test vlan is undefined");
}
my $vlan_allowed = $db->execute_query(" SELECT * FROM interface_acl WHERE vlan_start <=? AND vlan_end >= ? ",[$test_vlan, $test_vlan ]);
#warn Dumper($db->execute_query("select * from interface_acl LIMIT 5"));
if(scalar @$vlan_allowed > 0)
{
	$test3 = ($interface->acls()->vlan_allowed( vlan=>$test_vlan, workgroup_id => @$vlan_allowed[0]->{'workgroup_id'}),
		 "The given vlan are within start and end range");
}
else{
$test3 = 0 ;
}

$test4 =(defined($interface->mpls_range()->{$vlan}));

ok($test1 and $test2 and $test3 and  $test4, "The method vlan_valid() is giving valid results");
