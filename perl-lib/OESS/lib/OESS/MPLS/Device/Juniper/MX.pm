#!/usr/bin/perl

use strict;
use warnings;

package OESS::MPLS::Device::Juniper::MX;

use Template;
use Net::Netconf::Manager;
use Data::Dumper;
use Log::Log4perl;
use XML::Simple;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;
use constant FWDCTL_BLOCKED     => 4;

use GRNOC::Config;

use OESS::Circuit;
use OESS::Database;
use NetAddr::IP;
use base "OESS::MPLS::Device";

=head1 package OESS::MPLS::Device::Juniper::MX

    use OESS::MPLS::Device::Juniper::MX;

=head2 new

    my $mx = OESS::MPLS::Device::Juniper::MX->new(
      config => '/etc/oess/database.xml',
      loopback_addr => '127.0.0.1',
      mgmt_addr     => '192.168.1.1',
      name          => 'demo.grnoc.iu.edu',
      node_id       => 1
    );

new creates a Juniper MX device object. Use methods on this object to
communicate with a device on the network.

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

    $self->{'tt'} = Template->new(INCLUDE_PATH => OESS::Database::SHARE_DIR . "share/mpls/templates/:./share/mpls/templates/", RELATIVE => 1) or die "Unable to create Template Toolkit!";

    my $creds = $self->_get_credentials();
    if(!defined($creds)){
	die "Unable to fetch credentials!";
    }
    $self->{'username'} = $creds->{'username'};
    $self->{'password'} = $creds->{'password'};

    $self->{'supported_firmware'} = $self->_get_supported_firmware();
    return $self;
}

=head2 _get_firmware

=cut
sub _get_supported_firmware {
    my $self = shift;

    my $xml = XMLin('/etc/oess/firmware.xml');
    return $xml->{version};
}

=head2 disconnect

    disconnect();

disconnect calls disconnect on this MX's connection object and then
deletes it.

=cut
sub disconnect{
    my $self = shift;
    
    if (!defined $self->{'jnx'}) {
        return 1;
    }

    $self->{'jnx'}->disconnect();
    $self->{'jnx'} = undef;
    $self->{'logger'}->warn("Device was disconnected.");

    return 1;
}

=head2 get_response

    my ($xml, $dom, $err) = get_response();

get_response parses the last response received via
C<$self-E<gt>{jnx}>. It returns the XML object, the XML as a hash, and
the first error received if one was encountered.

=cut
sub get_response {
    my $self = shift;

    my $xml = $self->{jnx}->get_dom();
    my $dom = XMLin($xml->toString());
    my $err = undef;

    my $errors = [];
    if (defined $dom->{'commit-results'} && $dom->{'commit-results'}->{'rpc-error'}) {
        $errors = $dom->{'commit-results'}->{'rpc-error'};
    }

    if (defined $dom->{'rpc-error'}) {
        $errors = $dom->{'rpc-error'};
    }

    if (ref($errors) eq 'HASH') {
        $errors = [$errors];
    }

    if (defined $dom->{'commit-results'} && $dom->{'commit-results'}->{'routing-engine'}) {
        my $re0 = $dom->{'commit-results'}->{'routing-engine'}->{'re0'};
        if (defined $re0 && defined $re0->{'rpc-error'}) {
            push @$errors, $re0->{'rpc-error'};
        }
        my $re1 = $dom->{'commit-results'}->{'routing-engine'}->{'re1'};
        if (defined $re1 && defined $re1->{'rpc-error'}) {
            push @$errors, $re1->{'rpc-error'};
        }
    }

    foreach my $error (@{$errors}) {
        my $lvl = $error->{'error-severity'};
        my $msg = $error->{'error-message'};
        $msg =~ s/^\s+|\s+$//g; # python >> str.strip()

        if ($lvl eq 'warning') {
            $self->{'logger'}->warn($msg);
        } else {
            # error-severity of 'error' is considered a stop
            # condition. Return the first error encountered.
            $err = $msg;
            last;
        }
    }

    return ($xml, $dom, $err);
}

=head2 lock

    my $ok = lock();

lock attempts to open this device's configuration in private mode, and
returns C<1> on success. The unlock subroutine should always be called
after lock.

=cut
sub lock {
    my $self = shift;

    if (!$self->connected()) {
        $self->{'logger'}->error("Not currently connected to device");
        return 0;
    }

    eval {
        $self->{'jnx'}->open_configuration(private => 1);

        my ($xml, $dom, $err) = $self->get_response();
        if (defined $err) {
            $self->{logger}->error($xml->toString());
            die $err;
        }
        $self->{logger}->debug($xml->toString());
    };
    if ($@) {
        $self->{logger}->error("Error locking configuration: $@");
        return 0;
    }

    return 1;
}

=head2 commit

    my $ok = commit();

commit attempts to copy the device's private configuration to the
running configuration. commit returns C<1> on success.

=cut
sub commit {
    my $self = shift;

    if (!$self->connected()) {
        $self->{'logger'}->error("Not currently connected to device");
        return 0;
    }

    eval {
        $self->{'jnx'}->commit_configuration(synchronize => 1);

        my ($xml, $dom, $err) = $self->get_response();
        if (defined $err) {
            $self->{logger}->error($xml->toString());
            die $err;
        }
        $self->{logger}->debug($xml->toString());
    };
    if ($@) {
        $self->{'logger'}->error("Error commiting configuration: $@");
        return 0;
    }

    return 1;
}

=head2 unlock

    my $ok = unlock();

unlock attempts to unlock this device's configuration and returns C<1>
on success. This subroutine should always be called after lock.

=cut
sub unlock {
    my $self = shift;

    if (!$self->connected()) {
	$self->{'logger'}->error("Not currently connected to device");
	return 0;
    }

    eval {
        $self->{'jnx'}->close_configuration();

        my ($xml, $dom, $err) = $self->get_response();
        if (defined $err) {
            $self->{logger}->error($xml->toString());
            die $err;
        }
        $self->{logger}->debug($xml->toString());
    };
    if ($@) {
        $self->{'logger'}->error("Error commiting configuration: $@");
        return 0;
    }

    return 1;
}

