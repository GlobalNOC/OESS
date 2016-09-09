#!/usr/bin/perl

use strict;
use warnings;

package OESS::MPLS::Device::Juniper::MX;

use Template;
use Net::Netconf::Manager;
use Data::Dumper;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;

use GRNOC::Config;

use base "OESS::MPLS::Device";

sub new{
    my $class = shift;
    my %args = (
        @_
	);
    
    my $self = \%args;
    bless $self, $class;

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.MPLS.Device.Juniper.MX.' . $self->{'mgmt_addr'});
    $self->{'logger'}->info("MPLS Juniper Switch Created: $self->{'mgmt_addr'}");

    #TODO: make this automatically figure out the right REV
    $self->{'template_dir'} = "juniper/13.3R8";

    $self->{'tt'} = Template->new(INCLUDE_PATH => "/usr/share/doc/perl-OESS-1.2.0/share/mpls/templates/") or die "Unable to create Template Toolkit!";

    my $creds = $self->_get_credentials();
    if(!defined($creds)){
	die "Unable to fetch credentials!";
    }
    $self->{'username'} = $creds->{'username'};
    $self->{'password'} = $creds->{'password'};

    return $self;
}

sub disconnect{
    my $self = shift;

    if (defined $self->{'jnx'}) {
        $self->{'jnx'}->disconnect();
    } else {
        $self->{'logger'}->info("Device is already disconnected.");
    }

    $self->{'connected'} = 0;

    return 1;
}

sub get_system_information{
    my $self = shift;

    my $reply = $self->{'jnx'}->get_system_information();

    if($self->{'jnx'}->has_error){
        $self->{'logger'}->error("Error fetching system information: " . Data::Dumper::Dumper($self->{'jnx'}->get_first_error()));
        return;
    }

    my $system_info = $self->{'jnx'}->get_dom();
    my $xp = XML::LibXML::XPathContext->new( $system_info);
    $xp->registerNs('x',$system_info->documentElement->namespaceURI);     
    my $model = $xp->findvalue('/x:rpc-reply/x:system-information/x:hardware-model');
    my $version = $xp->findvalue('/x:rpc-reply/x:system-information/x:os-version');
    my $host_name = $xp->findvalue('/x:rpc-reply/x:system-information/x:host-name');
    my $os_name = $xp->findvalue('/x:rpc-reply/x:system-information/x:os-name');

    # We need to create know the root path for our xml requests. This path containd the version minus the last number block
    # (13.3R1.6 -> 13.3R1). The following regex creates the path as described
    my $var = $version;
    $var =~ /(\d+\.\d+R\d+)/;
    my $root_namespace = "http://xml.juniper.net/junos/".$1.'/';
    $self->{'root_namespace'} = $root_namespace;


    #also need to fetch the interfaces and find lo0.X
    $reply = $self->{'jnx'}->get_interface_information();
    if($self->{'jnx'}->has_error){
        $self->set_error($self->{'jnx'}->get_first_error());
        $self->{'logger'}->error("Error fetching interface information: " . Data::Dumper::Dumper($self->{'jnx'}->get_first_error()));
        return;
    }

    my $interfaces = $self->{'jnx'}->get_dom();
    my $path = $self->{'root_namespace'}."junos-interface";
    $xp = XML::LibXML::XPathContext->new( $interfaces);
    $xp->registerNs('x',$interfaces->documentElement->namespaceURI);
    $xp->registerNs('j',$path);
    my $ints = $xp->findnodes('/x:rpc-reply/j:interface-information/j:physical-interface');

    my $loopback_addr;

    foreach my $int ($ints->get_nodelist){
	my $xp = XML::LibXML::XPathContext->new( $int );
	my $path = $self->{'root_namespace'}."junos-interface";
	$xp->registerNs('j',$path);
	my $name = trim($xp->findvalue('./j:name'));
	next if ($name ne 'lo0');
	
	my $logical_ints = $xp->find('./j:logical-interface');
	foreach my $log (@{$logical_ints}){
	    my $log_xp = XML::LibXML::XPathContext->new( $log );
	    my $path = $self->{'root_namespace'}."junos-interface";
	    $log_xp->registerNs('j',$path);
	    my $log_name = trim($log_xp->findvalue('./j:name'));
	    if($log_name eq 'lo0.0'){
		my $addresses = $log_xp->find("./j:address-family");
		foreach my $addr (@$addresses){
		    my $af_xp = XML::LibXML::XPathContext->new( $addr );
		    my $path = $self->{'root_namespace'}."junos-interface";
		    $af_xp->registerNs('j',$path);
		    my $af_name = trim($af_xp->findvalue('./j:address-family-name'));
		    next if $af_name ne 'inet';
		    my $addrs = $af_xp->find('./j:interface-address/j:ifa-local');
		    foreach my $ad (@$addrs){
			my $address = trim($ad->textContent);
			next if(!defined($address));
			next if $address eq '';
			next if $address eq '127.0.0.1';
			$loopback_addr = $address;		       
		    }
		}
	    }
	}

	
    }

    return {model => $model, version => $version, os_name => $os_name, host_name => $host_name, loopback_addr => $loopback_addr};
}

