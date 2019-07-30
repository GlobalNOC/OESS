package OESSDatabaseTester;

use strict;
use FindBin;
use GRNOC::Config;
use Data::Dumper;
use DBI;

$ENV{"PATH"} = "";

sub getConfigFilePath {
    my $cwd = $FindBin::Bin;
    $cwd =~ /(.*)/;
    $cwd = $1;
    my $line;
    my $database_config = "$cwd/conf/database.xml";
   
    return $database_config;
}

sub getConfig {
    my $args = {
        config => undef,
        @_
    };

    if (!defined $args->{config}) {
        my $cwd = $FindBin::Bin;
        $cwd =~ /(.*)/;
        $cwd = $1;
        $args->{config} = "$cwd/conf/database.xml";
    }

    my $cfg                 = GRNOC::Config->new(config_file => $args->{config});
    my $user                = $cfg->get('/config/credentials[1]/@username')->[0];
    my $pass                = $cfg->get('/config/credentials[1]/@password')->[0];
    my $db                  = $cfg->get('/config/credentials[1]/@database')->[0];
    my $result = {"user"   => $user,
                  "pass"   => $pass,
                  "db"     => $db
    };

    return $result;
}

sub resetSNAPPDB {

    my $creds = &getConfig();
    #drop the snapp-test DB if it exists, and then create it.
    my %attr = (PrintError => 0, RaiseError => 0);
    my $dbh = DBI->connect("DBI:mysql:dbname=;host=localhost;port=6633",$creds->{'user'},$creds->{'pass'},\%attr);
    $dbh->do("create database " . 'snapp_test' );
    $dbh->do("set foreign_key_checks = 0");
    
    my $cwd = $FindBin::Bin;
    $cwd =~ /(.*)/;
    $cwd = $1;
    my $command = "/usr/bin/mysql -u $creds->{'user'} --password=$creds->{'pass'} snapp_test < $cwd/conf/snapp_known_state.sql";
    if (system($command)){
        return 0;
    }

    #this goes and sets up the snapp directory for the tests

    $dbh->do("use snapp_test");
    $dbh->do("UPDATE global SET value='$cwd/conf/SNMP/snapp/db/' WHERE name = 'rrddir'");

    my $sth = $dbh->prepare("UPDATE global SET value ='$cwd/conf/SNMP/snapp/db/' WHERE name = 'rrddir'");
    $sth->execute();
    $sth = $dbh->prepare('SELECT value FROM global');
    $sth->execute();
    my $result = $sth->fetchrow_hashref();
   
    $dbh->do("set foreign_key_checks = 1"); 

    return 1;
}

sub load_database {
    my $config_file = shift;
    my $dump_file = shift;

    my $config = GRNOC::Config->new(config_file => $config_file);
    my $user = $config->get('/config/credentials[1]/@username')->[0];
    my $pass = $config->get('/config/credentials[1]/@password')->[0];
    my $db = $config->get('/config/credentials[1]/@database')->[0];

    my $dbh = DBI->connect(
        "DBI:mysql:dbname=;host=localhost;port=6633",
        $user,
        $pass,
        { PrintError => 0, RaiseError => 0 }
    );
    $dbh->do("create database $db");
    $dbh->do("set foreign_key_checks = 0");

    my $command = "/usr/bin/mysql -u $user --password=$pass $db < $dump_file";
    if (system $command) {
        return 0;
    }

    $dbh->do("set foreign_key_checks = 1");
    return 1;
}

sub resetOESSDB {
    my $args = {
        config => undef,
        dbdump => undef,
        @_
    };

    my $creds = &getConfig(config => $args->{config});

    my %attr = (PrintError => 0, RaiseError => 0);
    my $dbh = DBI->connect("DBI:mysql:dbname=;host=localhost;port=6633",$creds->{'user'},$creds->{'pass'},\%attr);

    # Drop the oess-test DB if it exists and then create it.
    $dbh->do("drop database $creds->{db} if exists");
    $dbh->do("create database $creds->{db}");
    $dbh->do("set foreign_key_checks = 0");

    if (!defined $args->{dbdump}) {
        my $cwd = $FindBin::Bin;
        $cwd =~ /(.*)/;
        $cwd = $1;
        $args->{dbdump} = "$cwd/conf/oess_known_state.sql";
    }

    my $command = "/usr/bin/mysql -u $creds->{'user'} --password=$creds->{'pass'} $creds->{'db'} < $args->{dbdump}";
    if (system($command)){
        return 0;
    }

    $dbh->do("set foreign_key_checks = 1");
    return 1;
}

# convenience method for bumping/saging those pesky workgroup limits
sub workgroupLimits {
    my %args = @_;
    my $workgroup_id = $args{'workgroup_id'};
    my $db           = $args{'db'};
    my $circuit_num  = $args{'circuit_num'};
    my $op           = $args{'op'} || '+';

    # get workgroup
    my $workgroup = $db->_execute_query(
        'SELECT * from workgroup where workgroup_id = ?', 
        [$workgroup_id]
    )->[0];

    # +/-= any defined limit variables
    my $mac_addr_per_end = (defined($args{'mac_addr_endpoint_num'}))
        ? eval($workgroup->{'max_mac_address_per_end'}." $op ".$args{'mac_addr_endpoint_num'})
        : $workgroup->{'max_mac_address_per_end'};

    my $max_ckts = (defined($args{'circuit_num'}))
        ? eval($workgroup->{'max_circuits'}." $op ".$args{'circuit_num'})
        : $workgroup->{'max_circuits'};
        
    my $max_ckt_endpoints = (defined($args{'circuit_endpoints_num'}))
        ? eval($workgroup->{'max_circuit_endpoints'}." $op ".$args{'circuit_endpoints_num'})
        : $workgroup->{'max_circuit_endpoints'};

    # update that stuff
    my $res = $db->update_workgroup(
        workgroup_id             => $workgroup->{'workgroup_id'},
        name                     => $workgroup->{'name'},
        external_id              => $workgroup->{'external_id'},
        max_mac_address_per_end  => $mac_addr_per_end,
        max_circuits             => $max_ckts,
        max_circuit_endpoints    => $max_ckt_endpoints 
    );

    warn Dumper($res);
}

sub flows_match {
    my %args = @_;
    my $actual_flows   = $args{'actual_flows'};
    my $expected_flows = $args{'expected_flows'};
    my $failed_flow_compare = 0;
    foreach my $actual_flow (@$actual_flows){
        my $found = 0;
        for(my $i=0;$i < scalar(@$expected_flows); $i++){

            if($expected_flows->[$i]->compare_flow( flow_rule => $actual_flow)) {
                $found = 1;
                splice(@$expected_flows, $i,1);
                last;
            }
        }
        if(!$found){
            warn "Didn't find actual_flow:   ".$actual_flow->to_human();
            $failed_flow_compare = 1;
            #last;
        }
    }

    foreach my $expected_flow (@$expected_flows){
        $failed_flow_compare = 1;
        warn "Didn't find expected_flow: " . $expected_flow->to_human();
    }
    return !$failed_flow_compare;
} 


1;