=head2 get_system_information

    my ($info, $err) = get_system_information();

get_system_information returns an object containing information about
the connected device.

B<Result>

    {
      host_name     => 'vmx-r0'
      loopback_addr => '172.16.0.1'
      model         => 'vmx'
      os_name       => 'junos'
      version       => '15.1F6.9'
      major_rev     => '15'
    }

=cut
sub get_system_information{
    my $self = shift;

    if (!$self->connected) {
        return (undef, "Not currently connected to device");
    }

    my $reply = $self->{'jnx'}->get_system_information();
    if ($self->{'jnx'}->has_error) {
        my $error = $self->{'jnx'}->get_first_error();
        return (undef, "Error fetching system information: $error->{error_message}");
    }

    my $system_info = $self->{'jnx'}->get_dom();
    my $root_ns     = $system_info->documentElement()->namespaceURI();
    $self->{logger}->debug("Using root XML namespace $root_ns.");

    my $xp = XML::LibXML::XPathContext->new($system_info);
    $xp->registerNs('x', $root_ns);

    # Eg. http://xml.juniper.net/junos/15.1I0/junos
    my $junos_ns = $xp->lookupNs('junos');
    $self->{'root_namespace'} = substr($junos_ns, 0, -5);
    $self->{logger}->debug("Using JUNOS XML namespace $self->{'root_namespace'}.");

    my $host_name = $xp->findvalue('/x:rpc-reply/x:system-information/x:host-name');
    my $model =     $xp->findvalue('/x:rpc-reply/x:system-information/x:hardware-model');
    my $os_name =   $xp->findvalue('/x:rpc-reply/x:system-information/x:os-name');
    my $version =   $xp->findvalue('/x:rpc-reply/x:system-information/x:os-version');
    my $major_rev = $version;
    $major_rev =~ s/^(\d+)\..+$/$1/;
    $self->{logger}->info("Using firmware version $version.");

    #also need to fetch the interfaces and find lo0.X
    $reply = $self->{'jnx'}->get_interface_information();
    if ($self->{'jnx'}->has_error) {
        my $error = $self->{'jnx'}->get_first_error();
        $self->set_error($error->{'error_message'});
        return (undef, "Error fetching interface information: $error->{error_message}");
    }

    my $interfaces = $self->{'jnx'}->get_dom();
    my $path = $self->{'root_namespace'}."junos-interface";
    $xp = XML::LibXML::XPathContext->new($interfaces);
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
    $self->{'major_rev'} = $major_rev;

    my $result = {
        host_name     => $host_name,
        loopback_addr => $loopback_addr,
        os_name       => $os_name,
        model         => $model,
        version       => $version,
    };
    return ($result, undef);
}

=head2 get_routed_lsps

    my $circuits_to_lsps = get_routed_lsps(
      table    => 'bgp.l2vpn.0',
      circuits => {
        circuit_id => '3025',
        interfaces => [
          {
            'node' => 'vmx-r1.testlab.grnoc.iu.edu',
            'local' => '1',
            'mac_addrs' => [],
            'interface_description' => 'R1 -> R2',
            'port_no' => undef,
            'node_id' => '4',
            'urn' => undef,
            'interface' => 'ge-0/0/1',
            'tag' => '300',
            'role' => 'unknown'
          }
        ],
        a_side => '4',
        circuit_name => 'admin-5056cdda-f6df-11e7-94cd-fa163e341ea2',
        site_id => 2,
        paths => [
          {
            dest' => '172.16.0.0',
            name' => 'PRIMARY',
            mpls_path_type' => 'loose',
            dest_node' => '1'
          }
        ],
        ckt_type => 'L2VPN',
        state => 'active'
      }
    );

get_routed_lsps creates a map from circuit_id to an array of
associated LSPs.

B<Result>

    {
      '3025' => [
        'I2-LAB1-LAB0-LSP-0'
      ]
    }

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
    
    my $reply = $self->{'jnx'}->get_route_information(table => $table);

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

    my $ints = get_interfaces();

get_interfaces gets basic info about each interface on this device.

B<Returns>

    [
      {
        'addresses' => [
          '156.56.6.103'
        ],
        'name' => 'ge-0/0/0',
        'description' => 'Management Interface',
        'admin_state' => 'up',
        'operational_state' => 'up'
      }
    ]

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
    $self->{'logger'}->debug("get_interface_information: " . $interfaces->toString());
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

=head2 _process_interface

=cut
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

=head2 get_vrf_stats