sub get_interfaces{
    my $self = shift;

    my $reply = $self->{'jnx'}->get_interface_information();

    if($self->{'jnx'}->has_error){
	$self->set_error($self->{'jnx'}->get_first_error());
        $self->{'logger'}->error("Error fetching interface information: " . Data::Dumper::Dumper($self->{'jnx'}->get_first_error()));
        return;
    }

    my @interfaces;

    my $interfaces = $self->{'jnx'}->get_dom();
    my $path = $self->{'root_namespace'}."junos-interface";
    my $xp = XML::LibXML::XPathContext->new( $interfaces);
    $xp->registerNs('x',$interfaces->documentElement->namespaceURI);
    $xp->registerNs('j',$path);  
    my $ints = $xp->findnodes('/x:rpc-reply/j:interface-information/j:physical-interface');

    foreach my $int ($ints->get_nodelist){
	push(@interfaces, $self->_process_interface($int));
    }

    return \@interfaces;
}

sub _process_interface{
    my $self = shift;
    my $int = shift;
    
    my $obj = {};

    my $xp = XML::LibXML::XPathContext->new( $int );
    my $path = $self->{'root_namespace'}."junos-interface";
    $xp->registerNs('j',$path);
    $obj->{'name'} = trim($xp->findvalue('./j:name'));
    $obj->{'admin_state'} = trim($xp->findvalue('./j:admin-status'));
    $obj->{'operational_state'} = trim($xp->findvalue('./j:oper-status'));
    $obj->{'description'} = trim($xp->findvalue('./j:description'));
    if(!defined($obj->{'description'}) || $obj->{'description'} eq ''){
	$obj->{'description'} = $obj->{'name'};
    } 

    return $obj;

}

sub remove_vlan{
    my $self = shift;
    my $ckt = shift;

    my $vars = {};
    $vars->{'circuit_name'} = $ckt->{'circuit_name'};
    $vars->{'interfaces'} = [];
    foreach my $i (@{$ckt->{'interfaces'}}) {
        push (@{$vars->{'interfaces'}}, { name => $i->{'interface'},
                                          tag  => $i->{'tag'}
                                        });
    }
    $vars->{'circuit_id'} = $ckt->{'circuit_id'};
    $vars->{'switch'} = {name => $self->{'name'}};
    $vars->{'site_id'} = $ckt->{'site_id'};
    $vars->{'paths'} = $ckt->{'paths'};
    $vars->{'a_side'} = $ckt->{'a_side'};

    my $output;
    my $remove_template = $self->{'tt'}->process( $self->{'template_dir'} . "/" . $ckt->{'ckt_type'} . "/ep_config_delete.xml", $vars, \$output) or $self->{'logger'}->error( $self->{'tt'}->error());

    $self->{'logger'}->error("Remove Config: " . $output);

    return $self->_edit_config( config => $output );
}

sub add_vlan{
    my $self = shift;
    my $ckt = shift;
    
    $self->{'logger'}->error("Adding circuit: " . Data::Dumper::Dumper($ckt));

    my $vars = {};
    $vars->{'circuit_name'} = $ckt->{'circuit_name'};
    $vars->{'interfaces'} = [];
    foreach my $i (@{$ckt->{'interfaces'}}) {
        push (@{$vars->{'interfaces'}}, { name => $i->{'interface'},
                                          tag  => $i->{'tag'}
                                        });
    }
    $vars->{'paths'} = $ckt->{'paths'};
    $vars->{'destination_ip'} = $ckt->{'destination_ip'};
    $vars->{'circuit_id'} = $ckt->{'circuit_id'};
    $vars->{'switch'} = {name => $self->{'name'}};
    $vars->{'site_id'} = $ckt->{'site_id'};
    $vars->{'paths'} = $ckt->{'paths'};
    $vars->{'a_side'} = $ckt->{'a_side'};

#    if ($self->unit_name_available($vars->{'interface'}->{'name'}, $vars->{'vlan_tag'}) == 0) {
#        return FWDCTL_FAILURE;
#    }

    my $ckt_type = $ckt->{'mpls_type'};

    my $output;
    my $add_template = $self->{'tt'}->process( $self->{'template_dir'} . "/" . $ckt->{'ckt_type'} . "/ep_config.xml", $vars, \$output) or  $self->{'logger'}->error($self->{'tt'}->error());
    
    $self->{'logger'}->error("ADD config: " . $output);

    return $self->_edit_config( config => $output );    
    
}

