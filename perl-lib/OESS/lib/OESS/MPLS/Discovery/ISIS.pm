#!/usr/bin/perl

use strict;
use warnings;

package OESS::MPLS::Discovery::ISIS;

use OESS::Database;

use Log::Log4perl;
use AnyEvent;

sub new{
    my $class = shift;
    my %args = (
        @_
        );

    my $self = \%args;

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.MPLS.Discovery.ISIS');
    bless $self, $class;

    if(!defined($self->{'db'})){
	
	if(!defined($self->{'config'})){
	    $self->{'config'} = "/etc/oess/database.xml";
	}
	
	$self->{'db'} = OESS::Database->new( config_file => $self->{'config'} );
	
    }

    die if(!defined($self->{'db'}));

    return $self;
}

sub process_results{
    my $self = shift;
    my %params = @_;

    my $isis = $params{'isis'};
    if(!defined($isis)){
	$self->{'logger'}->error("Error fetching current links from the network...");
	return;
    }
    
    my $adjacencies = $self->_process_adjacencies($isis);
    my $res = $self->_diff_to_db($adjacencies);

    return $res;
}

sub _process_adjacencies{
    my $self = shift;
    my $isis = shift;
    
    my $adjacencies = {};
    
    foreach my $node (keys(%{$isis})){
	if(!defined($adjacencies->{$node})){
	    $adjacencies->{$node} = {};
	}

        foreach my $adj (@{$isis->{$node}->{'results'}}){
	    if(!defined($adjacencies->{$adj->{'remote_system_name'}})){
		$adjacencies->{$adj->{'remote_system_name'}} = {};
	    }
	    if(!defined($adjacencies->{$node}{$adj->{'remote_system_name'}})){
		$adjacencies->{$node}{$adj->{'remote_system_name'}} = {operational_state => $adj->{'operational_state'},
								       node_a => {node => $node,
										  interface_name => $adj->{'interface_name'},
								       },
								       node_z => {node => $adj->{'remote_system_name'},
										  ip_address => $adj->{'ip_address'},
										  ipv6_address => $adj->{'ipv6_address'}}};
		
		$adjacencies->{$adj->{'remote_system_name'}}{$node} = {operational_state => $adj->{'operational_state'},
								       node_z => {node => $node,
										  interface_name => $adj->{'interface_name'},
								       },
								       node_a => {node => $adj->{'remote_system_name'},
										  ip_address => $adj->{'ip_address'},
										  ipv6_address => $adj->{'ipv6_address'}}};
	    }else{
		#we already found it update it with the missing info from the other side!
		$adjacencies->{$adj->{'remote_system_name'}}{$node}{'node_a'}{'ip_address'} = $adj->{'ip_address'};
		$adjacencies->{$adj->{'remote_system_name'}}{$node}{'node_a'}{'ipv6_address'} = $adj->{'ipv6_address'};
		$adjacencies->{$adj->{'remote_system_name'}}{$node}{'node_z'}{'interface_name'} = $adj->{'interface_name'};
		$adjacencies->{$node}{$adj->{'remote_system_name'}}{'node_a'}{'interface_name'} = $adj->{'interface_name'};
		$adjacencies->{$node}{$adj->{'remote_system_name'}}{'node_a'}{'ip_address'} = $adj->{'ip_address'};
                $adjacencies->{$node}{$adj->{'remote_system_name'}}{'node_a'}{'ipv6_address'} = $adj->{'ipv6_address'};
	    }
        }
    }

    return $adjacencies;
}

