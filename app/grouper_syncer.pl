#!/usr/bin/perl

use strict;
use warnings;
use LWP::UserAgent;
use Data::Dumper;
use HTTP::Request::Common;
use GRNOC::Log;
use Getopt::Long;
use GRNOC::WebService::Client;
use JSON::XS;
my $log;

$ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 0;
$ENV{HTTPS_DEBUG} = 0;

my %all_oess_users;

sub main{
    my ($config_file, $verbose) = @_;

    #init_log4perl();

    $log = GRNOC::Log->new( level => 'INFO' );

    my $config = fetch_config( $config_file );
    
    my $oess = connect_to_oess( $config );
    
    my $wgs = $oess->get_workgroups( )->{'results'};
    log_debug("OESS Workgroups: " . Dumper($wgs));
    my $users = $oess->get_users()->{'results'};

    my %oess_wg;
    foreach my $wg (@$wgs){
	$oess_wg{$wg->{'name'}} = $wg;
    }
    
    foreach my $user (@$users){
	$all_oess_users{$user->{'auth_name'}[0]} = $user;
    }

    my $grouper_workgroups = make_group_request( url => $config->{'grouper'}->{'url'} . "/groups", user => $config->{'grouper'}->{'user'}, password => $config->{'grouper'}->{'password'}, stem => $config->{'grouper'}->{'stem'} );
    log_debug("Grouper Workgroups: " . Dumper($grouper_workgroups));

    foreach my $wg (@$grouper_workgroups){
	process_workgroup( workgroup => $wg, oess => $oess, oess_wg => \%oess_wg, config => $config );
    }

    #any workgroups that remain... should be removed
    foreach my $wg (keys %oess_wg){
	$oess->decom_workgroup( workgroup_id => $oess_wg{$wg}->{'workgroup_id'} );
    }
    
}

sub process_workgroup{
    my %params = @_;

    my $wg = $params{'workgroup'};
    my $oess_wg = $params{'oess_wg'};
    my $oess = $params{'oess'};
    my $config = $params{'config'};
    #apps:oessDemo:service:workgroups:barWorkgroup
    my $wg_name = $wg->{'extension'};
    
    if( !defined($oess_wg->{$wg_name}) ){
	log_info("Adding workgroup: " . $wg_name);
	my $res = $oess->add_workgroup( name => $wg_name,
					type => 'normal',
					max_circuit_endpoints => 10,
					max_mac_address_per_end => 10,
					max_circuits => 20 );
	
	$oess_wg->{$wg_name} = $res;

    }

    log_debug("Found workgroup: " . Dumper($oess_wg->{$wg_name}));
    my $users = $oess->get_users_in_workgroup( workgroup_id => $oess_wg->{$wg_name}->{'workgroup_id'} )->{'results'};
    log_debug("OESS Users: " . Dumper($users));
    
    log_debug("Grouper Workgroup: " . Dumper($wg));
    my $grouper_users = get_grouper_users( group => $wg, config => $config );
    log_debug("Grouper users: " . Dumper($grouper_users));

    #now compare the users
    compare_oess_users_to_grouper(oess => $oess, oess_users => $users, grouper_users => $grouper_users, workgroup => $oess_wg->{$wg_name});

    #finally delete this so we know its been handled...
    delete $oess_wg->{$wg_name};
}