=head2 diff

Do a diff between $ckts and the circuits on this device.

=cut
sub diff {
    my $self = shift;
    my $ckts = shift;
    my $pending_diff = shift; # Sourced from the DB

    # Convert $ckts to configuration
    my $configuration = '<configuration>';
    foreach my $ckt (@{$ckts}) {
        my $addition;

        my $vars = {};
        $vars->{'circuit_name'} = $ckt->{'circuit_name'};
        $vars->{'interfaces'} = [];
        foreach my $i (@{$ckt->{'interfaces'}}) {
            push (@{$vars->{'interfaces'}}, { name => $i->{'interface'},
                                              tag  => $i->{'tag'}
                                            });
        }
        $vars->{'paths'} = $ckt->{'paths'};
        $vars->{'destination_ip'} = $ckt->{'destination_ip'};
        $vars->{'circuit_id'} = $ckt->{'circuit_id'};
        $vars->{'switch'} = {name => $self->{'name'}};
        $vars->{'site_id'} = $ckt->{'site_id'};
        $vars->{'paths'} = $ckt->{'paths'};
        $vars->{'a_side'} = $ckt->{'a_side'};

        $self->{'tt'}->process($self->{'template_dir'} . "/" . $ckt->{'ckt_type'} . "/ep_config.xml", $vars, \$addition);
        $addition =~ s/<configuration>//g;
        $addition =~ s/<\/configuration>//g;
        $configuration = $configuration . $addition;
    }
    $configuration = $configuration . '</configuration>';

    # NOTE - Test data in diff_text overwrites this config
    my $diff = $self->diff_text($configuration);

    # The diff is apparently too big to trust.
    # NOTE - Any diff larger than one char will trigger this block
    if ($self->_large_diff($diff)) {
        if ($pending_diff) {
            if ($self->{'pending_diff'}) {
                $self->{'logger'}->info('Still waiting for approval before diff installation.');
                return 0;
            } else {
                $self->{'logger'}->info('Large diff approved. Starting installation.');
                $self->{'pending_diff'} = 0;
                $self->_edit_config(config => $configuration);
                return 1;
            }
        } else {
            $self->{'logger'}->info('Large diff detected. Waiting for approval before installation.');
            $self->{'pending_diff'} = 1;
            return 0;
        }
    }

    $self->_edit_config(config => $configuration);
    return 1;
}

=head2 diff_text

Returns a human readable diff for display to users.

=cut
sub diff_text {
    my $self = shift;
    my $conf = shift;

    # Test data - Remove
    $conf = "<configuration><interfaces><interface><name>xe-2/0/0</name><unit>" .
      "<name>1000</name><description>Foo</description></unit></interface>" .
      "</interfaces></configuration>";

    my %queryargs = ('target' => 'candidate');
    $self->{'jnx'}->lock_config(%queryargs);


    %queryargs = ('target' => 'candidate');
    $queryargs{'config'} = $conf;
    my $res = $self->{'jnx'}->edit_config(%queryargs);

    my $configcompare = $self->{'jnx'}->get_configuration( compare => "rollback", rollback => "0" );
    if ($self->{'jnx'}->has_error) {
	$self->set_error($self->{'jnx'}->get_first_error());
        $self->{'logger'}->error("Error getting diff from MX: " . Data::Dumper::Dumper($self->{'jnx'}->get_first_error()));
        return;
    }

    my $dom = $self->{'jnx'}->get_dom();
    my $diff = $dom->getElementsByTagName('configuration-output')->string_value();
    
    $res = $self->{'jnx'}->discard_changes();
    %queryargs = ('target' => 'candidate');
    $self->{'jnx'}->unlock_config(%queryargs);

    return $diff;
}

=head2 _large_diff

Returns 1 if $diff requires manual approval.

=cut
sub _large_diff {
    my $self = shift;
    my $diff = shift;

    my $len = length($diff);
    if ($len > 0) {
        return 1;
    }

    return 0;
}