=cut
sub get_vrf_stats{
    my $self = shift;
    my $success_cb = shift;
    my $error_cb = shift;

    if(!$self->connected()){
        my $error = "Not currently connected to device";
        $self->{'logger'}->error($error);
        return &$error_cb($error);
    }

    my $reply = $self->{'jnx'}->get_bgp_summary_information( instance => "OESS-L3VPN");

    if($self->{'jnx'}->has_error){
        my $error = $self->{'jnx'}->get_first_error();
        $self->set_error($error->{'error_message'});
        $self->{'logger'}->error("Error fetching VRF stats: " . $error->{'error_message'});
        return &$error_cb($error->{'error_message'});
    }

    my %vrf_stats;

    my $stats = $self->{'jnx'}->get_dom();
    $self->{'logger'}->debug("VRF Stats: " . $stats->toString());
    
    my @peer_stats;
    my @rib_stats;

    my $path = $self->{'root_namespace'}."junos-routing";
    my $xp = XML::LibXML::XPathContext->new( $stats );
    $xp->registerNs('x',$stats->documentElement->namespaceURI);
    $xp->registerNs('j',$path);
        
    my $peers = $xp->findnodes('/x:rpc-reply/j:bgp-information/j:bgp-peer');
    foreach my $peer (@{$peers}){
        my $peer_xp = XML::LibXML::XPathContext->new( $peer );
        my $path = $self->{'root_namespace'}."junos-routing";
        $peer_xp->registerNs('j',$path);
        my $address = $peer_xp->findvalue('./j:peer-address');
        my $as = $peer_xp->findvalue('./j:peer-as');
        my $vrf = $peer_xp->findvalue('./j:description');
        my $state = $peer_xp->findvalue('./j:peer-state');
        my $flap_count = $peer_xp->findvalue('./j:flap-count');
        my $rqc = $peer_xp->findvalue('./j:route-queue-count');
        my $output_messages = $peer_xp->findvalue('./j:output-messages');
        my $input_messages = $peer_xp->findvalue('./j:input-messages');
        push(@peer_stats,{vrf => $vrf,
                          address => $address,
                          as => $as,
                          state => $state,
                          flap_count => $flap_count,
                          route_queue_count => $rqc,
                          output_messages => $output_messages,
                          input_messages => $input_messages});
    }

    my $ribs = $xp->findnodes('/x:rpc-reply/j:bgp-information/j:bgp-rib');
    foreach my $rib (@{$ribs}){
        my $rib_xp = XML::LibXML::XPathContext->new( $rib );
        my $path = $self->{'root_namespace'}."junos-routing";
        $rib_xp->registerNs('j',$path);
        my $name = $rib_xp->findvalue('./j:name');
        my $total_prefix_count = $rib_xp->findvalue('./j:total-prefix-count');
        my $received_prefix_count = $rib_xp->findvalue('./j:received-prefix-count');
        my $accepted_prefix_count = $rib_xp->findvalue('./j:accepted-prefix-count');
        my $active_prefix_count = $rib_xp->findvalue('./j:active-prefix-count');
        my $suppressed_prefix_count = $rib_xp->findvalue('./j:suppressed-prefix-count');
        my $history_prefix_count = $rib_xp->findvalue('./j:history-prefix-count');
        my $damped_prefix_count = $rib_xp->findvalue('./j:damped-prefix-count');
        my $total_external_prefix_count = $rib_xp->findvalue('./j:total-external-prefix-count');
        my $active_external_prefix_count = $rib_xp->findvalue('./j:active-external-prefix-count');
        my $accepted_external_prefix_count = $rib_xp->findvalue('./j:accepted-external-prefix-count');
        my $suppressed_external_prefix_count = $rib_xp->findvalue('./j:suppressed-external-prefix-count');
        my $total_internal_prefix_count = $rib_xp->findvalue('./j:total-internal-prefix-count');
        my $active_internal_prefix_count = $rib_xp->findvalue('./j:active-internal-prefix-count');
        my $accepted_internal_prefix_count = $rib_xp->findvalue('./j:accepted-internal-prefix-count');
        my $suppressed_internal_prefix_count = $rib_xp->findvalue('./j:suppressed-internal-prefix-count');
        my $pending_prefix_count = $rib_xp->findvalue('./j:pending-prefix-count');
        push(@rib_stats,{ vrf => $name,
                          total_prefix_count => $total_prefix_count,
                          received_prefix_count => $received_prefix_count,
                          accepted_prefix_count => $accepted_prefix_count,
                          active_prefix_count => $active_prefix_count,
                          suppressed_prefix_count => $suppressed_prefix_count,
                          history_prefix_count => $history_prefix_count,
                          damped_prefix_count => $damped_prefix_count,
                          total_external_prefix_count => $total_external_prefix_count,
                          active_external_prefix_count => $active_external_prefix_count,
                          accepted_external_prefix_count => $accepted_external_prefix_count,
                          suppressed_external_prefix_count => $suppressed_external_prefix_count,
                          total_internal_prefix_count => $total_internal_prefix_count,
                          active_internal_prefix_count => $active_internal_prefix_count,
                          accepted_internal_prefix_count => $accepted_internal_prefix_count,
                          suppressed_internal_prefix_count => $suppressed_internal_prefix_count,
                          pending_prefix_count => $pending_prefix_count });
    }

    return &$success_cb({
        peer_stats => \@peer_stats,
        rib_stats  => \@rib_stats
    });
}

=head2 remove_vlan_xml

=cut
sub remove_vlan_xml {
    my $self = shift;
    my $ckt = shift;

    $ckt->{'switch'}->{'name'} = $self->{'name'};
    $ckt->{'switch'}->{'loopback'} = $self->{'loopback_addr'};

    # BEGIN: The following bits of code handle both L2CCC and the
    # L2VPLS template which seems to have extra path related stanzas
    # in it.
    if (!defined $ckt->{paths}) {
        $ckt->{paths} = [];
    }
    # if ($ckt->{'ckt_type'} eq 'L2CCC') {
        $ckt->{'dest'} = $ckt->{'paths'}->[0]->{'dest'};
        $ckt->{'dest_node'} = $ckt->{'paths'}->[0]->{'dest_node'};
    # }
    # END

    my $output;
    my $ok = $self->{'tt'}->process($self->{'template_dir'} . "/" . $ckt->{'ckt_type'} . "/ep_config_delete.xml", $ckt, \$output);
    if (!$ok) {
        $self->{'logger'}->error($self->{'tt'}->error());
        warn $self->{'tt'}->error();
        return;
    }
    if (!defined $output) {
        $self->{'logger'}->error('Unknown error occurred while generating remove_vlan_xml.');
        warn 'Unknown error occurred while generating remove_vlan_xml.';
        return;
    }
    return $output;
}


=head2 remove_vlan

    my $ok = remove_vlan(
      circuit_id => 1234,
      ckt_type   => 'L2VPLS',
      interfaces => [
        { name => 'ge-0/0/1', tag => 2004 },
        { name => 'ge-0/0/2', tag => 2004 }
      ],
      a_side     => '',            # Optional for L2VPN
      dest_node  => '127.0.0.2',   # Optional for L2VPN and L2VPLS
      paths      => [
        {
          name      => 'vmx1-r2',  # Optional for L2VPN
          dest_node => '127.0.0.2' # Optional for L2VPN and L2CCC
        }
      ]
    );

remove_vlan removes a vlan from this device via NetConf. Returns 1 on
success.

