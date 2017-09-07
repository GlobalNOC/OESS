#!/usr/bin/perl

use strict;
use warnings;

package OESS::MPLS::Device::Juniper::MX;

use Template;
use Net::Netconf::Manager;
use Data::Dumper;
use XML::Simple;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;
use constant FWDCTL_BLOCKED     => 4;

use GRNOC::Config;

use OESS::Circuit;
use OESS::Database;

use base "OESS::MPLS::Device";

=head2 new

creates a new Juniper MX Device object

=cut

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
    $self->{'logger'}->info("Loading database from $self->{'config'}");

    $self->{'template_dir'} = "juniper/13.3R8";

    $self->{'tt'} = Template->new(INCLUDE_PATH => OESS::Database::SHARE_DIR . "share/mpls/templates/") or die "Unable to create Template Toolkit!";

    my $creds = $self->_get_credentials();
    if(!defined($creds)){
	die "Unable to fetch credentials!";
    }
    $self->{'username'} = $creds->{'username'};
    $self->{'password'} = $creds->{'password'};

    return $self;
}

=head2 disconnect

disconnects from the device

=cut

sub disconnect{
    my $self = shift;

    if (defined $self->{'jnx'}) {
        $self->{'jnx'}->disconnect();
        $self->{'jnx'} = undef;
        $self->{'logger'}->warn("Device was disconnected.");
    } else {
        $self->{'logger'}->info("Device is already disconnected.");
    }

    return 1;
}

=head2 lock

=cut

sub lock {
    my $self = shift;

    if (!$self->connected()){
	$self->{'logger'}->error("Not currently connected to device");
	return;
    }

    my $TOGGLE = bless { 1 => 1 }, 'TOGGLE';

    $self->{'jnx'}->{'methods'}->{'open_configuration'} = {
        private    => $TOGGLE,
    };

    $self->{'jnx'}->open_configuration(private => 1);
    if ($self->{'jnx'}->has_error){
        my $error = $self->{'jnx'}->get_first_error();
        if ($error->{'error_message'} !~ /uncommitted/) {
            $self->{'logger'}->error("Error opening private configuration: " . $error->{'error_message'});
            return;
        }
    }

    my $result = $self->{'jnx'}->get_dom();
    $self->{'logger'}->info(Dumper($result->toString()));

    return 1;
}

=head2 commit

=cut

sub commit {
    my $self = shift;

    if (!$self->connected()){
	$self->{'logger'}->error("Not currently connected to device");
	return;
    }
    
    my $TOGGLE = bless { 1 => 1 }, 'TOGGLE';

    $self->{'jnx'}->{'methods'}->{'commit_configuration'} = { check => $TOGGLE , synchronize => $TOGGLE};

    $self->{'jnx'}->commit_configuration( synchronize => 1);
    if ($self->{'jnx'}->has_error){
        my $error = $self->{'jnx'}->get_first_error();
        $self->{'logger'}->error("Error closing private configuration: " . $error->{'error_message'});
    }

    # TODO Check for an ok

    my $result = $self->{'jnx'}->get_dom();
    $self->{'logger'}->info(Dumper($result->toString()));

    return 1;
}

=head2 unlock

=cut

sub unlock {
    my $self = shift;

    if (!$self->connected()){
	$self->{'logger'}->error("Not currently connected to device");
	return;
    }

    $self->{'jnx'}->{'methods'}->{'close_configuration'} = {};

    $self->{'jnx'}->close_configuration();
    if ($self->{'jnx'}->has_error){
        my $error = $self->{'jnx'}->get_first_error();
        if ($error->{'error_message'} !~ /uncommitted/) {
            $self->{'logger'}->error("Error closing private configuration: " . $error->{'error_message'});
            return 0;
        }
    }

    my $result = $self->{'jnx'}->get_dom();
    $self->{'logger'}->info(Dumper($result->toString()));

    return 1;
}

=head2 get_system_information

gets the systems information

=cut

sub get_system_information{
    my $self = shift;

    if(!$self->connected()){
	$self->{'logger'}->error("Not currently connected to device");
	return;
    }

    my $reply = $self->{'jnx'}->get_system_information();

    if ($self->{'jnx'}->has_error){
        my $error = $self->{'jnx'}->get_first_error();
        $self->{'logger'}->error("Error fetching system information: " . $error->{'error_message'});
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
    $var =~ /(\d+\.\d+\S\d+)/;
    my $root_namespace = "http://xml.juniper.net/junos/".$1.'/';
    $self->{'root_namespace'} = $root_namespace;
    $self->{'logger'}->debug("Root Namespace: " . $root_namespace);

    #also need to fetch the interfaces and find lo0.X
    $reply = $self->{'jnx'}->get_interface_information();
    if($self->{'jnx'}->has_error){
        my $error = $self->{'jnx'}->get_first_error();
        $self->set_error($error->{'error_message'});
        $self->{'logger'}->error("Error fetching interface information: " . $error->{'error_message'});
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

		    foreach my $addr (@{$af_xp->find('./j:interface-address')}){

			my $addrs = $af_xp->find('./j:ifa-local', $addr);
                        foreach my $ad (@$addrs){
                            my $address = trim($ad->textContent);
                            next if(!defined($address));
                            next if $address eq '';
                            next if $address eq '127.0.0.1';

                            $loopback_addr = $address;
                        }

			# Within the interface-address tag there may
			# be an ifa-flags tag. If so the
			# ifaf-preferred flag can be used to select
			# the default loopback address
			my $is_default = $af_xp->exists('./j:ifa-flags/j:ifaf-preferred', $addr);
                        if ($is_default) {
                            last;
                        }

                    }
		}
	    }
	}

	
    }

    $self->{'loopback_addr'} = $loopback_addr;
    return {model => $model, version => $version, os_name => $os_name, host_name => $host_name, loopback_addr => $loopback_addr};
}

