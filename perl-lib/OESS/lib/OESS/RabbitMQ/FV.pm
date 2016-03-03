package OESS::RabbitMQ::FV;

use Data::Dumper;
use GRNOC::RabbitMQ::Client;
use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;
use GRNOC::WebService::Regex;
use Log::Log4perl;

sub new {
    my $class  = shift;
    my $config = shift;

    my $self   = {};
    bless $self, $class;
    
    $self->{'logger'} = Log::Log4perl->get_logger("OESS.RabbitMQ.FV");
    $self->{'nox'}    = GRNOC::RabbitMQ::Client->new( host => $config->{'rabbitMQ'}->{'host'},
                                                      port => $config->{'rabbitMQ'}->{'port'},
                                                      user => $config->{'rabbitMQ'}->{'user'},
                                                      pass => $config->{'rabbitMQ'}->{'pass'},
                                                      exchange => 'OESS',
                                                      topic => 'OF.NOX' );
    $self->{'dispatch'} = GRNOC::RabbitMQ::Dispatcher->new( host => $config->{'rabbitMQ'}->{'host'},
                                                            port => $config->{'rabbitMQ'}->{'port'},
                                                            user => $config->{'rabbitMQ'}->{'user'},
                                                            pass => $config->{'rabbitMQ'}->{'pass'},
                                                            exchange => 'OESS',
                                                            topic => 'OF.NOX' );
    return $self;
}

sub start {
    my $self = shift;
    $self->{'dispatch'}->start_consuming();
}

=head2 register_for_fv_in

Publishes a message to OF.NOX.register_for_fv_in to enable the
generation of fv_packet_in messages on OF.NOX.fv_packet_in.

=over 1

=item $discovery_vlan VLAN on which discovery packets will be sent.

=back

=cut
sub register_for_fv_in {
    my $self = shift;
    my $discovery_vlan = shift;

    $self->{'nox'}->register_for_fv_in(discovery_vlan => $discovery_vlan);
}

=head2 send_fv_link_event

Generates a link event to the OF.FV.fv_link_event topic.

=over 1

=item $link_name  Name of link that triggered an event

=item $link_state State of the link identified by link_name

=back

=cut
sub send_fv_link_event {
    my $self       = shift;
    my $link_name  = shift;
    my $link_state = shift;
 
    $self->{'nox'}->fv_link_event( link_name => $link_name,
                                   state     => $link_state,
                                   no_reply  => 1 );
}

=head2 send_fv_packets

Sends an array of packets to $discovery_valn every $interval.

=over 1

=item $interval       Interval by which $packets will be sent

=item $discovery_vlan VLAN to which discovery packets must be sent.

=item $packets        Array reference of packets to send

=back

=cut
sub send_fv_packets {
    my $self           = shift;
    my $interval       = shift;
    my $discovery_vlan = shift;
    my $packets        = shift;

    $self->{'nox'}->send_fv_packets( interval       => $interval,
                                     discovery_vlan => $discovery_vlan,
                                     packets        => $packets );
}

sub on_datapath_join {
    my $self = shift;
    my $func = shift;
    my $method = GRNOC::RabbitMQ::Method->new( name        => "datapath_join",
                                               topic       => "OF.NOX.event",
                                               callback    => $func,
                                               description => "Signals a node has joined the controller" );
    $method->add_input_parameter( name => "dpid",
                                  description => "Datapath ID of node that has joined",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::NUMBER_ID );
    $method->add_input_parameter( name => "ip",
                                  description => "IP Address of node that has joined",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::INTEGER );
    $method->add_input_parameter( name => "ports",
                                  description => "Array of OpenFlow port structs",
                                  required => 1,
                                  schema => { 'type'  => 'array',
                                              'items' => [ 'type' => 'object',
                                                           'properties' => { 'hw_addr'    => {'type' => 'number'},
                                                                             'curr'       => {'type' => 'number'},
                                                                             'name'       => {'type' => 'string'},
                                                                             'speed'      => {'type' => 'number'},
                                                                             'supported'  => {'type' => 'number'},
                                                                             'enabled'    => {'type' => 'number'}, # bool
                                                                             'flood'      => {'type' => 'number'}, # bool
                                                                             'state'      => {'type' => 'number'},
                                                                             'link'       => {'type' => 'number'}, # bool
                                                                             'advertised' => {'type' => 'number'},
                                                                             'peer'       => {'type' => 'number'},
                                                                             'config'     => {'type' => 'number'},
                                                                             'port_no'    => {'type' => 'number'}
                                                                           }
                                                         ]
                                            } );
    $self->{'dispatch'}->register_method($method);
}