=head2

Returns 0 if the unit name already exists on the specified interface or
another error occurs; Otherwise 1 is returned for success.

=cut
sub unit_name_available {
    my $self           = shift;
    my $interface_name = shift;
    my $unit_name      = shift;

    if (!defined $self->{'jnx'}) {
        my $err = "Netconf connection is down.";
        $self->set_error($err);
        $self->{'logger'}->error($err);
        return 0;
    }

    eval {
        my %queryargs = ('source' => 'candidate');
        $self->{'jnx'}->get_config(%queryargs);
    };
    if ($@) {
        my $err = "$@";
        $self->set_error($err);
        $self->{'logger'}->error($err);
        return 0;
    };

    my $dom  = $self->{'jnx'}->get_dom();
    my $xml  = XML::LibXML::XPathContext->new($dom);

    $xml->registerNs("base", $dom->documentElement->namespaceURI);
    $xml->registerNs("conf", "http://xml.juniper.net/xnm/1.1/xnm");

    my $interfaces = $xml->findnodes("/base:rpc-reply/base:data/conf:configuration/conf:interfaces/conf:interface");
    foreach my $interface ($interfaces->get_nodelist) {
        my $iface_name = $xml->findvalue("./conf:name", $interface);
        my $units      = $xml->findnodes("./conf:unit", $interface);

        if ($iface_name eq $interface_name) {
            foreach my $unit ($units->get_nodelist) {
                my $name = $xml->findvalue("./conf:name", $unit);
                if ($name eq $unit_name) {
                    my $err = "Unit name conflict exists. Please use a different VLAN.";
                    $self->set_error($err);
                    $self->{'logger'}->error($err);
                    return 0;
                }
            }
        }
    }

    return 1;
}

=head2 connect

Returns 1 if a new connection is established. If the connection is
already established this function will also return 1. Otherwise an error
has occured and 0 is returned.

=cut
sub connect {
    my $self = shift;


    if ($self->connected()) {
        $self->{'logger'}->warn("Already connected to Juniper MX $self->{'mgmt_addr'}!");
        return 1;
    }

    my $jnx;

    eval {
        $self->{'logger'}->info("Connecting to device!");
        $jnx = new Net::Netconf::Manager( 'access' => 'ssh',
                                          'login' => $self->{'username'},
                                          'password' => $self->{'password'},
                                          'hostname' => $self->{'mgmt_addr'},
                                          'port' => 22,
                                          'debug_level' => 0 );
    };
    if ($@ || !$jnx) {
        my $err = "Could not connect to $self->{'mgmt_addr'}. Connection timed out.";
        $self->set_error($err);
        $self->{'logger'}->error($err);
	$self->{'connected'} = 0;
        return $self->{'connected'};
    }

    $self->{'connected'} = 1;
    $self->{'jnx'}       = $jnx;

    # Gather basic system information needed later!
    my $verify = $self->verify_connection();
    if ($verify != 1) {
        my $err = "Failure while verifying $self->{'mgmt_addr'}. Connection closed.";
        $self->set_error($err);
        $self->{'logger'}->error($err);
	$self->{'connected'} = 0;
        return $self->{'connected'};
    }

    # Configures parameters for the get_configuration method
    my $ATTRIBUTE = bless {}, 'ATTRIBUTE';
    $self->{'jnx'}->{'methods'}->{'get_configuration'} = { format   => $ATTRIBUTE,
                                                           compare  => $ATTRIBUTE,
                                                           changed  => $ATTRIBUTE,
                                                           database => $ATTRIBUTE,
                                                           rollback => $ATTRIBUTE };

    $self->{'logger'}->info("Connected to device!");
    return $self->{'connected'};
}

sub connected{
    my $self = shift;
    return $self->{'connected'};
}

sub verify_connection{
    #gather basic system information needed later, and make sure it is what we expected / are prepared to handle                                                                            
    #
    my $self = shift;
    my $sysinfo = $self->get_system_information();
    if (($sysinfo->{"os_name"} eq "junos") && ($sysinfo->{"version"} eq "13.3R1.6")){
	# print "Connection verified, proceeding\n";
	return 1;
    }
    else {
	$self->{'logger'}->error("Network OS and / or version is not supported");
	return 0;
    }
    
}

