#!/usr/bin/perl

use strict;
use warnings;

package OESS::MPLS::Discovery::Interface;

use OESS::Database;
use OESS::DB;
use OESS::DB::Interface;
use OESS::DB::Node;
use Data::Dumper;
use Log::Log4perl;

=head2 new

create a new MPLS Discovery interface handler

=cut

sub new{
    my $class = shift;
    my %args = (
        @_
        );

    my $self = \%args;

    $self->{'logger'} = Log::Log4perl->get_logger('OESS');
    bless $self, $class;

    if(!defined($self->{'db'})){
	if(!defined($self->{'config'})){
	    $self->{'config'} = "/etc/oess/database.xml";
	}
	
	$self->{'db'} = new OESS::DB( config => $self->{'config'} );
    }

    die if(!defined($self->{'db'}));

    return $self;
}

=head2 process_results

processes results and sends them to the db

=cut
sub process_results{
    my $self = shift;
    my %params = @_;
    my $node_name = $params{'node'};
    my $interfaces = $params{'interfaces'};

    $self->{'db'}->start_transaction();

    foreach my $interface (@$interfaces) {
        my $interface_id = OESS::DB::Interface::get_interface(db => $self->{'db'}, node => $node_name, interface => $interface->{'name'});
        if (!defined($interface_id)) {
            $self->{'logger'}->warn("Couldn't find interface creating new");
            my $node = OESS::DB::Node::fetch(db => $self->{'db'}, name => $node_name);
            if (!defined($node)) {
                $self->{'logger'}->warn($self->{'db'}->get_error);
                $self->{'db'}->rollback();
                return;
            }
            my $model = {
                node_id => $node->{'node_id'},
                name => $interface->{'name'},
                operational_state => $interface->{'operational_state'},
                admin_state => $interface->{'admin_state'},
                description => $interface->{'description'},
                vlan_tag_range => "-1",
                mpls_vlan_tag_range => "1-4095",
                capacity_mbps => $interface->{'speed'},
                mtu_bytes => $interface->{'mtu'}
            };
            my $res = OESS::DB::Interface::create( db=>$self->{'db'}, model=>$model);
            if (!defined($res)) {
                $self->{'logger'}->warn($self->{'db'}->get_error);
                $self->{'db'}->rollback();
                return;
            } else {
                next;
            }
        }
        $self->{'logger'}->warn('Found Interface');
        my $intf = OESS::DB::Interface::fetch(db => $self->{'db'}, interface_id=> $interface_id);
        if (!defined($intf)) {
            $self->{'logger'}->warn($self->{'db'}->{'error'});
            $self->{'db'}->rollback();
            return;
        }
        my $updateNeeded = 0;
        my $osUpgrade = 0;
        my $instanUpgrade =0;
        if ((defined $interface->{'speed'} && $intf->{'capacity_mbps'} ne $interface->{'speed'}) || (defined $interface->{mtu} && $intf->{'mtu_bytes'} ne $interface->{'mtu'})) {
            $updateNeeded = 1;
            $instanUpgrade = 1;
            $self->{'logger'}->warn("Needs To upgrade speed");
        }
        if ($intf->{'operational_state'} ne $interface->{'operational_state'}) {
            $updateNeeded = 1;
            $osUpgrade = 1;
            $self->{'logger'}->warn('needs to update operational state');
        }
        if ($updateNeeded == 1) {
            my $result = undef;

            $self->{'logger'}->error("Updating interface");
            if ($osUpgrade == 1  && $instanUpgrade == 1) {
                $self->{'logger'}->warn('update has EVERYTHING');
                $result = OESS::DB::Interface::update(db => $self->{'db'},
                    interface => {
                        interface_id      => $interface_id,
                        operational_state => $interface->{'operational_state'},
                        bandwidth         => $interface->{'speed'},
                        mtu         => $interface->{'mtu'}
                    }
                );
            } elsif ($osUpgrade ==1) {
                $self->{'logger'}->warn('update has operatational_state');
                $result = OESS::DB::Interface::update(db => $self->{'db'},
                    interface => {
                        interface_id      => $interface_id,
                        operational_state => $interface->{'operational_state'}
                    }
                );
            } else {
                $self->{'logger'}->warn('update has speed settings');
                $result = OESS::DB::Interface::update(db => $self->{'db'},
                    interface => {
                        interface_id  => $interface_id,
                        bandwidth => $interface->{'speed'},
                        mtu => $interface->{'mtu'}
                    })
            }
            $self->{'logger'}->warn('update has run');
            if (defined($result)) {
                $self->{'logger'}->warn($self->{'db'}->get_error);
                $self->{'db'}->rollback();
                return;
            }
        }
    }

    # all must have worked, commit and return success
    $self->{'db'}->commit();
    return 1;
}

1;
