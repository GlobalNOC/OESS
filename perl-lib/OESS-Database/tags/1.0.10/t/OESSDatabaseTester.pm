package OESSDatabaseTester;

use strict;
use FindBin;
use GRNOC::Config;
use Data::Dumper;
use DBI;

$ENV{"PATH"} = "";

sub getConfigFilePath{
    my $cwd = $FindBin::Bin;
    $cwd =~ /(.*)/;
    $cwd = $1;
    return "$cwd/conf/database.xml";
}

sub getConfig{

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

sub resetOESSDB{
    my $creds = &getConfig();

    #drop the snapp DB if it exists, and then create it
    my %attr = (PrintError => 0, RaiseError => 0);
    my $dbh = DBI->connect("DBI:mysql:dbname=;host=localhost;port=6633",$creds->{'user'},$creds->{'pass'},\%attr);
    
    $dbh->do("create database " . $creds->{'db'});
    $dbh->do("set foreign_key_checks = 0");
    #reset the SNAPP DB this one does the schema
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
