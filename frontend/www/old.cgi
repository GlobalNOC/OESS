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
use OESS::Config;
use OESS::Database;
use Data::Dumper;
use CGI;
use Template;
use Switch;
use FindBin;
use Log::Log4perl;

Log::Log4perl::init('/etc/oess/logging.conf');

my $config = new OESS::Config();
my $db= OESS::Database->new();


my $ADD_BREADCRUMBS = [{title => "Workgroups",   url => "?action=workgroups"},
                       {title => "Home",         url => "?action=index"},
		       {title => "Endpoints",    url => "?action=endpoints"},
                       {title => "Options",      url => "?action=options"},
		       {title => "Primary Path", url => "?action=primary_path"},
		       {title => "Backup Path",  url => "?action=backup_path"},
		       {title => "Scheduling",   url => "?action=scheduling"},
		       {title => "Provisioning", url => "?action=provisioning"},
		       ];

my $REMOVE_BREADCRUMBS = [{title => "Workgroups",   url => "?action=workgroups"},
                          {title => "Home",         url => "?action=index"},
			  {title => "Scheduling",   url => "?action=remove_scheduling"},
			  {title => "Provisioning", url => "?action=remove_provisioning"},
			  ];

my $HOME_BREADCRUMBS = [{title => "Workgroups",   url => "?action=workgroups"},
			{title => "Home",         url => "?action=index"}
			];

my $DETAILS_BREADCRUMBS = [{title => "Workgroups",      url => "?action=workgroups"},,
			   {title => "Home",            url => "?action=index"},
			   {title => "Circuit Details", url => "?action=view_details"},
                          ];


sub main{

    my $cgi = new CGI;

    my $tt  = Template->new(INCLUDE_PATH => "$FindBin::Bin") || die $Template::ERROR;

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

	$tt->process("html_templates/page_base.html", $vars, \$output) or warn $tt->error();
	print "Content-type: text/html\n\n" . $output;
	return;
    }
    
    my $is_admin = $db->get_user_admin_status(username=>$ENV{'REMOTE_USER'})->[0]{'is_admin'};
    if(!defined($is_admin)){
	$is_admin = 0;
    }
    my $is_read_only =0;
    my $user = $db->get_user_by_id( user_id => $db->get_user_id_by_auth_name( auth_name => $ENV{'REMOTE_USER'}))->[0];
    
    #-- What to pass to the TT and what http headers to send
    my ($vars, $output, $filename, $title, $breadcrumbs, $current_breadcrumb);
    
    #-- Figure out what we're trying to templatize here or default to workgroups page.
    my $action = "workgroups";
    
    if ($cgi->param('action') =~ /^(\w+)$/){
	$action = $1;
    }
    
    if ($user->{'status'} eq 'decom') {
	$action = "decom";
    }
    
    
    switch ($action) {
	
	case "workgroups"    { $filename           = "html_templates/workgroups.html"; 
			       $title              = "Workgroups";      
			       $breadcrumbs        = [{title => "Workgroups", url => "?action=workgroups"}];
			       $current_breadcrumb = "Workgroups"; 
	}	
	case "index"         { $filename           = "html_templates/index.html"; 
			       $title              = "Home";      
			       $breadcrumbs        = $HOME_BREADCRUMBS;
			       $current_breadcrumb = "Home"; 
	}
	case "edit_details"  { $filename           = "html_templates/edit_details.html"; 
			       $title              = "Details";
			       $breadcrumbs        = $ADD_BREADCRUMBS;
			       $current_breadcrumb = "Details"; 
	}
	
	case "loop_circuit"  { $filename           = "html_templates/loop_circuit.html"; 
			       $title              = "Loop Circuit";
			       $breadcrumbs        = $DETAILS_BREADCRUMBS;
			       $current_breadcrumb = "Loop Circuit"; 
	}
	case "view_details"  { $filename           = "html_templates/view_details.html"; 
			       $title              = "Circuit Details";
			       $breadcrumbs        = $DETAILS_BREADCRUMBS;
			       $current_breadcrumb = "Circuit Details"; 
	}
	case "interdomain"   { $filename           = "html_templates/interdomain.html";
			       $title              = "Interdomain Endpoints";
			       $breadcrumbs        = $ADD_BREADCRUMBS;
			       $current_breadcrumb = "Endpoints";
	}
	case "endpoints"     { $filename           = "html_templates/endpoints.html";
			       $title              = "Endpoints";
			       $breadcrumbs        = $ADD_BREADCRUMBS;
			       $current_breadcrumb = "Endpoints";
	}
	case "options"       { $filename           = "html_templates/options.html";
			       $title              = "Options";
			       $breadcrumbs        = $ADD_BREADCRUMBS;
			       $current_breadcrumb = "Options";
	}
	case "primary_path"  { $filename           = "html_templates/primary_path.html";
			       $title              = "Primary Path";
			       $breadcrumbs        = $ADD_BREADCRUMBS;
			       $current_breadcrumb = "Primary Path";
	}
	case "backup_path"   { $filename           = "html_templates/backup_path.html";
			       $title              = "Backup Path";
			       $breadcrumbs        = $ADD_BREADCRUMBS;
			       $current_breadcrumb = "Backup Path";	    
	}
	case "scheduling"    { $filename           = "html_templates/scheduling.html";
			       $title              = "Scheduling";
			       $breadcrumbs        = $ADD_BREADCRUMBS;
			       $current_breadcrumb = "Scheduling";	    
	}
	
	case "provisioning" {
	    $filename           = "html_templates/provisioning.html";
	    $title              = "Provisioning";
	    $breadcrumbs        = $ADD_BREADCRUMBS;
	    $current_breadcrumb = "Provisioning";
	}
	case "remove_scheduling" {
	    $filename           = "html_templates/remove_scheduling.html";
	    $title              = "Removal Scheduling";
	    $breadcrumbs        = $REMOVE_BREADCRUMBS;
	    $current_breadcrumb = "Scheduling";
	}
	case "remove_provisioning" {
	    $filename           = "html_templates/remove_provisioning.html";
	    $title              = "Removal Provisioning";
	    $breadcrumbs        = $REMOVE_BREADCRUMBS;
	    $current_breadcrumb = "Provisioning";
	}
	case "decom" {
	    $filename = "html_templates/denied.html";
		$title    = "Access Denied";
	}
	case "about" {
	    $filename = "html_templates/splash.html";
	    $title    = "About";
	}
	else {
	    $filename = "html_templates/error.html"; 
	    $title    = "Error";
	}
	
    }
    $vars->{'admin_email'}        = $db->get_admin_email();
    
    $vars->{'page'}               = $filename;
    $vars->{'title'}              = $title;
    $vars->{'breadcrumbs'}        = $breadcrumbs;
    $vars->{'current_breadcrumb'} = $current_breadcrumb;
    $vars->{'is_admin'}           = $is_admin;		    
    $vars->{'is_read_only'}       = $is_read_only;
    $vars->{'version'}            = OESS::Database::VERSION;
    $vars->{'network_type'}       = $config->network_type;
    
	#print STDERR Dumper($vars);
    if ($action eq 'view_l3vpn' || $action eq 'provision_cloud' || $action eq 'modify_cloud' || $action eq 'phonebook' || $action eq 'welcome') {
	$tt->process("html_templates/base.html", $vars, \$output) or warn $tt->error();
    } else {
	$tt->process("html_templates/page_base.html", $vars, \$output) or warn $tt->error();
    }
    print "Content-type: text/html\n\n" . $output;
}


main();