=head2 get_routed_lsps

=cut

sub get_routed_lsps{
    my $self = shift;
    my %args = @_;
    my $table = $args{'table'};
    my $circuits = $args{'circuits'};

    if(!$self->connected()){
        $self->{'logger'}->error("Not currently connected to device");
        return;
    }

    my $int_tag_circuit = {};
    #first thing is to take the circuits array and parse it into an interface -> tag -> circuit lookup
    foreach my $circuit (keys %{$circuits}){
        my $ckt = $circuits->{$circuit};
        foreach my $interface (@{$ckt->{'interfaces'}}){
            $int_tag_circuit->{$interface->{'interface'}}->{$interface->{'tag'}} = $circuit;
        }
    }
    
    my $reply = $self->{'jnx'}->get_route_information( table => $table );

    if($self->{'jnx'}->has_error){
        my $error = $self->{'jnx'}->get_first_error();
        $self->set_error($error->{'error_message'});
        $self->{'logger'}->error("Error fetching route table information: " . $error->{'error_message'});
        return;
    }

    my $dom = $self->{'jnx'}->get_dom();
    my $dest_to_lsp = {};

    my $path = $self->{'root_namespace'}."junos-routing";
    my $xp = XML::LibXML::XPathContext->new( $dom );
    $xp->registerNs('x',$dom->documentElement->namespaceURI);
    $xp->registerNs('j',$path);

    my $routes = $xp->findnodes('/x:rpc-reply/j:route-information/j:route-table/j:rt');    
    foreach my $route (@$routes){
	my $dest = $xp->findvalue('./j:rt-destination', $route);
	my $protocol = $xp->findvalue('./j:rt-entry/j:protocol-name',$route);
	my $next_hops = $xp->find('./j:rt-entry/j:nh', $route);

        if ($next_hops->size() == 0) {
            $self->{'logger'}->debug("Skipping rt-entry that has zero next hops in rt-destination $dest");
            next;
        }

	foreach my $nh (@$next_hops){
	    my $lsp_name = $xp->findvalue('./j:lsp-name', $nh);
            if (!defined $lsp_name || $lsp_name eq '') {
                # $lsp_name will probably never be undef; findvalue
                # seems to return an emtpy string even when the
                # lsp-name tag doesn't exist.
                $self->{'logger'}->debug("Skipping rt-entry's next hop as it's missing an lsp-name in rt-destination $dest");
                next;
            }

            if(!defined($dest_to_lsp->{$dest})){
                $dest_to_lsp->{$dest} = ();
            }
            push(@{$dest_to_lsp->{$dest}}, $lsp_name);
	}
    }

    my $circuit_to_lsp = {};

    foreach my $dest (keys %{$dest_to_lsp}){
        
        #determine which type it is
        #either the prefix, the route id or the interface name
        #11537:3019:1:1/96
        ##loopback mechanism not supported after all... use ASN ^^^
        #172.16.0.13:3017:1:1/96
        #xe-2/2/0.666
        
        my $circuit_id;

        if($dest =~ /^(.*)\.(\d+)$/){
            #ok we have an interface!
            my $int = $1;
            my $tag = $2;
            #need to find the interface and vlan combo and get the circuit id!
            if(defined($int_tag_circuit->{$int}) && defined($int_tag_circuit->{$int}->{$tag})){
                $circuit_id = $int_tag_circuit->{$int}->{$tag};
            }
        }else{
            my @parts = split(':',$dest);
            $circuit_id = $parts[1];
            if(!defined($circuits->{$circuit_id})){
                #not a circuit we know about... ignoring
                $circuit_id = undef;
            }
        }

        next if !defined($circuit_id);

        $circuit_to_lsp->{$circuit_id} = $dest_to_lsp->{$dest};
    }

    return $circuit_to_lsp;
}

=head2 get_interfaces

returns a list of current interfaces on the device

=cut

