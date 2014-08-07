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
    my $cwd = $FindBin::Bin;
    $cwd =~ /(.*)/;
    $cwd = $1;
    my $cfg                 = GRNOC::Config->new(config_file => "$cwd/conf/database.xml");
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

sub resetOESSDB {
    my $creds = &getConfig();
    #drop the oess-test DB if it exists, and then create it
    my %attr = (PrintError => 0, RaiseError => 0);
    my $dbh = DBI->connect("DBI:mysql:dbname=;host=localhost;port=6633",$creds->{'user'},$creds->{'pass'},\%attr);
    $dbh->do("create database " . $creds->{'db'});
    $dbh->do("set foreign_key_checks = 0");

   
    my $cwd = $FindBin::Bin;
    $cwd =~ /(.*)/;
    $cwd = $1;
    my $command = "/usr/bin/mysql -u $creds->{'user'} --password=$creds->{'pass'} $creds->{'db'} < $cwd/conf/oess_known_state.sql";
    if (system($command)){
        return 0;
    }

    $dbh->do("set foreign_key_checks = 1");
    return 1;
}


1;
