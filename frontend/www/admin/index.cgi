#!/usr/bin/perl

#---------
# This is the main workhorse service for all the admin template toolkit
# pages that serve the OE-SS frontend. There is nothing particularly special in here,
# it just accepts what page the user wants to see and returns it templatized.
#---------

use strict;
use warnings;

use CGI;
use Template;
use Switch;
use FindBin;
use OESS::Database();
use OESS::Config;
use Log::Log4perl;

Log::Log4perl::init('/etc/oess/logging.conf');

my $config = new OESS::Config();

my $ADMIN_BREADCRUMBS = [
    { title => "Workgroups", url => "../index.cgi?action=workgroups" },
    { title => "Admin",      url => "?action=admin" }
];

sub main {

    my $cgi = new CGI;
    my $db  = OESS::Database->new();
    my $tt  = Template->new( INCLUDE_PATH => "$FindBin::Bin/.." )
      || die $Template::ERROR;

    my $is_valid_user = $db->get_user_id_by_auth_name( auth_name => $ENV{'REMOTE_USER'});
    if(!defined($is_valid_user)){

        #-- What to pass to the TT and what http headers to send
        my ($vars, $output, $filename, $title, $breadcrumbs, $current_breadcrumb);
	$filename           = "html_templates/denied.html";
	$title              = "Access Denied";
        $vars->{'admin_email'}        = $db->get_admin_email();

        $vars->{'page'}               = $filename;
        $vars->{'title'}              = $title;
        $vars->{'breadcrumbs'}        = $breadcrumbs;
        $vars->{'current_breadcrumb'} = $current_breadcrumb;
        $vars->{'is_admin'}           = 0;
        $vars->{'is_read_only'}       = 1;
        $vars->{'version'}            = OESS::Database::VERSION;
        $vars->{'third_party_mgmt'}   = $config->third_party_mgmt;

        $tt->process("html_templates/page_base.html", $vars, \$output) or warn $tt->error();
        print "Content-type: text/html\n\n" . $output;
        return;
    }

    my $is_admin =
      $db->get_user_admin_status( 'username' => $ENV{'REMOTE_USER'} )
      ->[0]{'is_admin'};

    #-- What to pass to the TT and what http headers to send
    my ( $vars, $output, $filename, $title, $breadcrumbs, $current_breadcrumb );

    #-- Figure out what we're trying to templatize here or default to workgroups page.
    my $action = "admin";
    my $user = $db->get_user_by_id( user_id => $db->get_user_id_by_auth_name( auth_name => $ENV{'REMOTE_USER'}))->[0]; 
    if($user->{'status'} eq 'decom'){
        $action = 'denied';
    }
    if ( $cgi->param('action') && $cgi->param('action') =~ /^(\w+)$/ ) {
        $action = $1;
    }

    if ( !$is_admin ) {
        $action = 'denied';
    }

    switch ($action) {

        case "admin" {
            $filename           = "html_templates/admin.html";
            $title              = "Administration";
            $breadcrumbs        = $ADMIN_BREADCRUMBS;
            $current_breadcrumb = "Admin";
        }
        case "denied" {
            $filename           = "html_templates/denied.html";
            $title              = "Access Denied";
            $breadcrumbs        = $ADMIN_BREADCRUMBS;
            $current_breadcrumb = "Admin";
        }
        else {
            $filename = "html_templates/error.html";
            $title    = "Error";
        }

    }

    $vars->{'page'}               = $filename;
    $vars->{'title'}              = $title;
    $vars->{'breadcrumbs'}        = $breadcrumbs;
    $vars->{'current_breadcrumb'} = $current_breadcrumb;
    $vars->{'path'}               = "../";
    $vars->{'admin_email'}        = $db->get_admin_email();
    $vars->{'third_party_mgmt'}   = $config->third_party_mgmt;
    $tt->process( "html_templates/page_base.html", $vars, \$output )
      or warn $tt->error();

    print "Content-type: text/html\n\n" . $output;
}

main();