sub get_isis_adjacencies{
    my $self = shift;

    $self->{'logger'}->error("INSIDE GET_ISIS_ADJACENCIES");
    
    if(!defined($self->{'jnx'}->{'methods'}->{'get_isis_adjacency_information'})){
	my $TOGGLE = bless { 1 => 1 }, 'TOGGLE';
	$self->{'jnx'}->{'methods'}->{'get_isis_adjacency_information'} = { detail => $TOGGLE};
    }

    $self->{'jnx'}->get_isis_adjacency_information( detail => 1 );

    my $xml = $self->{'jnx'}->get_dom();
    $self->{'logger'}->error("ISIS: " . $xml->toString());
    my $xp = XML::LibXML::XPathContext->new( $xml);
    $xp->registerNs('x',$xml->documentElement->namespaceURI);
    my $path = $self->{'root_namespace'}."junos-routing";
    $xp->registerNs('j',$path);

    my $adjacencies = $xp->find('/x:rpc-reply/j:isis-adjacency-information/j:isis-adjacency');
    
    my @adj;
    foreach my $adjacency (@$adjacencies){
	push(@adj, $self->_process_isis_adj($adjacency));
    }

    return \@adj;
}

sub _process_isis_adj{
    my $self = shift;
    my $adj = shift;

    my $obj = {};

    my $xp = XML::LibXML::XPathContext->new( $adj );
    my $path = $self->{'root_namespace'}."junos-routing";
    $xp->registerNs('j',$path);
    $obj->{'interface_name'} = trim($xp->findvalue('./j:interface-name'));
    $obj->{'operational_state'} = trim($xp->findvalue('./j:adjacency-state'));
    $obj->{'remote_system_name'} = trim($xp->findvalue('./j:system-name'));
    $obj->{'ip_address'} = trim($xp->findvalue('./j:ip-address'));
    $obj->{'ipv6_address'} = trim($xp->findvalue('./j:ipv6-address'));

    $obj->{'remote_system_name'} =~ s/-re\d+//g;
    $obj->{'interface_name'} =~ s/\.\d+//g;

    return $obj;
}

sub get_LSPs{
    my $self = shift;

    if(!defined($self->{'jnx'}->{'methods'}->{'get_mpls_lsp_information'})){
        my $TOGGLE = bless { 1 => 1 }, 'TOGGLE';
        $self->{'jnx'}->{'methods'}->{'get_mpls_lsp_information'} = { detail => $TOGGLE};
    }

    $self->{'jnx'}->get_mpls_lsp_information( detail => 1);
    my $xml = $self->{'jnx'}->get_dom();
    my $xp = XML::LibXML::XPathContext->new( $xml);
    $xp->registerNs('x',$xml->documentElement->namespaceURI);
    $xp->registerNs('j',"http://xml.juniper.net/junos/13.3R1/junos-routing");
    my $rsvp_session_data = $xp->find('/x:rpc-reply/j:mpls-lsp-information/j:rsvp-session-data');
    
    my @LSPs;

    foreach my $rsvp_sd (@{$rsvp_session_data}){
	push(@LSPs,_process_rsvp_session_data($rsvp_sd));
    }

    return \@LSPs;
}

sub _process_rsvp_session_data{
    my $rsvp_sd = shift;
    
    my $obj = {};

    my $xp = XML::LibXML::XPathContext->new( $rsvp_sd);
    $xp->registerNs('j',"http://xml.juniper.net/junos/13.3R1/junos-routing");
    $obj->{'session_type'} = trim($xp->findvalue('./j:session-type'));
    $obj->{'count'} = trim($xp->findvalue('./j:count'));
    $obj->{'sessions'} = ();

    my $rsvp_sessions = $xp->find('./j:rsvp-session');

    if($obj->{'session_type'} eq 'Ingress'){
	
	foreach my $session (@{$rsvp_sessions}){
	    push(@{$obj->{'sessions'}}, _process_rsvp_session_ingress($session));
	}
	
    }elsif($obj->{'session_type'} eq 'Egress'){

	foreach my $session (@{$rsvp_sessions}){
            push(@{$obj->{'sessions'}}, _process_rsvp_session_egress($session));
        }

    }else{
	
	foreach my $session (@{$rsvp_sessions}){
            push(@{$obj->{'sessions'}}, _process_rsvp_session_transit($session));
        }

    }
    return $obj;

}