sub get_interfaces{
    my $self = shift;

    if(!$self->connected()){
        $self->{'logger'}->error("Not currently connected to device");
        return;
    }

    my $reply = $self->{'jnx'}->get_interface_information();

    if($self->{'jnx'}->has_error){
        my $error = $self->{'jnx'}->get_first_error();
	$self->set_error($error->{'error_message'});
        $self->{'logger'}->error("Error fetching interface information: " . $error->{'error_message'});
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
    $obj->{'addresses'} = [];

    if (!defined $obj->{'description'} || $obj->{'description'} eq '') {
	$obj->{'description'} = $obj->{'name'};
    } 

    my $families  = $xp->findnodes('./j:logical-interface/j:address-family');
    foreach my $family (@{$families}) {
        my $family_name = trim($xp->findvalue('j:address-family-name', $family));
        if (!defined $family_name || $family_name ne 'inet') {
            next;
        }

        my $local_addresses = $xp->findnodes('j:interface-address/j:ifa-local', $family);
        foreach my $local (@{$local_addresses}) {
            my $addr = trim($local->to_literal());
            push(@{$obj->{'addresses'}}, $addr);
        }
    }

    return $obj;
}

=head2 remove_vlan

removes a vlan via NetConf

=cut

sub remove_vlan{
    my $self = shift;
    my $ckt = shift;

    if(!$self->connected()){
        $self->{'logger'}->error("Not currently connected to device");
        return;
    }

    my $vars = {};
    $vars->{'circuit_name'} = $ckt->{'circuit_name'};
    $vars->{'interfaces'} = [];
    foreach my $i (@{$ckt->{'interfaces'}}) {
        push (@{$vars->{'interfaces'}}, { name => $i->{'interface'},
                                          tag  => $i->{'tag'}
                                        });
    }
    $vars->{'circuit_id'} = $ckt->{'circuit_id'};
    $vars->{'switch'} = {name => $self->{'name'},
                         loopback => $self->{'loopback_addr'}};
    $vars->{'site_id'} = $ckt->{'site_id'};
    $vars->{'paths'} = $ckt->{'paths'};
    $vars->{'a_side'} = $ckt->{'a_side'};
    $vars->{'dest'} = $ckt->{'paths'}->[0]->{'dest'};
    $vars->{'dest_node'} = $ckt->{'paths'}->[0]->{'dest_node'};

    my $output;
    my $remove_template = $self->{'tt'}->process( $self->{'template_dir'} . "/" . $ckt->{'ckt_type'} . "/ep_config_delete.xml", $vars, \$output) or $self->{'logger'}->error( $self->{'tt'}->error());

    $self->{'logger'}->error("Remove Config: " . $output);

    return $self->_edit_config( config => $output );
}

=head2 add_vlan

add a vlan to the juniper

=cut

sub add_vlan{
    my $self = shift;
    my $ckt = shift;
    
    if(!$self->connected()){
	return FWDCTL_FAILURE;
    }

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
    $vars->{'switch'} = {name => $self->{'name'},
			 loopback => $self->{'loopback_addr'}};
    $vars->{'site_id'} = $ckt->{'site_id'};
    $vars->{'a_side'} = $ckt->{'a_side'};
    $self->{'logger'}->error("PATHS: " . Data::Dumper::Dumper($vars->{'paths'}));
    $vars->{'dest'} = $ckt->{'paths'}->[0]->{'dest'};
    $vars->{'dest_node'} = $ckt->{'paths'}->[0]->{'dest_node'};

    if ($self->unit_name_available($vars->{'interface'}->{'name'}, $vars->{'vlan_tag'}) == 0) {
        $self->{'logger'}->error("Unit $vars->{'vlan_tag'} is not available on $vars->{'interface'}->{'name'}");
        return FWDCTL_FAILURE;
    }

    my $ckt_type = $ckt->{'mpls_type'};

    my $output;
    my $add_template = $self->{'tt'}->process( $self->{'template_dir'} . "/" . $ckt->{'ckt_type'} . "/ep_config.xml", $vars, \$output) or  $self->{'logger'}->error($self->{'tt'}->error());
    
    $self->{'logger'}->error("ADD config: " . $output);
    #totally possible our config is now busted :(
    if(!defined($output)){
        return FWDCTL_FAILURE;
    }

    return $self->_edit_config( config => $output );      
}

=head2 get_active_lsp_route

=over 4

=item B<loopback> - Loopback address of the destination node

=item B<table_id> - Name of the routing table to query

=back

Returns the name of the LSP connected to $loopback as defined in $table_id.

    <rpc>
      <get-route-information>
        <logical-system>all</logical-system>
        <table>$table_id</table>
        <destination>$loopback</destination>
        <brief/>
      </get-route-information>
    </rpc>

=cut
sub get_active_lsp_route {
    my $self     = shift;
    my $loopback = shift;
    my $table_id = shift;

    if(!$self->connected()){
        $self->{'logger'}->error("Not currently connected to device");
        return;
    }

    my $api       = $self->{'jnx'};
    my $mgmt_addr = $self->{'mgmt_addr'};

    $api->get_route_information( brief          => '',
                                 destination    => $loopback,
                                 logical_system => 'all',
                                 table          => $table_id );
    if ($api->has_error) {
        $self->{'logger'}->error("get_active_lsp_route: " . $api->get_first_error());
        return undef, 'Could not retreive route information';
    }

    my $dom = $api->get_dom()->toString();
    my $response = XMLin($dom);

    if (!defined $response->{'route-information'}) {
        return undef, 'Could not retreive route information';
    }

    if (!defined $response->{'route-information'}->{'route-table'}) {
        return undef, 'Route table was not defined in route-information';
    }

    my $table = $response->{'route-information'}->{'route-table'};
    my $hops  = $table->{'rt'}->{'rt-entry'}->{'nh'};
    my $lsp   = undef;

    if (ref($hops) eq 'HASH') {
        $lsp = $hops->{'lsp-name'};
        return $lsp, undef;
    }

    for my $hop (@{$hops}) {
        if (!defined $hop->{'selected-next-hop'}) {
            next;
        }

        $lsp = $hop->{'lsp-name'};
        last;
    }

    if (!defined $lsp) {
        return undef, 'Could not find a valid lsp-name';
    }

    return $lsp, undef;
}

=head2 get_active_lsp_path

=over 4

=item B<lsp> - Name of the LSP we're querying

=back

Returns an array of addresses describing the path taken by traffic on
$lsp.

    <rpc>
      <get-mpls-lsp-information>
        <logical-system>all</logical-system>
        <regex>$lsp</regex>
        <detail/>
      </get-mpls-lsp-information>
    </rpc>

=cut
sub get_active_lsp_path {
    my $self = shift;
    my $lsp  = shift;

    if(!$self->connected()){
        $self->{'logger'}->error("Not currently connected to device");
        return;
    }

    my $api = $self->{'jnx'};

    $api->get_mpls_lsp_information( detail         => '',
                                    logical_system => 'all',
                                    regex          => $lsp );
    if ($api->has_error) {
        $self->{'logger'}->error("get_active_lsp_path: " . $api->get_first_error());
        return undef, 'Could not retreive lsp information';
    }

    my $dom = $api->get_dom()->toString();
    my $response = XMLin($dom);

    if (!defined $response->{'mpls-lsp-information'}) {
        return undef, 'Could not retreive lsp information';
    }

    if (!defined $response->{'mpls-lsp-information'}->{'rsvp-session-data'}) {
        return undef, 'Could not find any lsp information';
    }

    my $path = undef;
    for my $session (@{$response->{'mpls-lsp-information'}->{'rsvp-session-data'}}) {
        if (!defined $session->{'rsvp-session'}) {
            next;
        }

        my $active_path = $session->{'rsvp-session'}->{'mpls-lsp'}->{'active-path'};
        if (index($active_path, 'primary') != -1) {
            $path = $session->{'rsvp-session'}->{'mpls-lsp'}->{'mpls-lsp-path'}->{$lsp . '-primary'}->{'explicit-route'}->{'address'};
        } else {
            $path = $session->{'rsvp-session'}->{'mpls-lsp'}->{'mpls-lsp-path'}->{$lsp . '-secondary'}->{'explicit-route'}->{'address'};
        }

        last;
    }

    if (!defined $path) {
        return undef, 'Could not find an mpls-lsp-path';
    }

    if (! (ref($path) eq 'ARRAY')) {
        $path = [$path];
    }

    return ($path, undef);
}

=head2 get_default_paths

=over 4

=item B<$loopback_addresses> - An array of loopback ip addresses

=back

Determine the default forwarding path between this node and each ip
address provided in $loopback_addresses.

=cut
sub get_default_paths {
    my $self = shift;
    my $loopback_addresses = shift;

    if(!$self->connected()){
        $self->{'logger'}->error("Not currently connected to device");
        return;
    }

    my $name   = undef;
    my $path   = undef;
    my $err    = undef;
    my $result = {};

    for my $addr (@{$loopback_addresses}) {
        ($name, $err) = $self->get_active_lsp_route($addr, 'inet.3');
        if (defined $err) {
            $self->{'logger'}->debug($err);
            next;
        }

        ($path, $err) = $self->get_active_lsp_path($name);
        if (defined $err) {
            $self->{'logger'}->debug($err);
            next;
        }

	$result->{$addr} = {};
	$result->{$addr}->{'name'} = $name;
	$result->{$addr}->{'path'} = $path;
    }

    return $result;
}

=head2 xml_configuration( $ckts )

Returns configuration as an xml string based on $ckts, which is an array of
OESS::Circuit objects. It also takes a string of Removes which will be specified before the adds.

=cut
sub xml_configuration {
    my $self = shift;
    my $ckts = shift;
    my $remove = shift;

    my $configuration = '<configuration>';
    $configuration .= $remove;
    foreach my $ckt (@{$ckts}) {
        # The argument $ckts is passed in a generic form. This should be
        # converted to work with the template.
        my $xml;
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
        $vars->{'switch'} = { name => $self->{'name'},
                              loopback => $self->{'loopback_addr'} };

        $vars->{'dest'} = $ckt->{'paths'}->[0]->{'dest'};
        $vars->{'dest_node'} = $ckt->{'paths'}->[0]->{'dest_node'};

        $vars->{'site_id'} = $ckt->{'site_id'};
        $vars->{'paths'} = $ckt->{'paths'};
        $vars->{'a_side'} = $ckt->{'a_side'};
        #$self->{'logger'}->debug(Dumper($vars));

        if ($ckt->{'state'} eq 'active') {
            $self->{'tt'}->process($self->{'template_dir'} . "/" . $ckt->{'ckt_type'} . "/ep_config.xml", $vars, \$xml);
        } else {
            # The remove case is now handled in get_config_to_remove
        }

        $xml =~ s/<configuration>//g;
        $xml =~ s/<\/configuration>//g;
        $configuration = $configuration . $xml;
    }
    $configuration = $configuration . '</configuration>';

    return $configuration;
}

=head2 get_device_circuit_infos

I do not believe this is used... 

=cut
sub get_device_circuit_infos {
    my $self = shift;

    if(!$self->connected()){
        $self->{'logger'}->error("Not currently connected to device");
        return;
    }

    my $result = {};

    my $res = $self->{'jnx'}->get_configuration( database => 'committed', format => 'xml' );
    if ($self->{'jnx'}->has_error) {
        my $error = $self->{'jnx'}->get_first_error();
	$self->set_error($error->{'error_message'});
        $self->{'logger'}->error("Error getting conf from MX: " . $error->{'error_message'});
        return;
    }

    my $dom = $self->{'jnx'}->get_dom();
    my $interfaces = $dom->getElementsByTagName('interface');

    foreach my $interface (@{$interfaces}) {
        my $units = $interface->getElementsByTagName('unit');
        foreach my $unit (@{$units}) {
            # Based on unit descriptions we can determine if this unit
            # represents a circuit that should be verified. Units to be
            # selected are in the form 'OESS <type> <id>'.
            # Ex.
            # OESS L2VPN 3006

            my $desc = $unit->getElementsByTagName('description');
            if ($desc->size() == 0) {
                next;
            }

            my $text = $desc->[0]->textContent();
            if ($text !~ /^OESS/) {
                # Units with descriptions starting with anything other
                # than 'OESS' are not circuit related; These may be
                # manually defined for other purposes, so we ignore.
                next;
            }

            my ($oess, $type, $id) = split(/ /, $text);
            $result->{$id} = { circuit_id => $id, type => $type };
        }
    }
    return $result;
}

=head2 get_config_to_remove

attempts to find parts of the config to remove, unfortunatly very templates specific

=cut

sub get_config_to_remove{
    my $self = shift;
    my %params = @_;
    my $circuits = $params{'circuits'};

    if(!$self->connected()){
        $self->{'logger'}->error("Not currently connected to device");
        return;
    }

    my $res = $self->{'jnx'}->get_configuration( database => 'committed', format => 'xml' );
    if ($self->{'jnx'}->has_error) {
        my $error = $self->{'jnx'}->get_first_error();
        if ($error->{'error_message'} !~ /uncommitted/) {
            $self->{'logger'}->error("Error getting conf from MX: " . $error->{'error_message'});
            return;
        }
    }

    my $dom = $self->{'jnx'}->get_dom();

    #so there are a few chunks of the config we need to check for
    #interface sub unit
    #mpls label switch path
    #mpls paths
    #connections remote interface switch
    #routing instances

    my $delete = "";
    my $routing_instance_dels = "";
    my $xp = XML::LibXML::XPathContext->new($dom);
    $xp->registerNs("base", $dom->documentElement->namespaceURI);
    $xp->registerNs('c', 'http://xml.juniper.net/xnm/1.1/xnm');

    my $routing_instances = $xp->find( '/base:rpc-reply/c:configuration/c:routing-instances/c:instance');
    foreach my $ri (@$routing_instances){
	my $name = $xp->findvalue( './c:name', $ri );
	if($name =~ /^OESS/){
	    #check to see if is currently active circuit
	    $name =~ /OESS\-\S+\-(\d+)/;
	    my $circuit_id = $1;
	    if(!$self->_is_active_circuit($circuit_id, $circuits)){
		$routing_instance_dels .= "<instance operation='delete'><name>$name</name></instance>";
	    }
	}
    }

    if($routing_instance_dels ne ''){
	$delete .= "<routing-instances>$routing_instance_dels</routing-instances>";
    }

    my $interfaces = $xp->find( '/base:rpc-reply/c:configuration/c:interfaces/c:interface');
    my $interfaces_del = "";
    foreach my $interface (@$interfaces){
	my $int_name = $xp->findvalue( './c:name', $interface);
	my $units = $xp->find( './c:unit', $interface);
	my $int_del = "<interface><name>" . $int_name . "</name>";
	my $has_dels = 0;
	foreach my $unit (@$units){
	    my $description = $xp->findvalue( './c:description', $unit );
	    if($description =~ /^OESS/){
		$description =~ /OESS\-\w+\-(\d+)/;
		my $circuit_id = $1;
		if(!$self->_is_active_circuit($circuit_id, $circuits)){
		    my $unit_name = $xp->findvalue( './c:name', $unit);
		    $int_del .= "<unit operation='delete'><name>" . $unit_name . "</name></unit>";
		    $has_dels = 1;
		}
	    }
	}
	$int_del .= "</interface>";
	if($has_dels){
	    $interfaces_del .= $int_del;
	}
    }

    if($interfaces_del ne ''){
	$delete .= "<interfaces>$interfaces_del</interfaces>";
    }

    my $lsp_dels = "";
    my $mpls_lsps = $xp->find( '/base:rpc-reply/c:configuration/c:protocols/c:mpls/c:label-switched-path');    
    foreach my $lsp (@{$mpls_lsps}){
	my $name = $xp->findvalue( './c:name', $lsp);
	if($name =~ /^OESS/){
	    $name =~ /OESS\-\w+\-\d+\-\d+\-LSP\-(\d+)/;
	    my $circuit_id = $1;
	    if(!$self->_is_active_circuit($circuit_id, $circuits)){
		$lsp_dels .= "<label-switched-path operation='delete'><name>" . $name . "</name></label-switched-path>";
	    }
	}
    }
    my $path_dels = "";
    my $paths = $xp->find( '/base:rpc-reply/c:configuration/c:protocols/c:mpls/c:path');
    foreach my $path (@{$paths}){
	my $name = $xp->findvalue( './c:name', $path);
        if($name =~ /^OESS/){
	    $name =~ /OESS\-\w+\-\w+\-\w+\-LSP\-(\d+)/;
	    my $circuit_id = $1;
            if (!$self->_is_active_circuit($circuit_id, $circuits)) {
                $path_dels .= "<path operation='delete'><name>" . $name . "</name></path>";
            } else {
		# Active circuits with a 'strict' or manually defined
		# path should check their path for extra hops.
		my $strict_path = $self->_get_strict_path($circuit_id, $circuits);
		if (!defined $strict_path) {
		    next;
		}

		my $path_list_dels = "";
		my $path_lists = $xp->find('./c:path-list', $path);

		foreach my $path_list (@$path_lists) {
		    my $path_list_name = $xp->findvalue('./c:name', $path_list);
		    $self->{'logger'}->info('===' . $path_list_name);

		    if (!defined $strict_path->{$path_list_name}) {
			$self->{'logger'}->info("===Adding $path_list_name to path-list delete");
		     	$path_list_dels .= "<path-list operation='delete'><name>" . $path_list_name . "</name></path-list>";
		    }
		}

		if ($path_list_dels ne '') {
		    $path_dels .= "<path><name>" . $name . "</name>" . $path_list_dels . "</path>";
		}
	    }
        }
    }

    if($lsp_dels ne '' || $path_dels ne ''){
	$delete .= "<protocols><mpls>";
	if($lsp_dels ne ''){
	    $delete .= $lsp_dels;
	}
	
	if($path_dels ne ''){
	    $delete .= $path_dels;
	}
	$delete .= "</mpls></protocols>";
    }


    my $ris_dels = "";

    my $remote_interface_switches = $xp->find( '/base:rpc-reply/c:configuration/c:protocols/c:connections/c:remote-interface-switch');
    
    foreach my $ris (@{$remote_interface_switches}){
	my $name = $xp->findvalue( './c:name', $ris);
        if($name =~ /^OESS/){
	    $name =~ /OESS\-\S+\-(\d+)/;
	    my $circuit_id = $1;
	    #figure out the right bit!
	    if(!$self->_is_active_circuit($circuit_id, $circuits)){
                $ris_dels .= "<remote-interface-switch operation='delete'><name>" . $name . "</name></remote-interface-switch>";
            }
        }
    }

    if($ris_dels ne ''){
	$delete .= "<protocols><connections>" . $ris_dels . "</connections></protocols>";
    }
    
    return $delete;
}

sub _get_strict_path{
    my $self = shift;
    my $circuit_id = shift;
    my $circuits = shift;

    if (!defined $circuit_id) {
	$self->{'logger'}->error("Missing argument circuit_id");
	return undef;
    }

    my $paths = $circuits->{$circuit_id}->{'paths'};
    foreach my $path (@$paths) {
	if ($path->{'mpls_path_type'} ne 'strict') {
	    next;
	}

	my $hops   = $path->{'path'};
	my $result = {};
	foreach my $hop (@$hops) {
	    $result->{$hop} = 1;
	}
	return $result;
    }

    return undef;
}

sub _is_active_circuit{
    my $self = shift;
    my $circuit_id = shift;
    my $circuits = shift;
    if(!defined($circuit_id)){
	$self->{'logger'}->error("Unable to find the circuit ID");
	return 0;
    }

    if(defined($circuits->{$circuit_id}) && ($circuits->{$circuit_id}->{'state'} eq 'active')){
	return 1;
    }

    $self->{'logger'}->error("Circuit id: " . $circuit_id . " was not found as an active circuit... scheduling for removal");
    return 0;
    
}


=head2 get_device_circuit_ids

this should no longer be used...

=cut

sub get_device_circuit_ids {
    my $self = shift;

    if(!$self->connected()){
        $self->{'logger'}->error("Not currently connected to device");
        return;
    }

    my $result = [];

    my $res = $self->{'jnx'}->get_configuration( database => 'committed', format => 'xml' );
    if ($self->{'jnx'}->has_error) {
        my $error = $self->{'jnx'}->get_first_error();
	$self->set_error($error->{'error_message'});
        $self->{'logger'}->error("Error getting conf from MX: " . $error->{'error_message'});
        return;
    }

    my $dom = $self->{'jnx'}->get_dom();
    my $interfaces = $dom->getElementsByTagName('interface');

    foreach my $interface (@{$interfaces}) {
        my $units = $interface->getElementsByTagName('unit');
        foreach my $unit (@{$units}) {
            # Based on unit descriptions we can determine if this unit
            # represents a circuit that should be verified. Units to be
            # selected are in the form 'OESS <type> <id>'.
            # Ex.
            # OESS L2VPN 3006

            my $desc = $unit->getElementsByTagName('description');
            if ($desc->size() == 0) {
                next;
            }

            my $text = $desc->[0]->textContent();
            if ($text !~ /^OESS/) {
                # Units with descriptions starting with anything other
                # than 'OESS' are not circuit related; These may be
                # manually defined for other purposes, so we ignore.
                next;
            }

            $self->{'logger'}->info("get_device_circuit_ids: $text");
            my ($oess, $type, $id) = split(/-/, $text);
            push(@{$result}, $id);
        }
    }
    return $result;
}


=head2 required_modifications

I don't believe this is used...

=cut
sub required_modifications {
    my $self = shift;
    my $circuits = shift;
    my $circuit_infos = shift;

    if(!$self->connected()){
        $self->{'logger'}->error("Not currently connected to device");
        return;
    }

    my $result = [];

    foreach my $id (keys %{$circuits}) {
        if (!defined $circuit_infos->{$id}) {
            my $addition = $circuits->{$id};
            $addition->{'action'} = 'add';

            push(@{$result}, $addition);
        }
    }

    foreach my $id (keys %{$circuit_infos}) {
        if (!defined $circuits->{$id}) {
            my $deletion = $circuits->{$id};
            $deletion->{'action'} = 'delete';

            push(@{$result}, $deletion);
        }
    }

    return $result;
}

=head2 get_device_diff

Returns and stores a human readable diff for display to users.

=cut
sub get_device_diff {
    my $self = shift;
    my $conf = shift;

    if(!$self->connected()){
        $self->{'logger'}->error("Not currently connected to device");
        return;
    }

    my %queryargs = ('target' => 'candidate');
    $queryargs{'config'} = $conf;

    my $ok = $self->lock();

    my $res = $self->{'jnx'}->edit_config(%queryargs);
    if ($self->{'jnx'}->has_error) {
	my $dom = $self->{'jnx'}->get_dom();
	$self->{'logger'}->error($dom->toString());
        my $error = $self->{'jnx'}->get_first_error();
        if ($error->{'error_message'} !~ /uncommitted/) {
            $self->{'logger'}->error("Error getting device diff: " . $error->{'error_message'});
            $self->disconnect();
            return;
        }
    }

    # According to docs format isn't considered when used with
    # compare. However in 15.1F6-S6.4 it is; I would expect this to
    # continue in later Junos versions.
    my $configcompare = $self->{'jnx'}->get_configuration( compare => "rollback", rollback => "0", format => "text" );
    if ($self->{'jnx'}->has_error) {
        my $error = $self->{'jnx'}->get_first_error();

        if ($error->{'error_message'} !~ /uncommitted/) {
            $self->set_error($error->{'error_message'});

            $self->{'logger'}->error("Error getting diff from MX: " . $error->{'error_message'});
            $res = $self->{'jnx'}->discard_changes();

            $ok = $self->unlock();
            return;
        }
    }

    my $dom = $self->{'jnx'}->get_dom();
    $self->{'diff_text'} = $dom->getElementsByTagName('configuration-output')->string_value();

    $ok = $self->unlock();

    if ($self->{'diff_text'} eq "\n") {
        # In some cases a diff containing only an empty line may be
        # received. This case should be ignored.
        $self->{'diff_text'} = '';
    }


    return $self->{'diff_text'};
}

=head3 _large_diff( $diff )

Returns 1 if $diff requires manual approval.

=cut
sub _large_diff {
    my $self = shift;
    my $diff = shift;

    my $len = length($diff);
    if ($len > 500) {
        return 1;
    }
    return 0;
}

=head2 diff

Do a diff between $ckts and the circuits on this device.

=cut
sub diff {
    my $self = shift;
    my %params = @_;

    my $circuits = $params{'circuits'};
    my $force_diff = $params{'force_diff'};
    my $remove = $params{'remove'};

    if(!$self->connected()){
        $self->{'logger'}->error("Not currently connected to device");
        return FWDCTL_FAILURE;
    }

    $self->{'logger'}->info("Calling MX.diff");

    my @circuits;
    foreach my $ckt_id (keys (%{$circuits})){
	push(@circuits, $circuits->{$ckt_id});
    }

    my $configuration = $self->xml_configuration(\@circuits, $remove);
    if ($configuration eq '<configuration></configuration>') {
        $self->{'logger'}->info('No diff required at this time.');
        return FWDCTL_SUCCESS;
    }

    $self->{'logger'}->debug(Dumper($configuration));

    if ($force_diff) {
        $self->{'logger'}->info('Force diff was initiated. Starting installation.');
        $self->{'pending_diff'} = 0;
        return $self->_edit_config(config => $configuration);
    }

    # Check the size of the diff to see if verification is required for
    # the changes to be applied. $diff is a human readable diff.
    my $diff = $self->get_device_diff($configuration);
    if (!defined $diff || $diff eq '') {
        $self->{'logger'}->info('No diff required at this time.');
        return FWDCTL_FAILURE;
    }

    if ($self->_large_diff($diff)) {
        # It may be possible that a large diffs is considered untrusted.
        # If so, block until the diff has been approved.
        $self->{'logger'}->info('Large diff detected. Waiting for approval before installation.');
        $self->{'pending_diff'} = 1;
        return FWDCTL_BLOCKED;
    }

    $self->{'logger'}->info("Diff requires no approval. Starting installation.");

    return $self->_edit_config(config => $configuration);
}

=head2 get_diff_text

Returns a human readable diff between $circuits and this Device's
configuration, or undef when no diff is required. Takes an array of
circuits to build the current configuration, and a remove string of
XML to be removed from the device.

=cut
sub get_diff_text {
    my $self = shift;
    my %params = @_;
    my $circuits = $params{'circuits'};
    my $remove = $params{'remove'};
    if(!$self->connected()){
        $self->{'logger'}->error("Not currently connected to device");
        return;
    }
    
    $self->{'logger'}->debug("Calling MX.get_diff_text");

    my @circuits;
    foreach my $ckt_id (keys (%{$circuits})){
        push(@circuits, $circuits->{$ckt_id});
    }

    my $configuration = $self->xml_configuration(\@circuits, $remove );
    if ($configuration eq '<configuration></configuration>') {
        return undef;
    }

    my $diff = $self->get_device_diff($configuration);
    if ($diff eq '') {
        # Handles case where a device returns an empty string
        return undef;
    }

    return $diff;
}

=head2 unit_name_available

Returns 0 if the unit name already exists on the specified interface or
another error occurs; Otherwise 1 is returned for success.

=cut
sub unit_name_available {
    my $self           = shift;
    my $interface_name = shift;
    my $unit_name      = shift;

    if(!$self->connected()){
        $self->{'logger'}->error("Not currently connected to device");
        return;
    }

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
                                          'port' => 830,
                                          'debug_level' => 0 );
    };

    if ($@ || !$jnx) {
        my $err = "Could not connect to $self->{'mgmt_addr'}. Connection timed out.";
        $self->set_error($err);
        $self->{'logger'}->error($err);
        return 0;
    }

    $self->{'jnx'} = $jnx;

    # Gather basic system information needed later!
    my $verify = $self->verify_connection();
    if ($verify != 1) {
        my $err = "Failure while verifying $self->{'mgmt_addr'}. Connection closed.";
        $self->set_error($err);
        $self->{'logger'}->error($err);
        return 0;
    }

    # Configures parameters for several methods
    my $ATTRIBUTE = bless {}, 'ATTRIBUTE';
    my $TOGGLE = bless { 1 => 1 }, 'TOGGLE';

    $self->{'jnx'}->{'methods'}->{'get_configuration'} = { format   => $ATTRIBUTE,
                                                           compare  => $ATTRIBUTE,
                                                           changed  => $ATTRIBUTE,
                                                           database => $ATTRIBUTE,
                                                           rollback => $ATTRIBUTE };

    $self->{'jnx'}->{'methods'}->{'get_mpls_lsp_information'} = {
        detail    => $TOGGLE,
        extensive => $TOGGLE,
    };

    $self->{'logger'}->info("Connected to device!");
    return 1;
}