=cut
sub remove_vlan{
    my $self = shift;
    my $ckt = shift;

    if (!$self->connected()) {
        $self->{'logger'}->error("Not currently connected to device");
        return;
    }

    my $output = $self->remove_vlan_xml($ckt);
    if (!defined $output) {
        return FWDCTL_FAILURE;
    }
    return $self->_edit_config(config => $output);
}

=head2 add_vlan_xml

=cut
sub add_vlan_xml {
    my $self = shift;
    my $ckt = shift;

    $ckt->{'switch'}->{'name'} = $self->{'name'};
    $ckt->{'switch'}->{'loopback'} = $self->{'loopback_addr'};
    if ($ckt->{'ckt_type'} eq 'L2CCC') {
        $ckt->{'dest'} = $ckt->{'paths'}->[0]->{'dest'};
        $ckt->{'dest_node'} = $ckt->{'paths'}->[0]->{'dest_node'};
    }

    my $output;
    my $ok = $self->{'tt'}->process($self->{'template_dir'} . "/" . $ckt->{'ckt_type'} . "/ep_config.xml", $ckt, \$output);
    if (!$ok) {
        $self->{'logger'}->error($self->{'tt'}->error());
        warn $self->{'tt'}->error();
        return;
    }
    if (!defined $output) {
        $self->{'logger'}->error('Unknown error occurred while generating add_vlan_xml.');
        warn 'Unknown error occurred while generating add_vlan_xml.';
        return;
    }
    return $output;
}

=head2 add_vlan

    my $ok = add_vlan({
      circuit_name => 'circuit',
      interfaces => [
        {
          interface => 'ge-0/0/1',
          inner_tag => 100,
          tag => 2004,
          unit => 2004
        },
        {
          interface => 'ge-0/0/2',
          inner_tag => 100,
          tag => 2004,
          unit => 2004
        }
      ],
      paths => [],
      circuit_id => 3012,
      site_id => 1,
      ckt_type => 'L2VPLS' # EVPN, L2CCC, L2VPLS, L2VPN, or L3VPN
    });

add_vlan adds a vlan to this device via NetConf. Returns 1 on success.

=cut
sub add_vlan{
    my $self = shift;
    my $ckt = shift;

    if (!$self->connected()) {
        return FWDCTL_FAILURE;
    }

    my $output = $self->add_vlan_xml($ckt);
    if (!defined $output) {
        return FWDCTL_FAILURE;
    }
    return $self->_edit_config(config => $output);
}

=head2 add_vrf_xml

=cut
sub add_vrf_xml {
    my $self = shift;
    my $vrf = shift;

    $vrf->{'switch'}->{'name'} = $self->{'name'};
    $vrf->{'switch'}->{'loopback'} = $self->{'loopback_addr'};

    my $output;
    my $ok = $self->{'tt'}->process($self->{'template_dir'} . "/L3VPN/ep_config.xml", $vrf, \$output);
    if (!$ok) {
        $self->{'logger'}->error($self->{'tt'}->error());
        warn $self->{'tt'}->error();
        return;
    }
    if (!defined $output) {
        $self->{'logger'}->error('Unknown error occurred while generating add_vrf_xml.');
        warn 'Unknown error occurred while generating add_vrf_xml.';
        return;
    }
    $self->{'logger'}->warn(Dumper($vrf));
    $self->{'logger'}->warn(Dumper($output));
    return $output;
}

=head2 add_vrf

=cut
sub add_vrf{
    my $self = shift;
    my $vrf = shift;

    if (!$self->connected()) {
        return FWDCTL_FAILURE;
    }

    $self->{'logger'}->debug("VRF: " . Dumper($vrf));

    my $output = $self->add_vrf_xml($vrf);
    if (!defined $output) {
        return FWDCTL_FAILURE;
    }
    return $self->_edit_config(config => $output);
}

=head2 remove_vrf_xml

=cut
sub remove_vrf_xml {
    my $self = shift;
    my $vrf = shift;

    my $output;
    my $ok = $self->{'tt'}->process($self->{'template_dir'} . "/L3VPN/ep_config_delete.xml", $vrf, \$output);
    if (!$ok) {
        $self->{'logger'}->error($self->{'tt'}->error());
        warn $self->{'tt'}->error();
        return;
    }
    if (!defined $output) {
        $self->{'logger'}->error('Unknown error occurred while generating remove_vrf_xml.');
        warn 'Unknown error occurred while generating remove_vrf_xml.';
        return;
    }
    return $output;
}

=head2 remove_vrf

=cut
sub remove_vrf{
    my $self = shift;
    my $vrf = shift;

    if (!$self->connected()) {
        return FWDCTL_FAILURE;
    }

    my $output = $self->remove_vrf_xml($vrf);
    if (!defined $output) {
        return FWDCTL_FAILURE;
    }
    return $self->_edit_config(config => $output);
}

=head2 xml_configuration( $ckts )

Returns configuration as an xml string based on $ckts, which is an array of
OESS::Circuit objects. It also takes a string of Removes which will be specified before the adds.

=cut
sub xml_configuration {
    my $self = shift;
    my $ckts = shift;
    my $vrf = shift;
    my $remove = shift;

    # We first delete the group then pass the same group a second
    # time. This results in a fully rebuilt config.
    my $configuration = '<configuration>';
    $configuration .= $remove;
    $configuration .= '<groups><name>OESS</name>';

    foreach my $ckt (@{$ckts}) {
        my $xml = $self->add_vlan_xml($ckt);
        if (!defined $xml) {
            next;
        }

        $xml =~ s/<configuration><groups><name>OESS<\/name>//g;
        $xml =~ s/<\/groups><\/configuration>//g;
        $configuration = $configuration . $xml;
    }

    foreach my $vrf (@{$vrf}){
        my $xml = $self->add_vrf_xml($vrf);
        if (!defined $xml) {
            next;
        }

        $xml =~ s/<configuration><groups><name>OESS<\/name>//g;
        $xml =~ s/<\/groups><\/configuration>//g;
        $configuration = $configuration . $xml;
    }

    $configuration = $configuration . '</groups><apply-groups>OESS</apply-groups></configuration>';
    return $configuration;
}