sub _process_rsvp_session_transit{
    my $session = shift;

    my $obj = {};

    my $xp = XML::LibXML::XPathContext->new( $session );
    $xp->registerNs('j',"http://xml.juniper.net/junos/13.3R1/junos-routing");
    $obj->{'name'} = trim($xp->findvalue('./j:name'));
    $obj->{'route-count'} = trim($xp->findvalue('./j:route-count'));
    $obj->{'description'} = trim($xp->findvalue('./j:description'));
    $obj->{'destination-address'} = trim($xp->findvalue('./j:destination-address'));
    $obj->{'source-address'} = trim($xp->findvalue('./j:source-address'));
    $obj->{'lsp-state'} = trim($xp->findvalue('./j:lsp-state'));
    $obj->{'lsp-path-type'} = trim($xp->findvalue('./j:lsp-path-type'));
    $obj->{'suggested-lable-in'} = trim($xp->findvalue('./j:suggested-label-in'));
    $obj->{'suggested-label-out'} = trim($xp->findvalue('./j:suggested-label-out'));
    $obj->{'recovery-label-in'} = trim($xp->findvalue('./j:recovery-label-in'));
    $obj->{'recovery-label-out'} = trim($xp->findvalue('./j:recovery-label-out'));
    $obj->{'rsb-count'} = trim($xp->findvalue('./j:rsb-count'));
    $obj->{'resv-style'} = trim($xp->findvalue('./j:resv-style'));
    $obj->{'label-in'} = trim($xp->findvalue('./j:label-in'));
    $obj->{'label-out'} = trim($xp->findvalue('./j:label-out'));
    $obj->{'psb-lifetime'} = trim($xp->findvalue('./j:psb-lifetime'));
    $obj->{'psb-creation-time'} = trim($xp->findvalue('./j:psb-creation-time'));
    $obj->{'lsp-id'} = trim($xp->findvalue('./j:lsp-id'));
    $obj->{'tunnel-id'} = trim($xp->findvalue('./j:tunnel-id'));
    $obj->{'proto-id'} = trim($xp->findvalue('./j:proto-id'));
    $obj->{'adspec'} = trim($xp->findvalue('./j:adspec'));

    my $pkt_infos = $xp->find('./j:packet-information');
    $obj->{'packet-information'} = ();
    foreach my $pkt_info (@$pkt_infos){
	push(@{$obj->{'packet-information'}}, _process_packet_info($pkt_info));
    }


    my $record_routes = trim($xp->find('./j:record-route/j:address'));
    $obj->{'record-route'} = ();
    foreach my $rr (@$record_routes){
	push(@{$obj->{'record-route'}}, $rr->textContent);
    }


    return $obj;
}

sub _process_packet_info{
    my $pkt_info = shift;
    my $obj = {};

    my $xp = XML::LibXML::XPathContext->new( $pkt_info );
    $xp->registerNs('j',"http://xml.juniper.net/junos/13.3R1/junos-routing");

    my $prev_hops = $xp->find('./j:previous-hop');
    if($prev_hops->size() > 0){
	$obj->{'previous-hop'} = ();
	foreach my $pre_hop (@$prev_hops){
	    push(@{$obj->{'previous-hop'}}, $pre_hop->textContent);
	}
    }

    my $next_hops = $xp->find('./j:next-hop');
    if($next_hops->size() > 0){
        $obj->{'next-hop'} = ();
        foreach my $next_hop (@$next_hops){
            push(@{$obj->{'next-hop'}}, $next_hop->textContent);
        }
    }

    my $interfaces = $xp->find('./j:interface-name');
    if($interfaces->size() > 0){
        $obj->{'interface-name'} = ();
        foreach my $int (@$interfaces){
            push(@{$obj->{'interface-name'}}, $int->textContent);
        }
    }


    return $obj;
}

