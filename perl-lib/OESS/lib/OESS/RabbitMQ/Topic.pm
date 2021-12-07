package OESS::RabbitMQ::Topic;

use strict;
use warnings;

use Data::Dumper;
use Exporter qw(import);
use Log::Log4perl;

our @EXPORT = qw(discovery_topic_for_node fwdctl_topic_for_node fwdctl_topic_for_connection discovery_switch_topic_for_node fwdctl_switch_topic_for_node);

=head1 OESS::RabbitMQ::Topic

    use OESS::RabbitMQ::Topic qw(discovery_topic_for_node fwdctl_topic_for_node fwdctl_topic_for_connection);

=cut

=head2 fwdctl_topic_for_connection

    my ($topic, $err) = fwdctl_topic_for_connection($conn->to_hash);

fwdctl_topic_for_connection returns the topic which should be used for
provisioning C<$conn>. The topic chosen is based on the controller
associated with the node of each endpoint. The controller must be the
same across all endpoints or an error is returned.

=cut
sub fwdctl_topic_for_connection {
    my $conn = shift;

    # Accessing variables directly vs using methods to allow for use
    # of both connection objects and their hashes. This is primarily
    # to accommodate circuit.cgi->update which has both a previous and
    # pending hash. If the topic is different for the two then
    # _send_update_cache needs to be called for both.

    my $controller; # 'openflow','netconf','nso'
    foreach my $ep (@{$conn->{endpoints}}) {
        if (!defined $controller) {
            $controller = $ep->{controller};
            next;
        }
        if ($controller ne $ep->{controller}) {
            return (undef, "Connection endpoints are not on the same controller.");
        }
    }

    if ($controller eq 'openflow') {
        return ('OF.FWDCTL.RPC', undef);
    }
    elsif ($controller eq 'netconf') {
        return ('MPLS.FWDCTL.RPC', undef);
    }
    elsif ($controller eq 'nso') {
        return ('NSO.FWDCTL.RPC', undef);
    }
    else {
        return (undef, "Unexpected controller '$controller' found for connection endpoints.");
    }
}

=head2 discovery_topic_for_node

    my ($topic, $err) = discovery_topic_for_node($node);

discovery_topic_for_node returns the topic which should be used for
working with C<$node>. The topic chosen is based on the controller
associated with the C<$node>.

=cut
sub discovery_topic_for_node {
    my $node = shift;

    my $controller = $node->controller;

    if ($controller eq 'openflow') {
        return ('OF.Discovery.RPC', undef);
    }
    elsif ($controller eq 'netconf') {
        return ('MPLS.Discovery.RPC', undef);
    }
    elsif ($controller eq 'nso') {
        return ('NSO.Discovery.RPC', undef);
    }
    else {
        return (undef, "Unexpected controller '$controller' found for node.");
    }
}

=head2 fwdctl_topic_for_node

    my ($topic, $err) = fwdctl_topic_for_node($node);

fwdctl_topic_for_node returns the topic which should be used for
working with C<$node>. The topic chosen is based on the controller
associated with the C<$node>.

=cut
sub fwdctl_topic_for_node {
    my $node = shift;

    my $controller = $node->controller;

    if ($controller eq 'openflow') {
        return ('OF.FWDCTL.RPC', undef);
    }
    elsif ($controller eq 'netconf') {
        return ('MPLS.FWDCTL.RPC', undef);
    }
    elsif ($controller eq 'nso') {
        return ('NSO.FWDCTL.RPC', undef);
    }
    else {
        return (undef, "Unexpected controller '$controller' found for node.");
    }
}

=head2 discovery_switch_topic_for_node

    my ($topic, $err) = discovery_switch_topic_for_node(
        mgmt_addr  => '127.0.0.1',
        tcp_port   => 830,
        controller => 'netconf'
    );

discovery_switch_topic_for_node returns the Discovery.Switch topic which
should be used for working with C<$node>. The topic chosen is based on
the controller associated with the C<$node>.

=cut
sub discovery_switch_topic_for_node {
    # TODO Take Switch object as argument
    # TODO Return error when used incorrectly
    my $args = {
        mgmt_addr  => undef,
        tcp_port   => 830,
        controller => 'netconf',
        @_
    };

    my $controller = $args->{controller};

    if ($controller eq 'openflow') {
        # There are no switch processes in the 'openflow' controller
        # return (undef, "Unexpected controller '$controller' found for node.");
        return undef;
    }
    elsif ($controller eq 'netconf') {
        # return ("MPLS.Discovery.Switch.$args->{mgmt_addr}.$args->{tcp_port}", undef);
        return "MPLS.Discovery.Switch.$args->{mgmt_addr}.$args->{tcp_port}";
    }
    elsif ($controller eq 'nso') {
        # There are no switch processes in the 'nso' controller
        # return (undef, "Unexpected controller '$controller' found for node.");
        return;
    }
    else {
        # return (undef, "Unexpected controller '$controller' found for node.");
        return;
    }
}

=head2 fwdctl_switch_topic_for_node

    my ($topic, $err) = fwdctl_switch_topic_for_node(
        mgmt_addr  => '127.0.0.1',
        tcp_port   => 830,
        controller => 'netconf'
    );

fwdctl_switch_topic_for_node returns the FWDCTL.Switch topic which
should be used for working with C<$node>. The topic chosen is based on
the controller associated with the C<$node>.

=cut
sub fwdctl_switch_topic_for_node {
    # TODO Take Switch object as argument
    # TODO Return error when used incorrectly
    my $args = {
        mgmt_addr  => undef,
        tcp_port   => 830,
        controller => 'netconf',
        @_
    };

    my $controller = $args->{controller};

    if ($controller eq 'openflow') {
        # There are no switch processes in the 'openflow' controller
        # return (undef, "Unexpected controller '$controller' found for node.");
        return;
    }
    elsif ($controller eq 'netconf') {
        # return ("MPLS.FWDCTL.Switch.$args->{mgmt_addr}.$args->{tcp_port}", undef);
        return "MPLS.FWDCTL.Switch.$args->{mgmt_addr}.$args->{tcp_port}";
    }
    elsif ($controller eq 'nso') {
        # There are no switch processes in the 'nso' controller
        # return (undef, "Unexpected controller '$controller' found for node.");
        return;
    }
    else {
        # return (undef, "Unexpected controller '$controller' found for node.");
        return;
    }
}

return 1;
