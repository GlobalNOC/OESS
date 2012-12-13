#!/usr/bin/perl

use strict;
use warnings;

use DBI;
use XML::Simple;

sub reload{
   my ($username,$password,$database) = @_;

print "Resetting database...\n";
`/usr/bin/mysql -u root -p$password $database < nddi.sql`;
print "Done!\n";

my $dbh = DBI->connect("DBI:mysql:$database", 'root', $password) or die "Can't cannot to db: $DBI::errstr";

print "Creating workgroup...\n";
$dbh->do("insert into workgroup (name, description) values ('Test Workgroup', 'Dans Super Sweet Test Workgroup')");

print "Creating user...\n";
$dbh->do("insert into user (email, given_names, family_name, is_admin) values ('daldoyle\@grnoc.iu.edu', 'Dan', 'Doyle', 1)");

print "Creating workgroup/user membership...\n";
$dbh->do("insert into user_workgroup_membership (workgroup_id, user_id) values (1, 1) ");

print "Creating network...\n";
$dbh->do("insert into network (name, longitude, latitude) values ('FooNet', -85, 40)");

print "Creating nodes...\n";
my %nodes= ( 
	'Atlanta' => 		{ longitude =>  -84.38759, latitude  => 33.758537, },
        'Los Angeles' =>	{ longitude =>  -118.2950, latitude  => 33.737916, },
        'Chicago' => 		{ longitude =>  -87.64306, latitude  => 41.896504, },
	'New York' =>		{ longitude =>  -74.00519, latitude  => 40.720069, },
	);

my @nodes_order = ("Atlanta", "Los Angeles", "Chicago", "New York");

my $i=1;

foreach my $node_name (@nodes_order) {
   #print $node_name;
   my $longitude=$nodes{$node_name}{'longitude'};
   my $latitude=$nodes{$node_name}{'latitude'};
   my $ip_addr=655360+$i;  
   $dbh->do("insert into node (node_id, name, longitude, latitude, network_id) values ($i, '$node_name', $longitude, $latitude, 1)");
   $dbh->do("insert into node_instantiation(node_id,end_epoch,start_epoch,management_addr_ipv4,dpid) VALUES ($i,-1,unix_timestamp(now()),$ip_addr,$ip_addr)");   

   $i++;
}

=pod
$dbh->do("insert into node (node_id, name, longitude, latitude, network_id) values (1, 'Atlanta', -84.38759, 33.758537, 1)");
$dbh->do("insert into node (node_id, name, longitude, latitude, network_id) values (2, 'Los Angelos', -118.295056, 33.737916, 1)");
$dbh->do("insert into node (node_id, name, longitude, latitude, network_id) values (3, 'Chicago', -87.64306, 41.896504, 1)");
$dbh->do("insert into node (node_id, name, longitude, latitude, network_id) values (4, 'New York', -74.005199, 40.720069, 1)");
=cut

print "Creating interfaces...\n";
my $int_id = 1;

for ( $i = 1; $i < 5; $i++){ 
    $dbh->do("insert into interface (name, description, node_id) values ('interface $int_id', 'description for interface $int_id', $i)");
    $dbh->do("insert into interface_instantiation (interface_id, end_epoch, start_epoch, capacity_mbps,mtu_bytes) values ($int_id, -1, unix_timestamp(NOW()), 10000,9000)");
    $int_id++;
    $dbh->do("insert into interface (name, description, node_id) values ('interface $int_id', 'description for interface $int_id', $i)");
    $dbh->do("insert into interface_instantiation (interface_id, end_epoch, start_epoch, capacity_mbps,mtu_bytes) values ($int_id, -1, unix_timestamp(NOW()), 10000,9000)");
    $int_id++;
}

print "Creating links...\n";
$dbh->do("insert into link (name) values ('Atla<=>Losa')");
$dbh->do("insert into link_instantiation (link_id, end_epoch, link_state, start_epoch,interface_a_id,interface_b_id) values (1, -1, 'active', NOW(),2,3)");

$dbh->do("insert into link (name) values ('Losa<=>Chic')");
$dbh->do("insert into link_instantiation (link_id, end_epoch, link_state, start_epoch,interface_a_id,interface_b_id) values (2, -1, 'active', NOW(),4,5)");

$dbh->do("insert into link (name) values ('Chic<=>Newy')");
$dbh->do("insert into link_instantiation (link_id, end_epoch, link_state, start_epoch,interface_a_id,interface_b_id) values (3, -1, 'active', NOW(),6,7)");

$dbh->do("insert into link (name) values ('Newy<=>Atla')");
$dbh->do("insert into link_instantiation (link_id, end_epoch, link_state, start_epoch,interface_a_id,interface_b_id) values (4, -1, 'active', NOW(),8,1)");

$dbh->disconnect();

print "Done!\n";

}

sub main{

    my $config = XML::Simple::XMLin("/etc/oess/database.xml");

    my $username = $config->{'credentials'}->{'username'};
    my $password = $config->{'credentials'}->{'password'};
    my $database = $config->{'credentials'}->{'database'};



   reload($username,$password, $database);
}

main();