sub _process_rsvp_session_egress{
    my $session = shift;

    my $obj = {};

    my $xp = XML::LibXML::XPathContext->new( $session );
    $xp->registerNs('j',"http://xml.juniper.net/junos/13.3R1/junos-routing");
    $obj->{'name'} = trim($xp->findvalue('./j:name'));
    $obj->{'route-count'} = trim($xp->findvalue('./j:route-count'));
    $obj->{'description'} = trim($xp->findvalue('./j:description'));
    $obj->{'destination-address'} = trim($xp->findvalue('./j:destination-address'));
    $obj->{'source-address'} = trim($xp->findvalue('./j:source-address'));
    $obj->{'lsp-state'} = trim($xp->findvalue('./j:lsp-state'));
    $obj->{'lsp-path-type'} = trim($xp->findvalue('./j:lsp-path-type'));
    $obj->{'suggested-lable-in'} = trim($xp->findvalue('./j:suggested-label-in'));
    $obj->{'suggested-label-out'} = trim($xp->findvalue('./j:suggested-label-out'));
    $obj->{'recovery-label-in'} = trim($xp->findvalue('./j:recovery-label-in'));
    $obj->{'recovery-label-out'} = trim($xp->findvalue('./j:recovery-label-out'));
    $obj->{'rsb-count'} = trim($xp->findvalue('./j:rsb-count'));
    $obj->{'resv-style'} = trim($xp->findvalue('./j:resv-style'));
    $obj->{'label-in'} = trim($xp->findvalue('./j:label-in'));
    $obj->{'label-out'} = trim($xp->findvalue('./j:label-out'));
    $obj->{'psb-lifetime'} = trim($xp->findvalue('./j:psb-lifetime'));
    $obj->{'psb-creation-time'} = trim($xp->findvalue('./j:psb-creation-time'));
    $obj->{'lsp-id'} = trim($xp->findvalue('./j:lsp-id'));
    $obj->{'tunnel-id'} = trim($xp->findvalue('./j:tunnel-id'));
    $obj->{'proto-id'} = trim($xp->findvalue('./j:proto-id'));
    $obj->{'adspec'} = trim($xp->findvalue('./j:adspec'));

    my $pkt_infos = $xp->find('./j:packet-information');
    $obj->{'packet-information'} = ();
    foreach my $pkt_info (@$pkt_infos){
        push(@{$obj->{'packet-information'}}, _process_packet_info($pkt_info));
    }

    my $record_routes = trim($xp->find('./j:record-route/j:address'));
    $obj->{'record-route'} = ();
    foreach my $rr (@$record_routes){
        push(@{$obj->{'record-route'}}, $rr->textContent);
    }    

    
    
    return $obj;
}


sub _process_rsvp_session_ingress{
    my $session = shift;
    
    my $obj = {};

    my $xp = XML::LibXML::XPathContext->new( $session );
    $xp->registerNs('j',"http://xml.juniper.net/junos/13.3R1/junos-routing");
    $obj->{'name'} = trim($xp->findvalue('./j:mpls-lsp/j:name'));
    $obj->{'description'} = trim($xp->findvalue('./j:mpls-lsp/j:description'));
    $obj->{'destination-address'} = trim($xp->findvalue('./j:mpls-lsp/j:destination-address'));
    $obj->{'source-address'} = trim($xp->findvalue('./j:mpls-lsp/j:source-address'));
    $obj->{'lsp-state'} = trim($xp->findvalue('./j:mpls-lsp/j:lsp-state'));
    $obj->{'route-count'} = trim($xp->findvalue('./j:mpls-lsp/j:route-count'));
    $obj->{'active-path'} = trim($xp->findvalue('./j:mpls-lsp/j:active-path'));
    $obj->{'lsp-type'} = trim($xp->findvalue('./j:mpls-lsp/j:lsp-type'));
    $obj->{'egress-label-operation'} = trim($xp->findvalue('./j:mpls-lsp/j:egress-label-operation'));
    $obj->{'load-balance'} = trim($xp->findvalue('./j:mpls-lsp/j:load-balance'));
    $obj->{'attributes'} = { 'encoding-type' => trim($xp->findvalue('./j:mpls-lsp/j:mpls-lsp-attributes/j:encoding-type')),
			     'switching-type' => trim($xp->findvalue('./mpls-lsp/j:mpls-lsp-attributes/j:switching-type')),
			     'gpid' => trim($xp->findvalue('./mpls-lsp/j:mpls-lsp-attributes/j:gpid'))},
    $obj->{'revert-timer'} = trim($xp->findvalue('./j:mpls-lsp/j:revert-timer'));
    
    $obj->{'paths'} = ();

    my $paths = $xp->find('./j:mpls-lsp/j:mpls-lsp-path');
    
    foreach my $path (@$paths){
	push(@{$obj->{'paths'}}, _process_lsp_path($path));
    }

    return $obj;
}