=head2 get_config_to_remove

attempts to find parts of the config to remove, unfortunatly very templates specific

=cut
sub get_config_to_remove{
    my $self = shift;
    my %params = @_;
    my $circuits = $params{'circuits'};
    my $vrfs = $params{'vrfs'};

    return '<groups operation="delete"><name>OESS</name></groups>';
}

=head2 _get_strict_path

=cut
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

=head2 _check_for_shaper

=cut

sub _check_for_shaper{
    my $self = shift;
    my $vrfs = shift;
    my $vrf_id = shift;
    my $port = shift;
    my $unit = shift;
    my $cos_xp = shift;
    my $remove = shift;

    my $vrf = $vrfs->{$vrf_id};
    foreach my $int (@{$vrf->{'interfaces'}}){

	if($int->{'interface'} eq $port && $int->{'unit'} eq $unit){
	    if($int->{'bandwidth'} > 0){

		#will be changed by the template
		return;
	    
	    }else{

		#needs to be removed
		if($cos_xp->exists( "/base:rpc-reply/c:configuration/c:class-of-service/c:interfaces/c:interface/[\@name=\"$port\']/c:unit/[\@name=\"$unit\"]")){
		    #delete the unit!
		    $remove .= "<interface><name>$port</name><unit operation='delete'><name>$unit</name></unit></interface></interfaces>";
		}
	    }
	}
    }


}

=head2 _is_circuit_on_port

=cut
sub _is_circuit_on_port{
    my $self = shift;
    my $circuit_id = shift;
    my $circuits = shift;
    my $port = shift;
    my $unit = shift;

    if(!defined($circuit_id)){
        $self->{'logger'}->error("Unable to find the circuit ID");
        return 0;
    }

    if (!defined $circuits->{$circuit_id}) {
        return 0;
    }

    foreach my $int (@{$circuits->{$circuit_id}->{'interfaces'}}){
        # check to see if the port matches the port
        # check to see if the vlan matches the vlan

        if($int->{'interface'} eq $port && $int->{'unit'} eq $unit){
            $self->{'logger'}->debug("Interface $int->{'interface'}.$int->{'unit'} is in circuit $circuit_id.");
            return 1;
        }
    }

    return 0;

}

=head2 _is_vrf_on_port

=cut
sub _is_vrf_on_port{
    my $self = shift;
    my $vrf_id = shift;
    my $vrfs = shift;
    my $port = shift;
    my $unit = shift; # Unit name on device

    if(!defined($vrf_id)){
        $self->{'logger'}->error("Unable to find the vrf ID");
        return 0;
    }

    if (!defined $vrfs->{$vrf_id}) {
        return 0;
    }

    # check to see if the port matches the port
    # check to see if the vlan matches the vlan
    foreach my $int (@{$vrfs->{$vrf_id}->{'interfaces'}}){
        if ($int->{'interface'} eq $port && $int->{'unit'} eq $unit) {
            return 1;
        }
    }

    return 0;
}


=head2 _is_peer_address

=cut
sub _is_peer_address {
    my $self = shift;
    my $vrf_id = shift;
    my $vrfs = shift;
    my $int_name = shift;
    my $addr_name = shift;

    if(!defined($vrf_id)){
        $self->{'logger'}->error("Unable to find the vrf ID");
        return 0;
    }

    if (!defined $vrfs->{$vrf_id}) {
        return 0;
    }

    foreach my $int (@{$vrfs->{$vrf_id}->{'interfaces'}}) {
        if ($int->{interface} ne $int_name) {
            next;
        }

        foreach my $peer (@{$int->{peers}}) {
            if ($peer->{local_ip} eq $addr_name) {
                return 1;
            }
        }
        return 0;
    }
    return 0;
}

=head2 _is_active_vrf

=cut
sub _is_active_vrf{
    my $self = shift;
    my $vrf_id = shift;
    my $vrfs = shift;

    if(!defined($vrf_id)){
        $self->{'logger'}->error("Unable to find the VRF ID");
        return 0;
    }

    $self->{'logger'}->debug("VRF Details: " . Dumper($vrfs->{$vrf_id}));

    if(defined($vrfs->{$vrf_id}) && $vrfs->{$vrf_id}->{'state'} eq 'active'){
        return 1;
    }

    $self->{'logger'}->error("VRF ID: " . $vrf_id . " was not found as an active VRF... scheduling removal");
    return 0;
    
}

=head2 _is_active_circuit

=cut
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

=head2 get_device_diff

    my $diff = get_device_diff($xml_configuration);
    if (defined $diff->{error}) {
        warn $diff->{error};
    }
    print $diff->{value};

Returns and stores a human readable diff for display to users.

=cut
sub get_device_diff {
    my $self = shift;
    my $conf = shift;

    if (!$self->connected()) {
        return (undef, "Not currently connected to device");
    }

    $self->{'logger'}->debug("Candidate config: " . $conf);

    my %queryargs = (
        'config' => $conf,
        'target' => 'candidate',
    );

    my $ok = $self->lock();
    if (!$ok) {
        return {value => undef, error => "Unable to generate diff without a valid lock."};
    }

    my $res = $self->{'jnx'}->edit_config(%queryargs);
    if ($self->{'jnx'}->has_error) {
        my $dom = $self->{'jnx'}->get_dom();
        $self->{'logger'}->error($dom->toString());

        my $error = $self->{'jnx'}->get_first_error();
        if ($error->{'error_message'} !~ /uncommitted/) {
            $self->disconnect();
            return {value => undef, error => "Error getting device diff: $error->{error_message}"};
        }
    }

    # According to docs format isn't considered when used with
    # compare. However in 15.1F6-S6.4 it is; I would expect this to
    # continue in later Junos versions.
    my $configcompare = $self->{'jnx'}->get_configuration(
        compare => "rollback",
        rollback => "0",
        format => "text"
    );
    if ($self->{'jnx'}->has_error) {
        my $dom = $self->{'jnx'}->get_dom();
        $self->{'logger'}->error($dom->toString());

        my $error = $self->{'jnx'}->get_first_error();
        if ($error->{'error_message'} !~ /uncommitted/) {
            $res = $self->{'jnx'}->discard_changes();
            $ok = $self->unlock();
            return {value => undef, error => "Error getting device diff: $error->{error_message}"};
        }
    }

    my $dom = $self->{'jnx'}->get_dom();
    my $text = $dom->getElementsByTagName('configuration-output')->string_value();
    $self->{'logger'}->debug("Raw diff: " . $text);

    $ok = $self->unlock();

    $text =~ s/\n\[edit .*\]\n[+|-] \s+ authentication-key \S+ \#\# SECRET-DATA\n//g;
    $text =~ s/[+|-] \s+ authentication-key \S+ \#\# SECRET-DATA//g;

    if ($text eq "\n") {
        # In some cases a diff containing only an empty line may be
        # received. This case should be ignored.
        $text = '';
    }

    return {value => $text, error => undef};
}

