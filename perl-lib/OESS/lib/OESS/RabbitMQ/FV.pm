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
    $self->{'fv'}     = GRNOC::RabbitMQ::Client->new( host => $config->{'rabbitMQ'}->{'host'},
                                                      port => $config->{'rabbitMQ'}->{'port'},
                                                      user => $config->{'rabbitMQ'}->{'user'},
                                                      pass => $config->{'rabbitMQ'}->{'pass'},
                                                      exchange => 'OESS',
                                                      queue => 'OF.FV' );
    $self->{'nox'}    = GRNOC::RabbitMQ::Client->new( host => $config->{'rabbitMQ'}->{'host'},
                                                      port => $config->{'rabbitMQ'}->{'port'},
                                                      user => $config->{'rabbitMQ'}->{'user'},
                                                      pass => $config->{'rabbitMQ'}->{'pass'},
                                                      exchange => 'OESS',
                                                      queue => 'OF.NOX' );
    $self->{'dispatch'} = GRNOC::RabbitMQ::Dispatcher->new( host => $config->{'rabbitMQ'}->{'host'},
                                                            port => $config->{'rabbitMQ'}->{'port'},
                                                            user => $config->{'rabbitMQ'}->{'user'},
                                                            pass => $config->{'rabbitMQ'}->{'pass'},
                                                            exchange => 'OESS',
                                                            queue => 'OF.NOX' );
    return $self;
}

sub start {
    my $self = shift;
    $self->{'dispatch'}->start_consuming();
}

sub register_for_fv_in {
    my $self = shift;
    my $discovery_vlan = shift;

    $self->{'nox'}->register_for_fv_in(discovery_vlan => $discovery_vlan);
}

sub send_fv_link_event {
    my $self       = shift;
    my $link_name  = shift;
    my $link_state = shift;
 
    $self->{'fv'}->fv_link_event( link_name => $link_name,
                                  state     => $link_state );
}

sub send_fv_packets {
    my $self           = shift;
    my $interval       = shift;
    my $discovery_vlan = shift;
    my $packets        = shift;

    $self->{'fv'}->send_fv_packets( interval       => $interval,
                                    discovery_vlan => $discovery_vlan,
                                    packets        => $packets );
}

sub on_datapath_join {
    my $self = shift;
    my $func = shift;
    my $method = GRNOC::RabbitMQ::Method->new( name        => "datapath_join",
                                               callback    => $func,
                                               description => "Adds datapath to FV's internal nodes" );
    $method->add_input_parameter( name => "dpid",
                                  description => "Adds datapath to FV's internal nodes",
                                  required => 1,
                                  pattern  => $GRNOC::WebService::Regex::NAME_ID );
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