sub _diff_to_db{
    my $self = shift;
    my $adj = shift;

    my %node_info;
    my $nodes = $self->{'db'}->get_current_nodes( mpls => 1);
    foreach my $node (@$nodes) {
        my $details = $self->{'db'}->get_node_by_id(node_id => $node->{'node_id'});
	next if(!$details->{'mpls'});
        $details->{'node_id'} = $details->{'node_id'};
	$details->{'id'} = $details->{'node_id'};
        $details->{'name'} = $details->{'name'};
	$details->{'ip'} = $details->{'ip'};
	$details->{'vendor'} = $details->{'vendor'};
	$details->{'model'} = $details->{'model'};
	$details->{'sw_version'} = $details->{'sw_version'};
	$node_info{$node->{'name'}} = $details;
    }

    my $links = $self->{'db'}->get_current_links( mpls => 1);
   
    my $processed_links = $self->_process_db_links($links);

    foreach my $node_a (keys (%{$adj})){
	foreach my $node_z (keys(%{$adj->{$node_a}})){
	    
	    if(!defined($node_info{$node_a}) || !defined($node_info{$node_z})){
		warn "Adj without a configured NODE!!!!!\n";
		$self->{'logger'}->info("An adjacency was detected between a configured node and a non-configured node... ignoring");
		next;
	    }

	    if(defined($processed_links->{$node_a}{$node_z})){
		#link exists in the DB!
		#check and see if the interfaces line up!
		if($processed_links->{$node_a}{$node_z}->{'node_a'} eq $node_a){
		    if($processed_links->{$node_a}{$node_z}{'interface_a'} eq $adj->{$node_a}{$node_z}{'node_a'}{'interface_name'} && 
			$processed_links->{$node_a}{$node_z}{'interface_z'} eq $adj->{$node_a}{$node_z}{'node_z'}{'interface_name'} ){
			#interfaces lines up
			#nothing to do
		    }else{
			#interfaces don't line up... lets fix!

			my $a_int = $self->{'db'}->get_interface_id_by_names( node => $node_a,
									      interface => $adj->{$node_a}{$node_z}{'node_a'}{'interface_name'});
			my $z_int = $self->{'db'}->get_interface_id_by_names( node => $node_z,
                                                                              interface => $adj->{$node_a}{$node_z}{'node_z'}{'interface_name'});
			
			if(!defined($a_int) || !defined($z_int)){
			    next;
			}

			$self->{'db'}->decom_link_instantiation( link_id => $processed_links->{$node_a}{$node_z}{'link_id'} );
			$self->{'db'}->create_link_instantiation( link_id => $processed_links->{$node_a}{$node_z}{'link_id'},
								  interface_a_id => $a_int,
								  interface_z_id => $z_int,
								  state => $processed_links->{$node_a}{$node_z}{'state'},
								  mpls => 1,
								  openflow => $processed_links->{$node_a}{$node_z}{'openflow'} );
		    }

		}else{
		    
		    if($processed_links->{$node_a}{$node_z}{'interface_z'} eq $adj->{$node_a}{$node_z}{'node_a'}{'interface_name'} &&
		       $processed_links->{$node_a}{$node_z}{'interface_a'} eq $adj->{$node_a}{$node_z}{'node_z'}{'interface_name'} ){
                        #interfaces lines up
                        #nothing to do
                    }else{
                        #interfaces don't line up... lets fix!

                        my $a_int = $self->{'db'}->get_interface_id_by_names( node => $node_a,
                                                                              interface => $adj->{$node_a}{$node_z}{'node_a'}{'interface_name'});
                        my $z_int = $self->{'db'}->get_interface_id_by_names( node => $node_z,
                                                                              interface => $adj->{$node_a}{$node_z}{'node_z'}{'interface_name'});
			
                        if(!defined($a_int) || !defined($z_int)){
			    warn "Unable to find interfaces for link\n";
                            next;
                        }
			
                        $self->{'db'}->decom_link_instantiation( link_id => $processed_links->{$node_a}{$node_z}{'link_id'} );
                        $self->{'db'}->create_link_instantiation( link_id => $processed_links->{$node_a}{$node_z}{'link_id'},
                                                                  interface_a_id => $a_int,
                                                                  interface_z_id => $z_int,
                                                                  state => $processed_links->{$node_a}{$node_z}{'state'},
								  mpls => 1,
								  openflow => $processed_links->{$node_a}{$node_z}{'openflow'} );
                    }
		}

		#do we need to change our operational state!
		if($processed_links->{$node_a}{$node_z} eq lc($adj->{$node_a}{$node_z}{'operational_status'})){
		    $self->{'logger'}->debug("link state is the same");
		}else{
		    $self->{'logger'}->info("Link changed state: " . $processed_links->{$node_a}{$node_z}{'name'} . " to " . lc($adj->{$node_a}{$node_z}{'operational_status'}));
		    $self->{'db'}->update_link_state( link_id => $processed_links->{$node_a}{$node_z}{'link_id'},
						      state => lc($adj->{$node_a}{$node_z}{'operational_status'}));
		}

		
		#finally delete it from our list of links
		delete $processed_links->{$node_a}{$node_z};
                delete $processed_links->{$node_z}{$node_a};
		delete $adj->{$node_a}{$node_z};
                delete $adj->{$node_z}{$node_a};
	    }else{
		my $a_int = $self->{'db'}->get_interface_id_by_names( node => $node_a,
								      interface => $adj->{$node_a}{$node_z}{'node_a'}{'interface_name'});
		my $z_int = $self->{'db'}->get_interface_id_by_names( node => $node_z,
								      interface => $adj->{$node_a}{$node_z}{'node_z'}{'interface_name'});

		#check and see if there is an OF link!
		my $of_links = $self->{'db'}->get_current_links( openflow => 1);
		my $processed_of_links = $self->_process_links($of_links);
		if(defined($processed_of_links->{$node_a}{$node_z})){
		    #update it!
		    $self->{'db'}->decom_link_instantiation( link_id => $processed_of_links->{$node_a}{$node_z}{'link_id'} );
		    $self->{'db'}->create_link_instantiation( link_id => $processed_of_links->{$node_a}{$node_z}{'link_id'},
							      interface_a_id => $a_int,
							      interface_z_id => $z_int,
							      state => $processed_of_links->{$node_a}{$node_z}{'state'},
							      mpls => 1,
							      openflow => $processed_of_links->{$node_a}{$node_z}{'openflow'} );
		}else{
		    #link does NOT exist... add it to the DB!		
		    my $link_id = $self->{'db'}->add_link( name => $node_a . "-" . $adj->{$node_a}{$node_z}{'node_a'}{'interface_name'} . "--" . $node_z . "-" . $adj->{$node_a}{$node_z}{'node_z'}{'interface_name'},
							   remote_urn => undef,
							   vlan_tag_range => undef);
		    
		    if(!defined($link_id)){
			warn "Unable to create link in the database\n";
			$self->{'logger'}->error("Unable to create Link in the database");
			next;
		    }
		    
		    if(!defined($a_int) || !defined($z_int)){
			warn "Unable to find interfaces for the link\n";
			$self->{'logger'}->error("Unable to find interfaces for the link");
			next;
		    }
		    
		    my $res = $self->{'db'}->create_link_instantiation( link_id => $link_id,
									interface_a_id => $a_int,
									interface_z_id => $z_int,
									state => 'available',
									openflow => 0,
									mpls => 1 );
		    if(!defined($res)){
			warn "Unable to create link instantiation: " . $self->{'db'}->get_error();
			$self->{'logger'}->error("unable to create link instantiation: " . $self->{'db'}->get_error());
		    }
		}
		delete $adj->{$node_a}{$node_z};
		delete $adj->{$node_z}{$node_a};
	    }
	}
    }

    foreach my $node_a (keys (%{$processed_links})){
        foreach my $node_z (keys(%{$processed_links->{$node_a}})){    
	    
	    #this link is gone...
	    #what to do...
	    #right now nothing... you have to decom in OESS UI

	}
    }

}

sub _process_db_links{
    my $self = shift;
    my $links = shift;
    
    my %links;

    foreach my $link (@$links){
	my $link_details = $self->{'db'}->get_link_details( name => $link->{'name'});
	
	next if !defined($link_details);

	$link_details->{'link_id'} = $link->{'link_id'};
	$link_details->{'status'} = $link->{'status'};
	$link_details->{'state'} = $link->{'state'};
	$link_details->{'openflow'} = $link->{'openflow'};

	if(!defined($links{$link_details->{'node_a'}})){
	    $links{$link_details->{'node_a'}} = {};
	}

	if(!defined($links{$link_details->{'node_z'}})){
            $links{$link_details->{'node_z'}} = {};
        }

	if(!defined($links{$link_details->{'node_a'}}{$link_details->{'node_z'}})){
	    $links{$link_details->{'node_a'}}{$link_details->{'node_z'}} = $link_details;
	}

	if(!defined($links{$link_details->{'node_z'}}{$link_details->{'node_a'}})){
            $links{$link_details->{'node_z'}}{$link_details->{'node_a'}} = $link_details;
        }
}

    return \%links;
}

sub _signal_link_addition{
    
}

sub _signal_link_deletion{

}

sub _signal_link_state_change{

}

1;