=head2 _large_diff( $diff )

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
    my $vrfs = $params{'vrfs'};
    my $remove = $params{'remove'};

    if(!$self->connected()){
        $self->{'logger'}->error("Not currently connected to device");
        return FWDCTL_FAILURE;
    }

    my @circuits;
    foreach my $ckt_id (keys (%{$circuits})){
	push(@circuits, $circuits->{$ckt_id});
    }

    my @vrfs;
    foreach my $vrf_id (keys (%{$vrfs})){
        push(@vrfs, $vrfs->{$vrf_id});
    }

    my $configuration = $self->xml_configuration(\@circuits,\@vrfs, $remove);
    if ($configuration eq '<configuration><groups operation="delete"><name>OESS</name></groups><groups><name>OESS</name></groups><apply-groups>OESS</apply-groups></configuration>') {
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
    if (defined $diff->{error}) {
        $self->{'logger'}->error($diff->{error});
        return FWDCTL_FAILURE;
    }
    if ($diff->{value} eq '') {
        $self->{'logger'}->info('No diff required at this time.');
        return FWDCTL_SUCCESS;
    }

    if ($self->_large_diff($diff->{value})) {
        # It may be possible that a large diffs is considered untrusted.
        # If so, block until the diff has been approved.
        $self->{'logger'}->info('Large diff detected. Waiting for approval before installation.');
        $self->{'pending_diff'} = 1;
        return FWDCTL_BLOCKED;
    }

    $self->{'logger'}->info("Auto diff was initiated. Starting installation.");

    return $self->_edit_config(config => $configuration);
}

=head2 get_diff_text

    my $diff = get_diff_text(...);
    if (defined $diff->{error}) {
        warn $diff->{error};
    }
    print $diff->{value};

Returns a human readable diff between $circuits and this Device's
configuration, or undef when no diff is required. Takes an array of
circuits to build the current configuration, and a remove string of
XML to be removed from the device.

=cut
sub get_diff_text {
    my $self = shift;
    my %params = @_;
    my $circuits = $params{'circuits'};
    my $vrfs = $params{'vrfs'};
    my $remove = $params{'remove'};

    $self->{'logger'}->debug("Calling MX.get_diff_text");

    if(!$self->connected()){
        return {value => undef, error => "Not currently connected to device."};
    }

    my @circuits;
    foreach my $ckt_id (keys (%{$circuits})){
        push(@circuits, $circuits->{$ckt_id});
    }

    my @vrfs;
    foreach my $vrf_id (keys (%{$vrfs})){
        push(@vrfs, $vrfs->{$vrf_id});
    }

    my $configuration = $self->xml_configuration(\@circuits,\@vrfs, $remove );
    if ($configuration eq '<configuration><groups operation="delete"><name>OESS</name></groups><groups><name>OESS</name></groups><apply-groups>OESS</apply-groups></configuration>') {
        return {value => '', error => undef};
    }

    return $self->get_device_diff($configuration);
}

=head2 unit_name_available

    my $ok = unit_name_available('ge-0/0/1', 2004);

unit_name_available returns C<1> if the unit is available for
provisioning. If the unit name already exists on the specified
interface or another error occurs C<0> is returned.

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

    my $ok = connect();

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

    $self->{'jnx'}->{'methods'}->{'get_configuration'} = {
        format   => $ATTRIBUTE,
        compare  => $ATTRIBUTE,
        changed  => $ATTRIBUTE,
        database => $ATTRIBUTE,
        rollback => $ATTRIBUTE
    };

    $self->{'jnx'}->{'methods'}->{'get_mpls_lsp_information'} = {
        detail    => $TOGGLE,
        extensive => $TOGGLE,
    };

    $self->{'jnx'}->{'methods'}->{'open_configuration'} = {private => $TOGGLE};

    $self->{'jnx'}->{'methods'}->{'commit_configuration'} = {
        check       => $TOGGLE,
        synchronize => $TOGGLE
    };

    $self->{'jnx'}->{'methods'}->{'get_isis_adjacency_information'} = {detail => $TOGGLE};

    $self->{'jnx'}->{'methods'}->{'close_configuration'} = {};

    $self->{'logger'}->info("Connected to device!");
    return 1;
}


=head2 connected

    my $state = connected();

connected returns 1 if the device is currently connected.

=cut
sub connected {
    my $self = shift;

    if (!defined $self->{'jnx'} || !defined $self->{'jnx'}->{'conn_obj'}) {
	$self->{'logger'}->warn("Connection state is down");
	return 0;
    }

    return 1;
}


=head2 verify_connection

    my $ok = verify_connection();

verify_connection gathers basic system information and checks the
device is running a supported software version.

