#!/usr/bin/perl

use OESS::Interface;
use Test::More tests => 19;
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

my $interface_id = 391;

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

ok($interface->name() eq 'e15/1'
	, " The method name() returns correct information");

ok($interface->cloud_interconnect_id() eq undef,"The interconnect id is not defined for interface_id 391");
$a = $interface->cloud_interconnect_type();
ok($a eq undef , "The method cloud_interconnect_type() returns correct information");

ok($interface->description() eq 'e15/1', "The method description() returns correct information");

#ok($interface->port_number() eq $test_interface->{'port_number'}, "The method port_number() returns correct information");

my $acls = OESS::ACL->new( db => $db, interface_id => $interface_id);
cmp_deeply($interface->acls()->{'acls'} 
		, $acls->{'acls'}
		," The method acls() returns correct object");

ok(($interface->node())->node_id eq ($test_interface->{'node_id'}), "The method node() returns the correct node");

cmp_deeply($interface->mpls_vlan_tag_range(), '1-10' 
		, "The method mpls_vlan_tag_range() returns the expected result");

### Test : used_vlans ###
cmp_deeply($interface->used_vlans,
	[
          391
        ], "The method used_vlans() returns expected output");

## Test : vlan_in_use ###
my $test1 = $interface->vlan_in_use(391);
my $test2 = not $interface->vlan_in_use(5555);
ok($test1 eq 1,"The method vlan_in_use() does return 1 if vlan is present" );

ok($test2 eq 1, "The method vlan_in_use() does return 0 if vlan is out of bounds");


cmp_deeply($interface->mpls_range(),
{
          '6' => 1,
          '3' => 1,
          '7' => 1,
          '9' => 1,
          '2' => 1,
          '8' => 1,
          '1' => 1,
          '4' => 1,
          '10' => 1,
          '5' => 1
        },"The method mpls_range() returns expected results");
### Test : vlan_valid ###
$test1 = $interface->vlan_in_use("1234");
$test2 = not $interface->vlan_in_use(@$used_vlans[0]);
ok ($interface->vlan_valid(vlan=>3,workgroup_id=>11) eq 1,"The method vlan_valid() does return expected result");
ok($interface->vlan_valid(vlan=>10000,workgroup_id=>11) eq 0, "The method vlan_valid() returns expected result when vlan is out of vlan range");
ok($interface->vlan_valid(vlan=>391,workgroup_id=>11) eq 0, "The method vlan_valid() returns expected result when vlan 391 is in use");
ok($interface->vlan_valid(vlan=>3,workgroup_id=>123)eq 0 , "The method vlan_valid() returns expected result when vlan is not_allowed");
ok($interface->vlan_valid(vlan=>40,workgroup_id=>11) eq 0," The method vlan_valid() returns expected result when vlan is out of mpls_range");
