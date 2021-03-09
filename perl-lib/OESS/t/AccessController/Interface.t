#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
my $path;

BEGIN {
    if ($FindBin::Bin =~ /(.*)/) {
        $path = $1;
    }
}
use lib "$path/..";


use Data::Dumper;
use Test::More tests => 42;

use OESS::AccessController::Base;
use OESS::AccessController::Default;
use OESS::AccessController::Grouper;


my $ctrls = [
    new OESS::AccessController::Base(),
    new OESS::AccessController::Default(),
    new OESS::AccessController::Grouper()
];

foreach my $ctrl (@$ctrls) {
    ok($ctrl->can("create_user"), "Method `create_user` is defined.");
    ok($ctrl->can("delete_user"), "Method `delete_user` is defined.");
    ok($ctrl->can("edit_user"), "Method `edit_user` is defined.");
    ok($ctrl->can("get_user"), "Method `get_user` is defined.");
    ok($ctrl->can("get_users"), "Method `get_users` is defined.");
    ok($ctrl->can("get_workgroup_users"), "Method `get_workgroup_users` is defined.");

    ok($ctrl->can("create_workgroup"), "Method `create_workgroup` is defined.");
    ok($ctrl->can("delete_workgroup"), "Method `delete_workgroup` is defined.");
    ok($ctrl->can("edit_workgroup"), "Method `edit_workgroup` is defined.");
    ok($ctrl->can("get_workgroup"), "Method `get_workgroup` is defined.");
    ok($ctrl->can("get_workgroups"), "Method `get_workgroups` is defined.");

    ok($ctrl->can("add_workgroup_user"), "Method `add_workgroup_user` is defined.");
    ok($ctrl->can("modify_workgroup_user"), "Method `modify_workgroup_user` is defined.");
    ok($ctrl->can("remove_workgroup_user"), "Method `remove_workgroup_user` is defined.");
}
