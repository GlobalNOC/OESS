#!/usr/bin/perl

#---------
# This is the main workhorse service for serving up all the template toolkit
# pages that serve the OE-SS frontend. There is nothing particularly special in here,
# it just accepts what page the user wants to see and returns it templatized.
#---------
##-----                                                                                  
##----- $HeadURL: svn+ssh://svn.grnoc.iu.edu/grnoc/oe-ss/frontend/trunk/www/index.cgi $
##----- $Id$
##----- $Date$
##----- $LastChangedBy$
##-----                                                                                
##----- Provides object oriented methods to interact with the DBus test
##
##-------------------------------------------------------------------------
##
##                                                                                       
## Copyright 2011 Trustees of Indiana University                                         
##                                                                                       
##   Licensed under the Apache License, Version 2.0 (the "License");                     
##   you may not use this file except in compliance with the License.                     
##   You may obtain a copy of the License at                                             
##                                                                                       
##       http://www.apache.org/licenses/LICENSE-2.0                                      
##                                                                                       
##   Unless required by applicable law or agreed to in writing, software                 
##   distributed under the License is distributed on an "AS IS" BASIS,                   
##   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.            
##   See the License for the specific language governing permissions and                 
##   limitations under the License.                                                      
#                                                 
use strict;
use warnings;
use OESS::Database;
use Data::Dumper;
use CGI;
use Template;
use Switch;
use FindBin;
use Log::Log4perl;

Log::Log4perl::init('/etc/oess/logging.conf');



