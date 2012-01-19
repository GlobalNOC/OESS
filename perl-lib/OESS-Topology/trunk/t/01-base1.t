use strict;
use Test::Simple tests=>7;
use Data::Dumper;
use OESS::Topology;
use OESS::Database;
use Set::Scalar;

my $config_filename="/etc/oess/db_testing.xml";

my $topology = OESS::Topology->new(config=>$config_filename);

ok(defined $topology, "No Error");

$OESS::Database::ENABLE_DEVEL=1;

ok($topology->get_database()->reset_database(), "resetting database");

ok($topology->get_database()->add_into(xml_dump => "t/test_topologies/dump1.xml"), "loading database");


my @nodes;
@nodes=('AAA','BBB');

my $bad_nodes_path = $topology->find_path(nodes=>\@nodes);

ok (not defined $bad_nodes_path);

##can calculate a path
@nodes=('Atlanta','Chicago');

my $primary_path = $topology->find_path(nodes=>\@nodes);

ok(defined($primary_path));


#can calculate backup path;
my $backup_path = $topology->find_path(nodes=>\@nodes,used_links=>$primary_path);
ok(defined($backup_path));


my $primary_path_set=Set::Scalar->new(@$primary_path);

my $backup_path_set=Set::Scalar->new(@$backup_path);

my $intersection_set=$primary_path_set * $backup_path_set;

ok($intersection_set->is_empty());