=cut
sub verify_connection{
    my $self = shift;

    if(!$self->connected()){
        $self->{'logger'}->error("Not currently connected to device");
        return 0;
    }

    my ($sysinfo, $err) = $self->get_system_information();
    if (defined $err) {
        $self->{'logger'}->error("Couldn't get system information: $err");
        return 0;
    }

    foreach my $fw (@{$self->{'supported_firmware'}}) {
        if ($sysinfo->{'os_name'} eq $fw->{'make'} && $sysinfo->{'model'} eq $fw->{'model'} && $sysinfo->{'version'} eq $fw->{'number'} && $sysinfo->{'major_rev'} eq $fw->{'major_rev'}) {
            return 1;
        }
    }

    warn "Network OS $sysinfo->{'os_name'} version $sysinfo->{'version'} on the $sysinfo->{'model'} is not supported.";
    $self->{'logger'}->error("Network OS $sysinfo->{'os_name'} version $sysinfo->{'version'} on the $sysinfo->{'model'} is not supported.");
    $self->disconnect();
    return 0;
}

=head2 get_isis_adjacencies

    my $adjs = get_isis_adjacencies();

get_isis_adjacencies returns a list of ISIS adjacencies.

B<Returns>

    [
      {
        'interface_name' => 'ae1',
        'remote_system_name' => 'vmx-r3',
        'ip_address' => '172.16.0.19',
        'ipv6_address' => 'fe80::205:8600:285c:d9c0',
        'operational_state' => 'Up'
      },
      {
        'interface_name' => 'ge-0/0/1',
        'remote_system_name' => 'vmx-r1',
        'ip_address' => '172.16.0.16',
        'ipv6_address' => 'fe80::206:a00:1e0e:fff5',
        'operational_state' => 'Up'
      }
    ]

=cut
sub get_isis_adjacencies{
    my $self = shift;

    if(!$self->connected()){
        $self->{'logger'}->error("Not currently connected to device");
        return;
    }

    $self->{'jnx'}->get_isis_adjacency_information( detail => 1 );

    my $xml = $self->{'jnx'}->get_dom();
    $self->{'logger'}->debug("get_isis_adjacency_information: " . $xml->toString());
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


=head2 _process_isis_adj

=cut
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

    my $lsps = get_LSPs();

get_LSPs returns all MPLS LSPs on this device. Returns an empty array
if none are found or an error occurs.

B<Returns>

    [{
      sessions => [{
        'destination-address' => '172.16.0.6',
        'name' => 'I2-LAB0-MX960-1-LSP-6',
        'lsp-type' => 'Static Configured',
        'lsp-state' => 'Up',
        'description' => '',
        'paths' => [
          {
            'path-state' => 'Up',
            'explicit-route' => {
              'explicit-route-type' => '',
              'addresses' => [
                '172.16.0.13',
                '172.16.0.17',
                '172.16.0.19',
                '172.16.0.31'
              ]
            },
            'name' => 'I2-LAB0-MX960-1-LSP-6-primary',
            'setup-priority' => '0',
            'smart-optimize-timer' => '',
            'path-active' => '',
            'received-rro' => 'Received RRO (ProtectionFlag 1=Available 2=InUse 4=B/W 8=Node 10=SoftPreempt 20=Node-ID):
      172.16.0.13 172.16.0.17 172.16.0.19 172.16.0.31',
            'title' => 'Primary',
            'hold-priority' => '0'
          }
        ],
        'egress-label-operation' => 'Penultimate hop popping',
        'active-path' => 'I2-LAB0-MX960-1-LSP-6-primary (primary)',
        'route-count' => '0',
        'revert-timer' => '600',
        'source-address' => '172.16.0.0',
        'load-balance' => 'random',
        'attributes' => {
          'encoding-type' => 'Packet',
          'switching-type' => '',
          'gpid' => ''
        }
      }],
      session_type => 'Ingress',
      count => '1'
    }]

=cut
sub get_LSPs{
    my $self = shift;

    if(!$self->connected()){
        $self->{'logger'}->error("Not currently connected to device");
        return;
    }

    $self->{'jnx'}->get_mpls_lsp_information(detail => 1);
    my $xml = $self->{'jnx'}->get_dom();
    $self->{'logger'}->debug("get_mpls_lsp_information: " . $xml->toString());
    my $xp = XML::LibXML::XPathContext->new( $xml);
    $xp->registerNs('x',$xml->documentElement->namespaceURI);
    $xp->registerNs('j', $self->{'root_namespace'} . 'junos-routing');
    my $rsvp_session_data = $xp->find('/x:rpc-reply/j:mpls-lsp-information/j:rsvp-session-data');
    
    my @LSPs;

    foreach my $rsvp_sd (@{$rsvp_session_data}){
	push(@LSPs, $self->_process_rsvp_session_data($rsvp_sd));
    }

    return \@LSPs;
}

=head2 get_lsp_paths

    my $paths = get_lsp_paths();

get_lsp_paths returns a map of LSP to an array of IP addresses; Each
array indicates the links of the LSP. An empty hash will be returned
if no LSPs are found or even if a failure occurs.

B<Returns>

    {
      'I2-LAB0-MX960-1-LSP-6' => [
        '172.16.0.13',
        '172.16.0.17',
        '172.16.0.19',
        '172.16.0.31'
      ]
    }

=cut
sub get_lsp_paths{
    my $self = shift;
    my $success_cb = shift;
    my $error_cb = shift;

    if(!$self->connected()){
        my $error = 'Not currently connected to device';
        $self->{'logger'}->error($error);
        return &$error_cb($error);
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
                my $next_hops;
                if ( $self->{'major_rev'} < 17 ) {
                    $next_hops = $xp->find('./r:explicit-route/r:address', $path);
                } else {
                    $next_hops = $xp->find('./r:explicit-route/r:explicit-route-element/r:address', $path);
                }

                foreach my $nh (@{$next_hops}) {
                    push(@{$lsp_routes->{$name}}, $nh->textContent);
                }
            }
        }
    }
    return &$success_cb($lsp_routes);
}

=head2 _process_rsvp_session_data

