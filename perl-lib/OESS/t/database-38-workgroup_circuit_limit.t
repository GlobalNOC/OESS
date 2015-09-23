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
use OESSDatabaseTester;

use Test::More tests => 2;
use Test::Deep;
use OESS::Database;
use OESSDatabaseTester;
use Data::Dumper;

my $db = OESS::Database->new(config => OESSDatabaseTester::getConfigFilePath());

# Add two additional circuits to max out workgroup.

$db->provision_circuit(
    'description' => "Test",
    'bandwidth' => 1337,
    'provision_time' => 1377716981,
    'remove_time' => 1380308981,
    'links' => ['Link 181', 'Link 191', 'Link 531'],
    'backup_links' => [],
    'nodes' => ['Node 11', 'Node 51'], 
    'interfaces' => ['e1/1', 'e15/1'],
    'tags' => [7,7],
    'user_name' => 'aragusa',
    'workgroup_id' => 11,
    'external_id' => undef
);

$db->provision_circuit(
    'description' => "Test",
    'bandwidth' => 1337,
    'provision_time' => 1377716981,
    'remove_time' => 1380308981,
    'links' => ['Link 181', 'Link 191', 'Link 531'],
    'backup_links' => [],
    'nodes' => ['Node 11', 'Node 51'], 
    'interfaces' => ['e1/1', 'e15/1'],
    'tags' => [7,7],
    'user_name' => 'aragusa',
    'workgroup_id' => 11,
    'external_id' => undef
);


#my $res;
# try provisioning a circuit when acl rules block you 
my $res = $db->provision_circuit(
    'description' => "Test",
    'bandwidth' => 1337,
    'provision_time' => 1377716981,
    'remove_time' => 1380308981,
    'links' => ['Link 181', 'Link 191', 'Link 531'],
    'backup_links' => [],
    'nodes' => ['Node 11', 'Node 51'], 
    'interfaces' => ['e15/1', 'e15/1'],
    'tags' => [2,9],
    'user_name' => 'aragusa',
    'workgroup_id' => 11,
    'external_id' => undef
);

warn Dumper($res);

ok(!$res, 'authorization check');
is($db->get_error(),'Permission denied: workgroup is already at circuit limit.','correct error');