=head2 connected

returns the state if the device is currently connected or not

=cut

sub connected {
    my $self = shift;

    return 0 if(!defined($self->{'jnx'}));
		
    if (defined $self->{'jnx'}->{'conn_obj'} && $self->{'jnx'}->has_error) {
        my $error = $self->{'jnx'}->get_first_error();
        $self->{'logger'}->error("Error: " . $error->{'error_message'});
    }

    if(defined($self->{'jnx'}->{'conn_obj'})){
	$self->{'logger'}->debug("Connection state is up");
	return 1;
    }else{
	$self->{'logger'}->warn("Connection state is down");
	return 0;
    }
}


=head2 verify_connection

    verify the connection

=cut

sub verify_connection{
    #gather basic system information needed later, and make sure it is what we expected / are prepared to handle
    #
    my $self = shift;

    if(!$self->connected()){
        $self->{'logger'}->error("Not currently connected to device");
        return 0;
    }

    my $sysinfo = $self->get_system_information();
    if (($sysinfo->{"os_name"} eq "junos") && ($sysinfo->{"version"} eq "13.3R1.6" || $sysinfo->{"version"} eq '15.1F6-S6.4')){
	# print "Connection verified, proceeding\n";
	return 1;
    }
    else {
	$self->{'logger'}->error("Network OS and / or version is not supported");
	return 0;
    }
    
}

