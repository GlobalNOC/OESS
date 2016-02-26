package OESS::RabbitMQ::FV;

use Data::Dumper;
use GRNOC::RabbitMQ::Client;
use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::RabbitMQ::Method;
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
                                  description => "The DPID of the switch which joined",
                                  required => 1,
                                  schema => { "type"       => "object",
                                              "required"   => [ "dpid" ],
                                              "properties" => { "dpid" => { "type" => "number" } }
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
                                  description => "The DPID of the switch which left",
                                  required => 1,
                                  schema => { "type"       => "object",
                                              "required"   => [ "dpid" ],
                                              "properties" => { "dpid" => { "type" => "number" } }
                                            } );
    $self->{'dispatch'}->register_method($method);
}

sub on_link_event {
    my $self = shift;
    my $func = shift;
    my $method = GRNOC::RabbitMQ::Method->new( name        => "link_event",
                                               callback    => $func,
                                               description => "Notifies FV of any link event." );
    $method->add_input_parameter( name => "link",
                                  description => "The state of the link that changed",
                                  required => 1,
                                  schema => { "type"       => "object",
                                              "required"   => [ "a_dpid", "a_port", "z_dpid", "z_port", "status" ],
                                              "properties" => { "a_dpid" => { "type" => "number" },
                                                                "a_port" => { "type" => "number" },
                                                                "z_dpid" => { "type" => "number" },
                                                                "z_port" => { "type" => "number" },
                                                                "status" => { "type" => "number" }
                                                              }
                                            } );
    $self->{'dispatch'}->register_method($method);
}

sub on_port_status {
    my $self = shift;
    my $func = shift;
    my $method = GRNOC::RabbitMQ::Method->new( name        => "port_status",
                                               callback    => $func,
                                               description => "Notifies FV of any port status change." );
    $method->add_input_parameter( name => "port",
                                  description => "The state of the port that changed",
                                  required => 1,
                                  schema => { "type"       => "object",
                                              "required"   => [ "dpid", "reason", "info"],
                                              "properties" => { "dpid"   => { "type" => "number" },
                                                                "reason" => { "type" => "number" },
                                                                "info"   => { "type"        => "object",
                                                                              "port_number" => { "type" => "number" },
                                                                              "link_status" => { "type" => "number" }
                                                                            }
                                                              }
                                            } );
    $self->{'dispatch'}->register_method($method);
}

sub on_fv_packet_in {
    my $self = shift;
    my $func = shift;
    my $method = GRNOC::RabbitMQ::Method->new( name        => "fv_packet_in",
                                               callback    => $func,
                                               description => "Notifies FV of any received FV packet." );

    $method->add_input_parameter( name => "fv_packet_in",
                                  description => "The ",
                                  required => 1,
                                  schema => { "type"       => "fv_packet_in",
                                              "required"   => [ "src_dpid",
                                                                "src_port",
                                                                "dst_dpid",
                                                                "dst_port",
                                                                "timestamp" ],
                                              "properties" => { "src_dpid"  => { "type" => "number" },
                                                                "src_port"  => { "type" => "number" },
                                                                "dst_dpid"  => { "type" => "number" },
                                                                "dst_port"  => { "type" => "number" },
                                                                "timestamp" => { "type" => "number" }
                                                              }
                                            } );
    $self->{'dispatch'}->register_method($method);
}

return 1;
