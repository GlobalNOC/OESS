use strict;
use warnings;

use Data::Dumper;
use JSON;

my $modules = [
    { name => "circuit",           source => "./frontend/webservice/circuit.cgi" },
    { name => "vrf",               source => "./frontend/webservice/vrf.cgi" },
    { name => "admin-admin",       source => "./frontend/webservice/admin/admin.cgi" },
    { name => "admin-maintenance", source => "./frontend/webservice/admin/maintenance.cgi" },
    { name => "command",           source => "./frontend/webservice/command.cgi" },
    { name => "configuration",     source => "./frontend/webservice/configuration.cgi" },
    { name => "data",              source => "./frontend/webservice/data.cgi" },
    { name => "entity",            source => "./frontend/webservice/entity.cgi" },
    { name => "interface",         source => "./frontend/webservice/interface.cgi" },
    { name => "measurement",       source => "./frontend/webservice/measurement.cgi" },
    { name => "monitoring",        source => "./frontend/webservice/monitoring.cgi" },
    { name => "traceroute",        source => "./frontend/webservice/traceroute.cgi" },
    { name => "user",              source => "./frontend/webservice/user.cgi" },
    { name => "workgroup_manage",  source => "./frontend/webservice/workgroup_manage.cgi" }
];

$ENV{REMOTE_USER} = 'admin';

foreach my $module (@$modules) {
    my $help = `perl $module->{source} "method=help"`;
    if ($help !~ m/(\{.*\})|(\[.*\])/gm) {
        next;
    }

    my $methods;
    eval {
        $methods = decode_json($2);
    };
    if ($@) {
        warn "Error while decoding $module->{name}: $@";
        next;
    }

    my $title = $module->{source};
    $title =~ s/\.\.\/frontend\/webservice//g;

    my $filename = "./docs/_api_endpoints/$module->{name}.md";
    if (! -e $filename) {
        print "Creating initial page for $module->{name}.\n";

        open(FH1, ">docs/_api_endpoints/$module->{name}.md");
        print FH1 "---\n";
        print FH1 "name: $module->{name}\n";
        print FH1 "title: $title\n";
        print FH1 "layout: cgi\n";
        print FH1 "---\n";
        print FH1 "This is some documentation.\n";
        print FH1 "\n";
    }

    # Make directory in case it doesn't already exist.
    `mkdir -p docs/_data/api/$module->{name}/`;

    print "Loading method data for $module->{source}\n";
    foreach my $method (@$methods) {
        next if ($method eq 'help');

        my $method_help = `perl $module->{source} "method=help&method_name=$method"`;
        if ($method_help !~ m/(\{.*\})|(\[.*\])/gm) {
            next;
        }

        print "Saving method data from $method\n";
        open(FH, ">docs/_data/api/$module->{name}/$method.json");
        print FH $1;
    }
}