=head2 get_isis_adjacencies

    returns the current isis adjacencies on the box

=cut

sub get_isis_adjacencies{
    my $self = shift;

    if(!$self->connected()){
        $self->{'logger'}->error("Not currently connected to device");
        return;
    }

    $self->{'logger'}->error("INSIDE GET_ISIS_ADJACENCIES");
    
    if(!defined($self->{'jnx'}->{'methods'}->{'get_isis_adjacency_information'})){
	my $TOGGLE = bless { 1 => 1 }, 'TOGGLE';
	$self->{'jnx'}->{'methods'}->{'get_isis_adjacency_information'} = { detail => $TOGGLE};
    }

    $self->{'jnx'}->get_isis_adjacency_information( detail => 1 );

    my $xml = $self->{'jnx'}->get_dom();
    $self->{'logger'}->debug("ISIS: " . $xml->toString());
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

=head2 get_LSPs

returns the current MPLS LSPs on the box

=cut

sub get_LSPs{
    my $self = shift;

    if(!$self->connected()){
        $self->{'logger'}->error("Not currently connected to device");
        return;
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

=head2 get_lsp_paths

implementation of OESS::MPLS::Device::get_lsp_paths

=cut

sub get_lsp_paths{
    my $self = shift;

    if(!$self->connected()){
        $self->{'logger'}->error('Not currently connected to device');
        return;
    }

    my $res = $self->{'jnx'}->get_mpls_lsp_information(extensive => 1);
    my $dom = $self->{'jnx'}->get_dom();

    # Extract the link IP addresses out of the response
    my $xp = XML::LibXML::XPathContext->new($dom);

    $xp->registerNs('root', $dom->documentElement->namespaceURI);
    $xp->registerNs('r', $self->{'root_namespace'} . 'junos-routing');

    my $ingress_lsps = $xp->findnodes('/root:rpc-reply/r:mpls-lsp-information/r:rsvp-session-data[r:session-type="Ingress"]/r:rsvp-session/r:mpls-lsp');
    my $lsp_routes   = {};

    foreach my $ingress_lsp (@{$ingress_lsps}) {
        my $name  = $xp->findvalue('./r:name', $ingress_lsp);
        my $paths = $xp->find('./r:mpls-lsp-path', $ingress_lsp);

        foreach my $path (@{$paths}) {
            if ($xp->exists('./r:path-active', $path)) {
                my $next_hops = $xp->find('./r:explicit-route/r:address', $path);

                foreach my $nh (@{$next_hops}) {
                    push(@{$lsp_routes->{$name}}, $nh->textContent);
                }
            }
        }
    }

    return $lsp_routes;
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

    if(!$self->connected()){
        my $err = "Not currently connected to the switch";
        $self->set_error($err);
        $self->{'logger'}->error($err);
        return FWDCTL_FAILURE;
    }

    my %queryargs = ();
    my $res;

    $self->{'logger'}->debug("Locking config");

    my $ok = $self->lock();

    $self->{'logger'}->debug("Locked config!");

    %queryargs = (
        'target' => 'candidate'
        );

    eval {
	$self->{'logger'}->debug("About to send config: " . $params{'config'});
        $queryargs{'config'} = $params{'config'};
        $res = $self->{'jnx'}->edit_config(%queryargs);
	$self->{'logger'}->debug("Success Editing config!");
	my $result = $self->{'jnx'}->get_dom();
	$self->{'logger'}->info(Dumper($result->toString()));
    };
    if ($@) {
        my $err = "$@";
        $self->set_error($err);
        $self->{'logger'}->error($err);
	$self->{'logger'}->debug("Unlocking config");
        $res = $self->{'jnx'}->unlock_config();
	$self->{'logger'}->debug("Config unlocked");
        return FWDCTL_FAILURE;
    }
    if($self->{'jnx'}->has_error){
        my $error = $self->{'jnx'}->get_first_error();
        if ($error->{'error_message'} !~ /uncommitted/) {
            my $err = "Error attempting to edit config: " . $error->{'error_message'};
            $self->set_error($err);
            $self->{'logger'}->error($err);
#	    $self->{'logger'}->debug("Unlocking config");
#            $self->unlock();
#	    $self->{'logger'}->debug("Config unlocked!");
#            return FWDCTL_FAILURE;
        }
    }

    $self->{'logger'}->debug("Commiting!");

    $ok = $self->commit();

    $self->{'logger'}->debug("Commit complete!");

    $ok = $self->unlock();

    $self->{'logger'}->debug("Unlock complete!");

    return FWDCTL_SUCCESS;
}

=head2 trim

trims off white space

=cut

sub trim{
    my $s = shift; 
    $s =~ s/^\s+|\s+$//g;
    return $s
}

1;
