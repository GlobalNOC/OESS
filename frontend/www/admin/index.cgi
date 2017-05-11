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

my $ADMIN_BREADCRUMBS = [
    { title => "Workgroups", url => "../index.cgi?action=workgroups" },
    { title => "Admin",      url => "?action=admin" }
];

sub main {

    my $cgi = new CGI;
    my $db  = OESS::Database->new();
    my $tt  = Template->new( INCLUDE_PATH => "$FindBin::Bin/.." )
      || die $Template::ERROR;

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
    $tt->process( "html_templates/page_base.html", $vars, \$output )
      or warn $tt->error();

    print "Content-type: text/html\n\n" . $output;
}

main();
