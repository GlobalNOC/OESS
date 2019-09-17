use strict;
use warnings;

package OESS::MPLS::Device::Juniper::QFX;

use parent 'OESS::MPLS::Device::Juniper::MX';

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;
use constant FWDCTL_BLOCKED     => 4;

use Log::Log4perl;

=head1 OESS::MPLS::Device::Juniper::QFX

    use OESS::MPLS::Device::Juniper::QFX;

=cut

=head2 new

    my $qfx = OESS::MPLS::Device::Juniper::QFX->new(
      config => '/etc/oess/database.xml',
      loopback_addr => '127.0.0.1',
      mgmt_addr     => '192.168.1.1',
      name          => 'demo.grnoc.iu.edu',
      node_id       => 1
    );

new creates a Juniper QFX device object. Use methods on this object to
communicate with a device on the network.

=cut
sub new {
    my $class = shift;
    my $args = {
        @_
    };

    my $self = $class->SUPER::new(@_);
    bless $self, $class;

    $self->{logger} = Log::Log4perl->get_logger("OESS.MPLS.Device.Juniper.QFX.$self->{mgmt_addr}");
    $self->{logger}->info("Juniper QFX Loaded: $self->{mgmt_addr}");

    return $self;
}

=head2 add_vrf

=cut
sub add_vrf {
    my $self = shift;
    $self->{logger}->error('Layer 3 Connections are not supported on QFX devices.');
    return FWDCTL_FAILURE;
}

=head2 remove_vrf

=cut
sub remove_vrf {
    my $self = shift;
    $self->{logger}->error('Layer 3 Connections are not supported on QFX devices.');
    return FWDCTL_FAILURE;
}

return 1;