sub compare_oess_users_to_grouper{
    my %params = @_;
    my $oess = $params{'oess'};
    my $workgroup = $params{'workgroup'};
    my $oess_users = $params{'oess_users'};
    my $grouper_users = $params{'grouper_users'};
    
    my %oess_users;

    foreach my $oess_user (@$oess_users){
	log_debug("OESS User: " . Dumper($oess_user));
	$oess_users{$oess_user->{'auth_name'}[0]} = $oess_user;
    }
    log_debug("OESS User Hash: " . Dumper(\%oess_users));
    foreach my $grouper_user (@$grouper_users){
	if(defined($oess_users{$grouper_user->{'username'}})){
	    log_debug("User " . $grouper_user->{'username'} . " already exists in workgroup " . $workgroup->{'workgroup_id'});
	    delete $oess_users{$grouper_user->{'username'}};
	}else{
	    #first find out if this user is in OESS
	    if(defined($all_oess_users{$grouper_user->{'username'}})){
		#we found the user in OESS just not in this workgroup!
		log_info("User " . $grouper_user->{'id'} . " already exists in OESS but not this workgroup... adding to workgroup " . $workgroup->{'workgroup_id'});
		$oess->add_user_to_workgroup( user_id => $all_oess_users{$grouper_user->{'username'}}->{'user_id'},
					      workgroup_id => $workgroup->{'workgroup_id'});
	    }else{
		log_info("Adding user " . $grouper_user->{'username'} . " to OESS and to workgroup: " . $workgroup->{'workgroup_id'});
		my $res = $oess->add_user( email_address => $grouper_user->{'email'},
					   status => 'active',
					   type => 'normal',
					   family_name => $grouper_user->{'last_name'},
					   first_name => $grouper_user->{'first_name'},
					   auth_name => $grouper_user->{'username'});
		log_debug("Add user result: " . Dumper($res));
		if(!defined($res) || !defined($res->{'results'}->[0]->{'user_id'})){
		    log_error("Error adding user to OESS: " . Dumper($res));
		}else{
		    my $user_id = $res->{'results'}->[0]->{'user_id'};
		    $oess->add_user_to_workgroup( user_id => $user_id,
						  workgroup_id => $workgroup->{'workgroup_id'});
		}
	    }
	}
    }

    log_debug("Extra users that need removing: " . Dumper(keys %oess_users));

    foreach my $ou (keys %oess_users){
	log_info("Removing User: " . $ou . " from workgroup " . $workgroup->{'workgroup_id'});
	$oess->remove_user_from_workgroup( workgroup_id => $workgroup->{'workgroup_id'},
					   user_id => $oess_users{$ou}->{'user_id'} );
	

    }
    

}
    
sub get_grouper_users{
    my %params = @_;
    my $group = $params{'group'};
    my $config = $params{'config'};
    
    my $url = $config->{'grouper'}->{'url'} . "/groups/" . $group->{'name'} . "/members";
    
    my $h = HTTP::Headers->new(
        Content_Type => 'application/json' );
    
    my $r = HTTP::Request->new('GET', $url, $h);
    $r->authorization_basic($config->{'grouper'}->{'user'}, $config->{'grouper'}->{'password'});
    my $ua = LWP::UserAgent->new;
    my $res = $ua->request($r);
    
    #log_debug("Results " . Dumper($res));
    
    my $obj = decode_json($res->content);
    my @grouper_users;
    

    foreach my $gu (@{$obj->{'WsGetMembersLiteResult'}->{'wsSubjects'}}){
	my $o = {'WsRestGetSubjectsRequest' => {'actAsSubjectLookup' => {'subjectId' => 'oess_provision'},
						'wsSubjectLookups' => [{'subjectId' => $gu->{'id'}}],
						'subjectAttributeNames' => ['givenname','sn','edupersonprincipalname','uid','employeenumber','cn','mail']}};
	my $str;
	eval{
	    $str = encode_json($o);
	};

	if(!defined($str)){
	    log_error("unable to encode our JSON for fetching user details");
	    die "unable to encode our JSON for fetching user details";
	}

	my $h = HTTP::Headers->new(
	    Content_Length => length($str),
	    Content_Type => 'text/x-json' );
	
	my $url = $config->{'grouper'}->{'url'} . "subjects";
	my $r = HTTP::Request->new('POST', $url, $h, $str);	
	$r->authorization_basic($config->{'grouper'}->{'user'}, $config->{'grouper'}->{'password'});
	my $res = $ua->request($r);
	
	log_debug("Results " . Dumper($res));
	my $obj;
	eval{
	    $obj = decode_json($res->content)->{'WsGetSubjectsResults'};
	};

	if(!defined($obj)){
	    log_error("Unable to fetch Grouper user details");
	    die "Unable to fetch Grouper User details";
	}
	log_debug("Attribute Values: " . Dumper($obj->{'wsSubjects'}->[0]->{'attributeValues'}));
	log_debug("Attribute Names: " . Dumper($obj->{'subjectAttributeNames'}));

	my $attrs = {};
	next if !defined($obj->{'wsSubjects'}->[0]->{'attributeValues'});
	for(my $i=0;$i<=scalar(@{$obj->{'wsSubjects'}->[0]->{'attributeValues'}});$i++){
	    $attrs->{ $obj->{'subjectAttributeNames'}->[$i] } = $obj->{'wsSubjects'}->[0]->{'attributeValues'}->[$i];
	}
	
	log_debug("User details: " .  Dumper($attrs));

	push(@grouper_users,{ id => $gu->{'id'},
			      first_name => $attrs->{'givenname'},
			      last_name => $attrs->{'sn'},
			      username => $attrs->{'edupersonprincipalname'},
			      email => $attrs->{'mail'} } );
	
    }
    
    return \@grouper_users;
}



