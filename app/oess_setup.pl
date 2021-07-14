#!/usr/bin/perl

use strict;
use warnings;

use DBI;
use OESS::Database;
use Sys::Hostname;
use Data::Dumper;
use File::Path qw(make_path);
use CPAN;
sub main{

    system('clear');
    print "******************************\n";
    print "* OESS Software Setup Script *\n";
    print "******************************\n";

    print "NOTE: This should ONLY be run for a fresh install of OESS, if you have an\n";
    print "existing OESS install, please run the upgrade scripts in the upgrade\n";
    print "directory '" . OESS::Database::SHARE_DIR . "upgrade/'\n";
    print "\nPress control+c to exit out of the installation process at any time\n";
    print "\n\nMySQL should be running, and you should know the administrator password\n";
    print "before continuing on.";
    print "\n";
    continue_param("Do you wish to continue");

    eval {
	require SOAP::Data::Builder;
    };

    if( $@ ){
	CPAN::Shell->install("SOAP::Data::Builder");
    }

    require SOAP::Data::Builder;

    eval { require Term::ReadKey; };

    if( $@ ){
	CPAN::Shell->install("Term::ReadKey");
    }

    use Term::ReadKey;
    print "\n\n\n";
    print "#####################################";
    print "\n\n  Starting Configuration of OESS\n\n";
    print "#####################################\n";

    print "\n\nDatabase Configuration\n";
    print "----------------------\n";
    my $db_host = optional_parameter("Host","127.0.0.1");
    my $db_port = optional_parameter("Port",3306);
    my $db_user = optional_parameter("Admin user","root");
    my $db_name = "oess";
    my $db_pass;

    ReadMode('noecho');
    while(!($db_pass = required_parameter("Admin Password: "))){
	print "\nAdmin Password is required\n\n";
    }
    ReadMode('normal');
    print "\n";

    my $of_mpls_mode;
    my %allowed_modes = ('1' => 1, '2' => 1, '3' => 1);
    while(!($of_mpls_mode = required_parameter('Enable OpenFlow only (1), MPLS only (2), or both OpenFlow and MPLS (3)? '))
          or !$allowed_modes{$of_mpls_mode}) {
        print "Invalid value $of_mpls_mode entered - use 1, 2, or 3.\n";
    }

    my $network_types = { '1' => 'openflow', '2' => 'vpn-mpls', '3' => 'evpn-vxlan' };
    my $network_type;
    while (!($network_type = required_parameter('Network Stack: OpenFlow (1), VPN-MPLS (2), or EVPN-VXLAN (3)')) || !$network_types->{$network_type}) {
        print "Invalid network type '$network_type' selected. - Use 1, 2 or 3.\n";
    }
    $network_type = $network_types->{$network_type};

    my $use_mpls = 'enabled';
    my $use_openflow = 'enabled';

    if ($network_type eq 'openflow') {
        $use_mpls = 'disabled';
    }
    elsif ($network_type eq 'vpn-mpls') {
        $use_openflow = 'disabled';
    }
    elsif ($network_type eq 'evpn-vxlan') {
        $use_mpls = 'disabled';
        $use_openflow = 'disabled';
    }

    my $host = hostname;
    my $oscars_host = optional_parameter("Oscars Host URL","https://$host");
    my $my_cert = optional_parameter("OSCARS SSL Cert","mycert.crt");
    my $my_key = optional_parameter("OSCARS SSL Key","mykey.key");
    my $topo_host = optional_parameter("TopoHost","http://ndb7.net.internet2.edu:8012/perfSONAR_PS/services/topology");
    my $from_address = optional_parameter("Notification originating email address","OESS\@localhost");
    my $image_base_url = optional_parameter("Base URL used to host images for html notifications", "https://$host/oess/notification-img/");
    my $base_url = optional_parameter("Base URL of OESS application", "https://$host/oess/");
    my $from_name = optional_parameter("Email From Name (used in signature)", "OESS Circuit Notifier");

    print "\nTesting DB connection\n";
    my $handle = DBI->connect("DBI:mysql:dbname=mysql;host=$db_host;port=$db_port",
			      $db_user,
			      $db_pass,{PrintError => 0});

    if(!$handle){
	print "Failed!\n\n";
	print "Unable to connect to the DB: " . $DBI::errstr . "\n";
	exit(1);
    }else{
	print "DB Connection appears to work!\n";
    }

    continue_param("Do you want to create the database $db_name and install the OESS schema there?");
    print "The Follwing password requests are for the new mysql oess user that will be created\n";

    my ($oess_pass, $oess_confirm);
    ReadMode('noecho');
    while (1){
	$oess_pass    = required_parameter("OESS Password: ");
	print "\n";
	$oess_confirm = required_parameter("Confirm OESS Password: ");
	print "\n";

	last if ($oess_pass eq $oess_confirm);
	print "Passwords did not match, try again.\n";
    }
    print "\n";

    ReadMode('normal');
    print "\n";

    print "\nCreating new user\n";

    $handle->do('create database oess');
    $handle->do("GRANT ALL ON oess.* to 'oess'\@'localhost' identified by '$oess_pass'") or die DBI::errstr;
    $handle->do("flush privileges");
	
    my $discovery_vlan = optional_parameter("Discovery VLAN Tag: ","untagged");
    my $tsds_url = required_parameter("TSDS Service URL: ");
    my $tsds_username = required_parameter("TSDS Username: ");
    ReadMode('noecho');
    my $tsds_password = required_parameter("TSDS Password: ");
    ReadMode('normal');
    my $grafana_url = optional_parameter("Grafana URL", "https://localhost/grafana");
    my $third_party_management = yes_or_no_parameter("Are you using third party User/Workgroup management? ");
    #put all of this into a config file
    print "Creating Configuration file (/etc/oess/database.xml)\n";
    open(FILE, "> /etc/oess/database.xml");

    print FILE << "END";
<config host="$db_host" port="$db_port" base_url="$base_url"
        openflow="$use_openflow" mpls="$use_mpls" network_type="$network_type">
  <tsds url="$tsds_url" username="$tsds_username" password="$tsds_password" />
  <grafana host="$grafana_url">
    <graph panelName="oess-interface"     uid="aaaaaaaaa" orgId="1" panelId="1"/>
    <graph panelName="oess-bgp-peer"      uid="aaaaaaaaa" orgId="1" panelId="1"/>
    <graph panelName="oess-routing-table" uid="aaaaaaaaa" orgId="1" panelId="1"/>
  </grafana>
  <credentials username="oess" password="$oess_pass" database="oess" />
  <oscars host="$oscars_host" cert="$my_cert" key="$my_key" topo="$topo_host"/>
  <smtp from_address="$from_address" image_base_url="$image_base_url" from_name="$from_name" />
END
    print FILE "  <discovery_vlan>$discovery_vlan</discovery_vlan>\n" if($discovery_vlan ne 'untagged');
    print FILE "  <process name='fwdctl' status='$use_openflow' />\n";
    print FILE "  <process name='mpls_fwdctl' status='$use_mpls' />\n";
    print FILE "  <process name='mpls_discovery' status='$use_mpls' />\n";
    print FILE "  <process name='fvd' status='disabled' />\n";
    print FILE "  <process name='watchdog' status='disabled' />\n";
    print FILE "  <rabbitMQ user='guest' pass='guest' host='localhost' port='5672' vhost='/' />\n";
    print FILE "  <third_party_management>$third_party_management</third_party_management>";
    print FILE "</config>\n";
    close(FILE);


    if ($use_mpls eq 'enabled') {
        my $make_passwd = yes_or_no_parameter('Set up credentials for OESS to log into switches (needed for MPLS)?');
        if ($make_passwd eq 'y') {
            my $mpls_user = required_parameter('Default username for switches: ');

            my ($mpls_pass, $mpls_confirm);
            ReadMode('noecho');
            while (1) {
                $mpls_pass    = required_parameter('Password for switches: ');
                print "\n";
                $mpls_confirm = required_parameter('Confirm password for switches: ');
                print "\n";

                last if ($mpls_pass eq $mpls_confirm);
                print "Passwords did not match - try again.\n";
            }
            ReadMode('normal');
            print "\n";

            $mpls_user = xml_escape($mpls_user);
            $mpls_pass = xml_escape($mpls_pass);

            print "Creating switch credentials file (/etc/oess/.passwd.xml)\n";
            open(FILE, '> /etc/oess/.passwd.xml');
            print FILE << "END";
<config default_user='$mpls_user' default_pw='$mpls_pass'>
</config>
END
            close(FILE);
        }
    }


    print "\nInstalling the OESS Schema\n";
    my $db = OESS::Database->new();
    $OESS::Database::ENABLE_DEVEL=1;
    $db->reset_database();

    print "DONE!\n\n";
    print "Re-connecting to mysql using the new database ($db_name)... ";

    $handle = DBI->connect("DBI:mysql:dbname=$db_name;host=$db_host;port=$db_port",
                       $db_user,
                       $db_pass,
                       {PrintError => 0});

    if (!$handle) {
	print "FAILED!\n\n";
	print "Unable to connect to the database: " . $DBI::errstr . "\n";
	exit(1);
    }else {
	print "OK!\n\n";
    }


    #create local domain
    my $domain_name = required_parameter("What is your local domain (Fully Qualified)");

    my $sth = $handle->prepare("insert into network (name,longitude,latitude,is_local) VALUES (?,?,?,?)") or die "Unable to add Network";
    $sth->execute($domain_name,0,0,1) or die "Unable to add Network";

    #add an admin workgroup
    print "We will now be creating an OE-SS Workgroup\n";
    my $admin_workgroup = optional_parameter("Admin Workgroup Name","admin");
    my $workgroup_id = $db->add_workgroup( name => $admin_workgroup,
					   type => 'admin');

    #create a user
    #if (yes_or_no_parameter("OESS Frontend requires a user, would you like to add a user via htpasswd file?") eq "y"){

    my $user = required_parameter("UserName");
    my $first = required_parameter("First Name");
    my $last = required_parameter("Last Name");
    my $email = required_parameter("Email Address");

    my ($pass, $confirm);
    if (yes_or_no_parameter("OESS Frontend requires a user, would you like to add a user via htpasswd file?  If using a different authentication mechanism choose n") eq "y"){
	while (1){
        ReadMode('noecho');
	    $pass    = required_parameter("Password");
	    print "\n";
	    $confirm = required_parameter("Confirm Password");
	    print "\n";

	    if ($pass eq $confirm){

            ReadMode('normal');
            last;
        }   
	    print "Passwords did not match, try again.\n";
	}
    make_path('/usr/share/oess-frontend/www/', { mode => 0755 });
	open(my $fh, "> /usr/share/oess-frontend/www/.htpasswd");
	print $fh $user . ":" . crypt($pass,$pass) . "\n";
    chmod(0755, $fh);
	close($fh);
    }

    #now add the user to the DB
    my $user_id = $db->add_user( given_name => $first,
				 family_name => $last,
				 email_address => $email,
				 auth_names => [$user],
                 type => 'normal');

    #add the user to the admin workgroup
    $db->add_user_to_workgroup( user_id => $user_id,
				workgroup_id => $workgroup_id);

    if (yes_or_no_parameter("Would you like to start the OESS services?") eq "y"){
	`/etc/init.d/oess start`;
    }

    print "Done!\n";
}

