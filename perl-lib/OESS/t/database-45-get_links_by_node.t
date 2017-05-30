#!/usr/bin/perl -T

use strict;

use FindBin;
my $path;

BEGIN {
    if($FindBin::Bin =~ /(.*)/){
            $path = $1;
      }
}

use lib "$path";
use OESS::Database;
use OESS::Circuit;
use OESSDatabaseTester;

use Test::More tests => 10;
use Data::Dumper;

my $db = OESS::Database->new( config => OESSDatabaseTester::getConfigFilePath() );

# We use link id=31 for these tests. To start out, it has current endpoint interfaces
# 11 (= node_id 11 intf e1/2) and 311 (= node_id 1 intf e1/1)

foreach my $test ([11,1],[1,1],[41,0],[51,0]) {
    my $res = $db->get_links_by_node(node_id => $test->[0]);
    my $x = ($test->[1]) ? 'is' : 'is not';
    ok(length_of_match(sub { $_->{'link_id'} == 31 }, $res) == $test->[1], "original: link 31 $x connected to node $test->[0]");
}

# Now, we change the link to have endpoint interfaces
# 471 (= node_id 41 intf e15/2) and 511 (= node_id 51 intf e15/1)

my $epoch = 1400000000;

my $res1 = $db->_execute_query("update link_instantiation set end_epoch=$epoch where link_id=31 and end_epoch=-1");
my $res2 = $db->_execute_query("insert into link_instantiation (link_id,start_epoch,end_epoch,link_state,interface_a_id,interface_z_id) values (31,$epoch,-1,'active',471,511)");
ok(defined($res1) && defined($res2), 'successfully updated link endpoints');


foreach my $test ([11,0],[1,0],[41,1],[51,1]) {
    my $res = $db->get_links_by_node(node_id => $test->[0]);
    my $x = ($test->[1]) ? 'is' : 'is not';
    ok(length_of_match(sub { $_->{'link_id'} == 31 }, $res) == $test->[1], "modified: link 31 $x connected to node $test->[0]");
}

ok(&OESSDatabaseTester::resetOESSDB(), "Resetting OESS Database");

sub length_of_match {
    my $predicate = shift;
    my $array = shift;

    my @res = grep &$predicate, @$array;
    return scalar(@res);
}
