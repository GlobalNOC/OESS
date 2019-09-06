#!/usr/bin/perl

use strict;
use warnings;

package OESS::MPLS::Device;

use GRNOC::Config;
use OESS::MPLS::Device::Juniper::MX;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;
use constant OESS_PW_FILE       => "/etc/oess/.passwd.xml";

=head2 new

creates a new device object (don't instantiate directly)

=cut

sub new{
    my $class = shift;
    my %args = (
        @_
        );

    my $self = \%args;

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.MPLS.Device.' . $self->{'host_info'}->{'mgmt_addr'});
    $self->{'logger'}->debug("MPLS Device created");

    bless $self, $class;    
}

sub _get_credentials{
    my $self = shift;
    my $node_id = $self->{'node_id'};
    my $config = GRNOC::Config->new( config_file => OESS_PW_FILE );
    my $node;
    if (defined $node_id) {
        $node = $config->{'doc'}->getDocumentElement()->find("/config/node[\@node_id='$node_id']")->[0];
    }

    my $creds;
    if(!defined($node)){
        $creds = { username => $config->get("/config/\@default_user")->[0],
                   password => $config->get("/config/\@default_pw")->[0] };
    }else{
        $creds = XML::Simple::XMLin($node->toString(), ForceArray => 1);
    }

    if(!defined($creds)){
        warn "No Credentials found for node_id: " . $node_id . "\n";
	die;
    }

    return $creds;

}

=head2 connect

=cut

sub connect{
    my $self = shift;

    $self->set_error("This device does not support connect");
    return;
}

=head2 get_config_to_remove

=cut
sub get_config_to_remove{
    my $self = shift;

    $self->set_error("This device does not support connect");
    return;
}

=head2 disconnect

=cut
sub disconnect{
    my $self = shift;

    $self->set_error("This device does not support disconnect");
    return;
}

=head2 get_system_information

=cut

sub get_system_information{
    my $self = shift;

    $self->set_error("This device does not support get_system_information");
    return;
}

=head2 get_routed_lsps

See OESS::MPLS::Switch::get_routed_lsps for input and output format

=cut

sub get_routed_lsps{
    my $self = shift;

    $self->set_error("This device does not support get_routed_lsps");
    return;
}

=head2 get_interfaces 

=cut

sub get_interfaces{
    my $self = shift;

    $self->set_error("This device does not support get_interfaces");
    return;
}

=head2 get_isis_adjacencies

=cut

sub get_isis_adjacencies{
    my $self = shift;
    
    $self->set_error("This device does not support get_isis_adjacencies");
    return;
}

=head2 get_LSPs

=cut

sub get_LSPs{
    my $self = shift;

    $self->set_error("This device does not support get_LSPs");
    return;
}

=head2 get_lsp_paths

See OESS::MPLS::Switch::get_lsp_paths for input and output format

=cut

sub get_lsp_paths{
    my $self = shift;

    $self->set_error("This device does not support get_lsp_paths");
    return;
}

=head2 add_vlan

=cut

sub add_vlan{
    my $self = shift;

    $self->set_error("This device does not support add_vlan");
    return;
}

=head2 remove_vlan

=cut

sub remove_vlan{
    my $self = shift;

    $self->set_error("This device does not support remove_vlan");
    return;
}

=head2 add_vrf

=cut

sub add_vrf{
    my $self = shift;

    $self->set_error("This device does not support add_vrf");
    return;
}

=head2 remove_vrf

=cut

sub remove_vrf{
    my $self = shift;

    $self->set_error("This device does not support remove_vrf");
    return;
}

=head2 get_vrf_stats

=cut

sub get_vrf_stats{
    my $self = shift;

    $self->set_error("This device does not support get_vrf_stats");
    return;
}


=head2 diff

=cut

sub diff {
    my $self = shift;

    $self->set_error("The device does not support diff");
    return;
}

=head2 diff_approved

Returns 1 if $diff may be applied without manual approval.

=cut
sub diff_approved {
    my $self = shift;
    my $diff = shift;

    $self->set_error("This device does not support large_diff");
}

=head2 set_error

=cut

sub set_error{
    my $self = shift;
    my $error = shift;
    $self->{'has_error'} = 1;
    push(@{$self->{'error'}}, $error);
}

=head2 has_error

=cut

sub has_error{
    my $self = shift;
    return $self->{'has_error'};
}

=head2 get_error

=cut

sub get_error{
    my $self = shift;

    my $errors = "";
    foreach my $error (@{$self->{'error'}}){
        $errors .= $error . "\n";
    }

    # Clear out the error for next time...
    $self->{'error'} = ();
    $self->{'has_error'} = 0;

    return $errors;
}

1;
