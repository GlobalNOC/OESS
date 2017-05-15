#!/usr/bin/perl

use strict;
use warnings;

###############################################################################
package OESS::MPLS::Topology;

use strict;
use warnings;

use GRNOC::RabbitMQ;

=head2 new

    create a new OESS Master process

=cut

sub new {
    my $class = shift;
    my %params = @_;
    my $self = \%params;
    bless $self, $class;

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.MPLS.Topology');

    if(!defined($self->{'config'})){
        $self->{'config'} = "/etc/oess/database.xml";
    }

    $self->{'db'} = OESS::Database->new( config_file => $self->{'config'} );

    my $fwdctl_dispatcher = GRNOC::RabbitMQ::Dispatcher->new( host => $self->{'db'}->{'rabbitMQ'}->{'host'},
                                                              port => $self->{'db'}->{'rabbitMQ'}->{'port'},
                                                              user => $self->{'db'}->{'rabbitMQ'}->{'user'},
                                                              pass => $self->{'db'}->{'rabbitMQ'}->{'pass'},
                                                              exchange => 'OESS',
                                                              queue => 'MPLS-FWDCTL',
                                                              topic => "MPLS.FWDCTL.RPC");

    $self->register_rpc_methods( $fwdctl_dispatcher );
    $self->register_nox_events( $fwdctl_dispatcher );

    $self->{'fwdctl_dispatcher'} = $fwdctl_dispatcher;


    $self->{'fwdctl_events'} = GRNOC::RabbitMQ::Client->new( host => $self->{'db'}->{'rabbitMQ'}->{'host'},
                                                             port => $self->{'db'}->{'rabbitMQ'}->{'port'},
                                                             user => $self->{'db'}->{'rabbitMQ'}->{'user'},
                                                             pass => $self->{'db'}->{'rabbitMQ'}->{'pass'},
                                                             exchange => 'OESS',
                                                             topic => 'MPLS.FWDCTL.event');



    $self->{'logger'}->info("RabbitMQ ready to go!");

    # When this process receives sigterm send an event to notify all
    # children to exit cleanly.
    $SIG{TERM} = sub {
        $self->stop();
    };


    #from TOPO startup
    my $nodes = $self->{'db'}->get_current_nodes( MPLS => 1);
    foreach my $node (@$nodes) {
        $self->{'db'}->update_node_operational_state(node_id => $node->{'node_id'}, state => 'down');
    }

    my $topo = OESS::Topology->new( db => $self->{'db'}, MPLS => 1 );
    if (! $topo) {
        $self->{'logger'}->fatal("Could not initialize topo library");
        exit(1);
    }

    return $self;

}

1;
