#!/usr/bin/perl -T
#
##----- NDDI OESS Measurement.cgi
##-----                                                                                  
##----- $HeadURL: svn+ssh://svn.grnoc.iu.edu/grnoc/oe-ss/frontend/tags/1.0.0/webservice/measurement.cgi $
##----- $Id$
##----- $Date$
##----- $LastChangedBy$
##-----                                                                                
##----- Provides Measurement data to the UI
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

use CGI;
use JSON;
use Switch;
use Data::Dumper;

use OESS::Database;
use OESS::Topology;
use OESS::Measurement qw(BUILDING_FILE);

my $db          = new OESS::Database();
my $topo        = new OESS::Topology();
my $measurement = new OESS::Measurement();

my $cgi  = new CGI;

$| = 1;

sub main {

    if (! $db){
	send_json({"error" => "Unable to connect to database."});
	exit(1);
    }    

    my $action = $cgi->param('action');

    my $output;

    switch ($action){
	
	case "get_circuit_data" {
	    $output = &get_circuit_data();
	}
	else{
	    $output = {error => "Unknown action - $action"};
	}

    }
    
    send_json($output);
    
}

sub get_circuit_data {
    my $results;

    my $start      = $cgi->param("start");
    my $end        = $cgi->param("end");
    my $circuit_id = $cgi->param("circuit_id");

    if ($start !~ /^\d+$/ || $end !~ /^\d+$/ || $circuit_id !~ /^\d+$/){
	return undef;
    }

    my $data = $measurement->get_circuit_data(circuit_id => $circuit_id,
					      start_time => $start,
					      end_end    => $end
	);


    if (! defined $data){
	$results->{'results'} = [];
	$results->{'error'} = $measurement->get_error();
    }
    elsif ($data eq BUILDING_FILE){
	$results->{'results'}     = [];
	$results->{'in_progress'} = 1;
    }
    else{   

       # TEMPORARY HACK FOR PING STUFF                                                                                                                                                        \
                                                                                                                                                                                               

        if (-e "/tmp/pinger_stats.csv"){

            open(PING_STATS, "/tmp/pinger_stats.csv");

            my $ping_data;

            while (my $line = <PING_STATS>){

		my ($ip, $time, $value) = split(/,/, $line);

		next if ($time < $start);

                push (@$ping_data, [$time, $value]);

            }

            if (defined $ping_data && @$ping_data > 0){
		push(@$data, {"name" => "Ping (ms)",
			      "data" => $ping_data});
	    }

	}

	$results->{'results'} = $data;
    } 

    return $results;
}


sub send_json{
    my $output = shift;
        
    print "Content-type: text/plain\n\n" . encode_json($output);
}

main();