sub required_parameter {

    my $name = shift;

    while (1) {

	print "$name (required): ";
	my $response = <>;
	chomp($response);

	return $response if ($response);

	print "\nThis option is required!\n\n";
    }
}


sub yes_or_no_parameter {

    my $name = shift;

    print "$name [y/n]: ";
    my $yes_or_no = <>;
    chomp($yes_or_no);

    if ($yes_or_no =~ /y/i && $yes_or_no !~ /n/i) {

	$yes_or_no = "y";
    }

    else {

	$yes_or_no = "n";
    }

    return $yes_or_no;
}

sub continue_param{
    my $name = shift;
    print "$name [y/n]: ";
    my $yes_or_no = <>;
    chomp($yes_or_no);

    exit(0) if ($yes_or_no !~ /y/i || $yes_or_no =~ /n/i);
}

sub optional_parameter {

    my ($name, $default) = @_;

    print $name;

    if (defined($default)) {

	print " [default $default]: ";
    }

    else {

	print ": ";
    }

    my $response = <>;
    chomp($response);

    $response = $default if (defined($default) && !$response);

    return $response;
}

sub xml_escape {
    my $str = shift;

    $str =~ s/&/&amp;/g;
    $str =~ s/"/&quot;/g;
    $str =~ s/'/&apos;/g;

    return $str;
}


main();