sub _process_lsp_path{
    my $path = shift;

    my $xp = XML::LibXML::XPathContext->new( $path );
    $xp->registerNs('j',"http://xml.juniper.net/junos/13.3R1/junos-routing");
    
    my $obj = {};

    $obj->{'name'} = trim($xp->findvalue('./j:name'));
    $obj->{'title'} = trim($xp->findvalue('./j:title'));
    $obj->{'path-state'} = trim($xp->findvalue('./j:path-state'));
    $obj->{'path-active'} = trim($xp->findvalue('./j:path-active'));
    $obj->{'setup-priority'} = trim($xp->findvalue('./j:setup-priority'));

    $obj->{'hold-priority'} = trim($xp->findvalue('./j:hold-priority'));
    $obj->{'smart-optimize-timer'} = trim($xp->findvalue('./j:smart-optimize-timer'));

    #TODO
    #what is cspf-status
    #$obj->{'title'} = trim($xp->find('./j:cspf-status'));
    $obj->{'explicit-route'} = { 'addresses' => [] };
    my $addresses = $xp->find('./j:explicit-route/j:address');

    foreach my $address (@$addresses){
	push(@{$obj->{'explicit-route'}->{'addresses'}}, $address->textContent);
    }

    $obj->{'explicit-route'}->{'explicit-route-type'} = trim($xp->findvalue('./j:explicit-route/j:explict-route-type'));

    $obj->{'received-rro'} = trim($xp->findvalue('./j:received-rro'));
    
    return $obj;
}


sub _edit_config{
    my $self = shift;
    my %params = @_;

    $self->{'logger'}->debug("Sending the following config: " . $params{'config'});

    if(!defined($params{'config'})){
        my $err = "No Configuration specified!";
        $self->set_error($err);
        $self->{'logger'}->error($err);
        return FWDCTL_FAILURE;
    }

    if(!$self->{'connected'}){
        my $err = "Not currently connected to the switch";
        $self->set_error($err);
        $self->{'logger'}->error($err);
        return FWDCTL_FAILURE;
    }
    
    # my %queryargs = ( 'target' => 'candidate' );
    # my $res = $self->{'jnx'}->lock_config(%queryargs);

    my %queryargs = ();
    my $res;

    eval {
        %queryargs = ( 'target' => 'candidate' );
        $self->{'jnx'}->lock_config(%queryargs);
    };
    if ($@) {
        my $err = "$@";
        $self->set_error($err);
        $self->{'logger'}->error($err);
        return FWDCTL_FAILURE;
    }
    if ($self->{'jnx'}->has_error) {
        my $err = "Error attempting to lock config: " . Dumper($self->{'jnx'}->get_first_error());
        $self->set_error($err);
        $self->{'logger'}->error($err);
        return FWDCTL_FAILURE;
    }

    %queryargs = (
        'target' => 'candidate'
        );

    eval {
        $queryargs{'config'} = $params{'config'};
        $res = $self->{'jnx'}->edit_config(%queryargs);
    };
    if ($@) {
        my $err = "$@";
        $self->set_error($err);
        $self->{'logger'}->error($err);
        return FWDCTL_FAILURE;
    }
    if($self->{'jnx'}->has_error){
        my $err = "Error attempting to modify config: " . Dumper($self->{'jnx'}->get_first_error());
        $self->set_error($err);
        $self->{'logger'}->error($err);

        my %queryargs = ( 'target' => 'candidate' );
        $res = $self->{'jnx'}->unlock_config(%queryargs);
        return FWDCTL_FAILURE;
    }

    eval {
        $self->{'jnx'}->commit();
    };
    if ($@) {
        my $err = "$@";
        $self->set_error($err);
        $self->{'logger'}->error($err);
        return FWDCTL_FAILURE;
    }
    if($self->{'jnx'}->has_error){
        my $err = "Error attempting to commit the config: " . Dumper($self->{'jnx'}->get_first_error());
        $self->set_error($err);
        $self->{'logger'}->error($err);

        my %queryargs = ( 'target' => 'candidate' );
        $res = $self->{'jnx'}->unlock_config(%queryargs);
        return FWDCTL_FAILURE;
    }

    eval {
        my %queryargs2 = ( 'target' => 'candidate' );
        $res = $self->{'jnx'}->unlock_config(%queryargs2);
    };
    if ($@) {
        my $err = "$@";
        $self->set_error($err);
        $self->{'logger'}->error($err);
        return FWDCTL_FAILURE;
    }
    if($self->{'jnx'}->has_error){
        my $err = "Error attempting to unlock the config: " . Dumper($self->{'jnx'}->get_first_error());
        $self->set_error($err);
        $self->{'logger'}->error($err);

        my %queryargs = ( 'target' => 'candidate' );
        $res = $self->{'jnx'}->unlock_config(%queryargs);
        return FWDCTL_FAILURE;
    }

    %queryargs = ( 'target' => 'candidate' );
    $res = $self->{'jnx'}->unlock_config(%queryargs);

    return FWDCTL_SUCCESS;
}

sub trim{
    my $s = shift; 
    $s =~ s/^\s+|\s+$//g;
    return $s
}

1;