sub main{
    my $db  = OESS::Database->new();
    my $cgi = new CGI;
    my $tt  = Template->new(INCLUDE_PATH => "$FindBin::Bin/..") || die $Template::ERROR;

    my $is_valid_user = $db->get_user_id_by_auth_name( auth_name => $ENV{'REMOTE_USER'});
    if(!defined($is_valid_user)){

        #-- What to pass to the TT and what http headers to send
        my ($vars, $output, $filename, $title, $breadcrumbs, $current_breadcrumb);
        $filename           = "html_templates/denied2.html";
        $title              = "Access Denied";
        $vars->{'admin_email'}        = $db->get_admin_email();

        $vars->{'page'}               = $filename;
        $vars->{'title'}              = $title;
        $vars->{'breadcrumbs'}        = $breadcrumbs;
        $vars->{'current_breadcrumb'} = $current_breadcrumb;
        $vars->{'is_admin'}           = 0;
	$vars->{'path'}               = "../";
        $vars->{'is_read_only'}       = 1;
        $vars->{'version'}            = OESS::Database::VERSION;

        $tt->process("html_templates/base.html", $vars, \$output) or warn $tt->error();
        print "Content-type: text/html\n\n" . $output;
        return;
    }

    my $is_admin = $db->get_user_admin_status(username=>$ENV{'REMOTE_USER'})->[0]{'is_admin'};
    if (!defined $is_admin) {
	$is_admin = 0;
    }
    my $is_read_only = 0;
    my $user = $db->get_user_by_id( user_id => $db->get_user_id_by_auth_name( auth_name => $ENV{'REMOTE_USER'}))->[0];
    if ($user->{'type'} eq 'read-only') {
	$is_read_only = 1;
    }

    #-- What to pass to the TT and what http headers to send
    my ($vars, $output, $filename, $title, $breadcrumbs, $current_breadcrumb);
    
    #-- Figure out what we're trying to templatize here or default to welcome page.
    my $action = "welcome";

    if ($cgi->param('action') =~ /^(\w+)$/){
	$action = $1;
    }

    if ($user->{'status'} eq 'decom') {
        $action = "decom";
    }
    
    switch ($action) {
        case "provision_l3vpn" {
            $title              = "New private network";
            $filename           = "html_templates/provision_l3vpn.html";
            $current_breadcrumb = "New private network";
            $breadcrumbs        = [
                {title => "Welcome",          url => "?action=welcome"},
                {title => "New private network", url => "#"}
            ];
        }
        case "view_l3vpn" {
            $title              = "Private network details";
            $filename           = "html_templates/view_l3vpn.html";
            $current_breadcrumb = "Private network details";
            $breadcrumbs        = [
                {title => "Welcome",              url => "?action=welcome"},
                {title => "Private network details", url => "#"}
            ];
        }
        case "modify_l2vpn" {
            $title              = "L2VPN - Details";
            $filename           = "html_templates/modify_l2vpn.html";
            $current_breadcrumb = "Modify L2VPN";
            $breadcrumbs        = [
                {title => "Welcome",       url => "?action=welcome"},
                {title => "L2VPN Details", url => "#"}
            ];
        }
        case "provision_l2vpn" {
            $title              = "L2VPN - Provision";
            $filename           = "html_templates/provision_l2vpn.html";
            $current_breadcrumb = "L2VPN Details";
            $breadcrumbs        = [
                {title => "Welcome",       url => "?action=welcome"},
                {title => "L2VPN Details", url => "#"}
            ];
        }
        case "provision_cloud" {
            $title              = "New cloud network";
            $filename           = "html_templates/provision_cloud.html";
            $current_breadcrumb = "New cloud network";
            $breadcrumbs        = [
                {title => "Welcome",        url => "?action=welcome"},
                {title => "New cloud network", url => "#"}
            ];
        }
        case "phonebook" {
            $title              = "Phonebook";
            $filename           = "html_templates/phonebook.html";
            $current_breadcrumb = "Phonebook";
            $breadcrumbs        = [
                {title => "Welcome", url => "?action=welcome"},
                {title => "Phonebook",  url => "#"}
            ];
        }
        case "welcome" {
            $title              = "Welcome";
            $filename           = "html_templates/welcome.html";
            $current_breadcrumb = "Welcome";
            $breadcrumbs        = [
                {title => "Welcome",    url => "#"}
            ];
        }
        case "modify_cloud" {
            $title              = "Update cloud network";
            $filename           = "html_templates/modify_cloud.html";
            $current_breadcrumb = "Update cloud network";
            $breadcrumbs        = [
                {title => "Welcome",          url => "?action=welcome"},
                {title => "Update cloud network", url => "#"}
            ];
        }
        case "acl" {
            $filename = "html_templates/acl.html";
            $title    = "Edit ACL";
        }
        case "decom" {
            $filename = "html_templates/denied.html";
            $title    = "Access Denied";
        }
        case "edit_entity" {
            $filename		= "html_templates/edit_entity.html";
            $current_breadcrumb = "Edit Entity";
            $title		= "Edit Entity";
            $breadcrumbs	= [
                {title	=> "Welcome",	url => "?action=welcome"},
                {title	=> "Edit Entity",	url	=> "#"}
            ];
        }
        case "add_entity" {
            $filename           = "html_templates/add_entity.html";
            $current_breadcrumb = "Add Entity";
            $title              = "Add Entity";
            $breadcrumbs        = [
                {title  => "Welcome",   url => "?action=welcome"},
                {title  => "Add Entity",       url     => "#"}
            ];
        } 
	else {
            $filename = "html_templates/error.html"; 
            $title    = "Error";
        }
    }

    $vars->{'g_port'}    = $db->{grafana}->{'oess-interface'};
    $vars->{'g_l2_port'} = $db->{grafana}->{'oess-l2-interface'};
    $vars->{'g_peer'}    = $db->{grafana}->{'oess-bgp-peer'};
    $vars->{'g_route'}   = $db->{grafana}->{'oess-routing-table'};

    $vars->{'admin_email'}        = $db->get_admin_email();
    $vars->{'page'}               = $filename;
    $vars->{'title'}              = $title;
    $vars->{'breadcrumbs'}        = $breadcrumbs;
    $vars->{'current_breadcrumb'} = $current_breadcrumb;
    $vars->{'path'}               = "../";
    $vars->{'is_admin'}           = $is_admin;
    $vars->{'is_read_only'}       = $is_read_only;
    $vars->{'version'}            = OESS::Database::VERSION;

    $tt->process("html_templates/base.html", $vars, \$output) or warn $tt->error();
    print "Content-type: text/html\n\n" . $output;
}

main();