sub on_datapath_leave {
    my $self = shift;
    my $func = shift;
    my $method = GRNOC::RabbitMQ::Method->new( name        => "datapath_leave",
                                               callback    => $func,
                                               description => "Removes datapath to FV's internal nodes" );
    $method->add_input_parameter( name => "dpid",
                                  description => "Removes datapath from FV's internal nodes",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::NAME_ID );

    $self->{'dispatch'}->register_method($method);
}

sub on_link_event {
    my $self = shift;
    my $func = shift;
    my $method = GRNOC::RabbitMQ::Method->new( name        => "link_event",
                                               callback    => $func,
                                               description => "Notifies FV of any link event." );
    $method->add_input_parameter( name => "a_dpid",
                                  description => "DPID of one node on the link",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::NAME_ID );
    $method->add_input_parameter( name => "a_port",
                                  description => "Port of node a on the link",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::INTEGER );
    $method->add_input_parameter( name => "z_dpid",
                                  description => "DPID of one node on the link",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::NAME_ID );
    $method->add_input_parameter( name => "z_port",
                                  description => "Port of node z on the link",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::INTEGER );
    $method->add_input_parameter( name => "status",
                                  description => "Status of the link",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::INTEGER );

    $self->{'dispatch'}->register_method($method);
}

sub on_port_status {
    my $self = shift;
    my $func = shift;
    my $method = GRNOC::RabbitMQ::Method->new( name        => "port_status",
                                               callback    => $func,
                                               description => "Notifies FV of any port status change." );
    
    $method->add_input_parameter( name => "dpid",
                                  description => "The DPID of the switch which fired the port status event",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::NAME_ID);
    
    $method->add_input_parameter( name => "reason",
                                  description => "The reason for the port status must be one of OFPPR_ADD OFPPR_DELETE OFPPR_MODIFY",
                                  required => 1,
                                  pattern => $GRNOC::WebService::Regex::INTEGER);
    
    $method->add_input_parameter( name => "port",
                                  description => "Details about the port that had the port status message generated on it",
                                  required => 1,
                                  schema => { 'type' => 'object',
                                              'properties' => {'port_no'     => {'type' => 'number'},
                                                               'link'        => {'type' => 'number'},
                                                               'name'        => {'type' => 'string'},
                                                               'admin_state' => {'type' => 'string'},
                                                               'status'      => {'type' => 'string'}} } );

    $self->{'dispatch'}->register_method($method);
}

sub on_fv_packet_in {
    my $self = shift;
    my $func = shift;
    my $method = GRNOC::RabbitMQ::Method->new( name        => "fv_packet_in",
                                               callback    => $func,
                                               description => "Notifies FV of any received FV packet." );
    $method->add_input_parameter( name => "src_dpid",
                                  description => "DPID of one node on the link",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::NAME_ID );
    $method->add_input_parameter( name => "src_port",
                                  description => "Port of node a on the link",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::INTEGER );
    $method->add_input_parameter( name => "dst_dpid",
                                  description => "DPID of one node on the link",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::NAME_ID );
    $method->add_input_parameter( name => "dst_port",
                                  description => "Port of node z on the link",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::INTEGER );
    $method->add_input_parameter( name => "timestamp",
                                  description => "When the packet_in was received.",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::INTEGER );

    $self->{'dispatch'}->register_method($method);
}

return 1;
