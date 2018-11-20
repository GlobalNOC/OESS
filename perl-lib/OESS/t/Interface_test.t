#!/usr/bin/perl  -T

use OESS::Interface;
use Test::More tests => 30;
use Log::Log4perl;
use OESS::DB;
use Data::Dumper;
use Test::Deep;


# Initialize logging
Log::Log4perl->init("/etc/oess/logging.conf");

# Initialize DB
my $db = OESS::DB->new();

my $interface_id = 391;

# Initialize instance of interfaceusing interface id
my $interface = OESS::Interface->new(	db 	=> $db,
					interface_id => $interface_id
						);
ok(defined($interface)
	,"Object  of type interface initiated");
$query = "SELECT * FROM interface where interface_id=".$interface_id;
my $test_interface = ($db->execute_query($query))[0][0];

ok($interface->operational_state() eq ("up")
	, "The method operational_state() returns the right information");

ok($interface->interface_id() eq ($interface_id)
	, "The method interface_id() returns correct information");

ok($interface->name() eq 'e15/1'
	, " The method name() returns correct information");

ok($interface->cloud_interconnect_id() eq 'Test',"The method cloud_interconnect_id() gives expected output for interface_id 391");
$a = $interface->cloud_interconnect_type();
ok($a eq undef , "The method cloud_interconnect_type() returns correct information");

ok($interface->description() eq 'e15/1', "The method description() returns correct information");

#ok($interface->port_number() eq $test_interface->{'port_number'}, "The method port_number() returns correct information");

cmp_deeply($interface->acls()->{'acls'} ,
[
          {
            'eval_position' => '10',
            'workgroup_id' => '11',
            'allow_deny' => 'deny',
            'entity_id' => '7',
            'end' => undef,
            'start' => 1
          },
          {
            'eval_position' => '20',
            'workgroup_id' => 11,
            'allow_deny' => 'allow',
            'entity_id' => '7',
            'end' => 4095,
            'start' => 1
          }
        ] 
	," The method acls() returns correct object");

ok(($interface->node())->{'node_id'} eq '11', "The method node() returns the correct node");

cmp_deeply($interface->mpls_vlan_tag_range(), '1-10' 
		, "The method mpls_vlan_tag_range() returns the expected result");

### Test : used_vlans ###
cmp_deeply($interface->used_vlans(),
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

# Testing the Interface object
ok($interface->{'name'} eq "e15/1", "The object interface returns expected name");
ok($interface->{'interface_id'} eq '391', "The object interface has the correct interface_id");
ok($interface->{'node'}->{'node_id'} eq "11", "The object interface has the correct node");
ok($interface->{'description'} eq 'e15/1', "The object interface has correct description");
cmp_deeply($interface->{'acls'}->{'acls'},
[
          {
            'eval_position' => '10',
            'workgroup_id' => '11',
            'allow_deny' => 'deny',
            'entity_id' => '7',
            'end' => undef,
            'start' => 1
          },
          {
            'eval_position' => '20',
            'workgroup_id' => 11,
            'allow_deny' => 'allow',
            'entity_id' => '7',
            'end' => 4095,
            'start' => 1
          }
        ], "The object interface 391 has expect list of acls");

ok($interface->{'mpls_vlan_tag_range'} eq '1-10', "The tag range defined for interface 391 is correct");
my $flag = 0;
foreach my $i ( @{$interface->{'used_vlans'}}){
	if ($i == 391){
		$flag= 1;
	}
}
ok($flag == 1, "Vlan 391 is in use by the interface object");


$flag =1;
foreach my $i ( @{$interface->{'used_vlans'}}){
        if ($i == 444){
                $flag= 0;
        }
}
ok($flag == 1, "Vlan 444 is not in use by the interface object");
ok($interface->{'operational_state'} eq "up", "The operational state is up for the given interface");
ok($interface->{'cloud_interconnect_id'} eq 'Test', "Iterface object shows correct value for cloud_interconnect_id");
ok($interface->{'cloud_interconnect_type'} eq undef, "Cloud interconnect type has not neem defined for interface_id 391");