sub fetch_config{
    my $config_file = shift;
    log_debug("Config File: " . $config_file); 
    my $config = GRNOC::Config->new( config_file => $config_file);
    
    my $res = {};
    
    my $grouper = {};
    my $oess = {};

    $grouper->{'user'} = $config->get('/config/grouper/@user')->[0];
    $grouper->{'url'} = $config->get('/config/grouper/@url')->[0];
    $grouper->{'password'} = $config->get('/config/grouper/@password')->[0];
    $grouper->{'stem'} = $config->get('/config/grouper/@stem')->[0];
    $oess->{'user'} = $config->get('/config/oess/@user')->[0];
    $oess->{'url'} = $config->get('/config/oess/@url')->[0];
    $oess->{'password'} = $config->get('/config/oess/@password')->[0];

    $res->{'grouper'} = $grouper;
    $res->{'oess'} = $oess;

    return $res;
}

sub connect_to_oess{
    my $config = shift;

    my $wsc = GRNOC::WebService::Client->new( url => $config->{'oess'}->{'url'} . "/admin/admin.cgi",
					      uid => $config->{'oess'}->{'user'},
					      passwd => $config->{'oess'}->{'password'},
					      realm => $config->{'oess'}->{'realm'},
					      verify_hostname => 0,
					      debug => 0
	);

    return $wsc;

    
}

sub make_group_request{    

    my %params = @_;

    my $url = $params{'url'};
    my $user = $params{'user'};
    my $password = $params{'password'};
    my $stem = $params{'stem'};

    my $ua = LWP::UserAgent->new;

    my $obj = {'WsRestFindGroupsRequest' => {'actAsSubjectLookup' => {'subjectId' => 'oess_provision'},
	       'wsQueryFilter' => {'queryFilterType' => 'FIND_BY_STEM_NAME', 'stemName' => $stem}}};
    my $str;
    eval{
	$str = encode_json($obj);
    };
    if(!defined($str)){
	log_error("Unable to compile our JSON object");
	die "Unable to compile our JSON object";
    }
    
    my $h = HTTP::Headers->new(
	Content_Length => length($str),
	Content_Type => 'text/x-json' );
    
    my $r = HTTP::Request->new('POST', $url, $h, $str);
    
    $r->authorization_basic($user, $password);
    
    my $res = $ua->request($r);
   
    log_debug("Results " . Dumper($res));
    
    my $o;
    eval{
	$o = decode_json($res->content);
    };
    
    if(!defined($o)){
	log_error("Error fetching workgroups from Grouper");
	die "Error fetching workgroups from Grouper";
    }

    log_debug("OBJ: " . Dumper($o));    
    return $o->{'WsFindGroupsResults'}->{'groupResults'};
}

my $config;
my $verbose;

GetOptions( "config=s" => \$config,
	    "verbose=s" => \$verbose );

main($config, $verbose);