=cut
sub _process_rsvp_session_data{
    my $self = shift;
    my $rsvp_sd = shift;
    
    my $obj = {};

    my $xp = XML::LibXML::XPathContext->new( $rsvp_sd);
    $xp->registerNs('j', $self->{'root_namespace'} . 'junos-routing');
    $obj->{'session_type'} = trim($xp->findvalue('./j:session-type'));
    $obj->{'count'} = trim($xp->findvalue('./j:count'));
    $obj->{'sessions'} = ();

    my $rsvp_sessions = $xp->find('./j:rsvp-session');

    if($obj->{'session_type'} eq 'Ingress'){
	
	foreach my $session (@{$rsvp_sessions}){
	    push(@{$obj->{'sessions'}}, $self->_process_rsvp_session_ingress($session));
	}
	
    }elsif($obj->{'session_type'} eq 'Egress'){

	foreach my $session (@{$rsvp_sessions}){
            push(@{$obj->{'sessions'}}, $self->_process_rsvp_session_egress($session));
        }

    }else{
	
	foreach my $session (@{$rsvp_sessions}){
            push(@{$obj->{'sessions'}}, $self->_process_rsvp_session_transit($session));
        }

    }
    return $obj;

}

=head2 _process_rsvp_session_transit

=cut
sub _process_rsvp_session_transit{
    my $self = shift;
    my $session = shift;

    my $obj = {};

    my $xp = XML::LibXML::XPathContext->new( $session );
    $xp->registerNs('j', $self->{'root_namespace'} . 'junos-routing');
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
	push(@{$obj->{'packet-information'}}, $self->_process_packet_info($pkt_info));
    }


    my $record_routes = trim($xp->find('./j:record-route/j:address'));
    $obj->{'record-route'} = ();
    foreach my $rr (@$record_routes){
	push(@{$obj->{'record-route'}}, $rr->textContent);
    }


    return $obj;
}

=head2 _process_packet_info

=cut
sub _process_packet_info{
    my $self = shift;
    my $pkt_info = shift;
    my $obj = {};

    my $xp = XML::LibXML::XPathContext->new( $pkt_info );
    $xp->registerNs('j', $self->{'root_namespace'} . 'junos-routing');

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

=head2 _process_rsvp_session_egress

=cut
sub _process_rsvp_session_egress{
    my $self = shift;
    my $session = shift;

    my $obj = {};

    my $xp = XML::LibXML::XPathContext->new( $session );
    $xp->registerNs('j', $self->{'root_namespace'} . 'junos-routing');
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
        push(@{$obj->{'packet-information'}}, $self->_process_packet_info($pkt_info));
    }

    my $record_routes = trim($xp->find('./j:record-route/j:address'));
    $obj->{'record-route'} = ();
    foreach my $rr (@$record_routes){
        push(@{$obj->{'record-route'}}, $rr->textContent);
    }    

    return $obj;
}

=head2 _process_rsvp_session_ingress

=cut
sub _process_rsvp_session_ingress{
    my $self = shift;
    my $session = shift;
    
    my $obj = {};

    my $xp = XML::LibXML::XPathContext->new( $session );
    $xp->registerNs('j', $self->{'root_namespace'} . 'junos-routing');
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
	push(@{$obj->{'paths'}}, $self->_process_lsp_path($path));
    }

    return $obj;
}

=head2 _process_lsp_path

=cut
sub _process_lsp_path{
    my $self = shift;
    my $path = shift;

    my $xp = XML::LibXML::XPathContext->new( $path );
    $xp->registerNs('j', $self->{'root_namespace'} . 'junos-routing');
    
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

=head2 _edit_config

=cut
sub _edit_config{
    my $self = shift;
    my %params = @_;

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
    my $result;
    my $ok = 0;

    $self->{'logger'}->debug("Locking config");
    $ok = $self->lock();
    if (!$ok) {
        $self->{'logger'}->error("Unable to edit config without a valid lock.");
        return FWDCTL_FAILURE;
    }

    $self->{'logger'}->debug("Locked config!");

    %queryargs = (
        target => 'candidate',
        config => $params{'config'}
    );

    eval {
        $self->{'logger'}->debug("Calling edit_config: " . $queryargs{'config'});
        $self->{'jnx'}->edit_config(%queryargs);

        my $dom = $self->{'jnx'}->get_dom()->toString();
        my $response = XMLin($dom);

        my $errors = [];
        if (defined $response->{'commit-results'} && $response->{'commit-results'}->{'rpc-error'}) {
            $errors = $response->{'commit-results'}->{'rpc-error'};
        }

        if (defined $response->{'rpc-error'}) {
            $errors = $response->{'rpc-error'};
        }

        if (ref($errors) eq 'HASH') {
            $errors = [ $errors ];
        }

        foreach my $error (@{$errors}) {
            my $lvl = $error->{'error-severity'};
            my $msg = $error->{'error-message'};
            $msg =~ s/^\s+|\s+$//g; # python >> str.strip()

            if ($lvl eq 'warning') {
                $self->{'logger'}->warn($msg);
            } else {
                # error-severity of 'error' is considered fatal
                $self->{'logger'}->debug(Dumper($error));
                die $msg;
            }
        }
    };
    if ($@) {
        my $err = "$@";
        $self->set_error($err);
        $self->{'logger'}->error($err);

        $self->unlock();
        return FWDCTL_FAILURE;
    }

    if ($self->{'jnx'}->has_error) {
        my $error = $self->{'jnx'}->get_first_error();
        if ($error->{'error_message'} !~ /uncommitted/) {
            my $lvl = $error->{'error_severity'};
            my $msg = $error->{'error_message'};

            if ($lvl eq 'warning') {
                $self->{'logger'}->warn($msg);
            } else {
                # error-severity of 'error' is considered fatal
                $self->{'logger'}->error($msg);
                $self->unlock();
                return FWDCTL_FAILURE;
            }
        }
    }

    $self->{'logger'}->debug("Commiting!");
    $ok = $self->commit();
    if (!$ok) {
        $self->{'logger'}->error("Commit could not be completed!");
        $result = FWDCTL_FAILURE;
    } else {
        $self->{'logger'}->debug("Commit complete!");
        $result = FWDCTL_SUCCESS;
    }

    $self->{'logger'}->debug("Unlocking!");
    $self->unlock();
    $self->{'logger'}->debug("Unlock complete!");

    return $result;
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
