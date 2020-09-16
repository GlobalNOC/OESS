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

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.Discovery.Interface');
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
        my $intf = new OESS::Interface(db => $self->{'db'}, node => $node_name, name => $interface->{'name'});
        if (!defined $intf) {
            $self->{'logger'}->info("New interface $interface->{name} on $node_name found.");

            my $node = OESS::DB::Node::fetch(db => $self->{'db'}, name => $node_name);
            if (!defined $node) {
                $self->{'logger'}->error($self->{'db'}->get_error);
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
            my ($res, $err) = OESS::DB::Interface::create(db => $self->{'db'}, model => $model);
            if (defined $err) {
                $self->{'logger'}->error($err);
                $self->{'db'}->rollback();
                return;
            }
        } else {
            $intf->operational_state($interface->{operational_state});
            $intf->admin_state($interface->{admin_state});
            $intf->bandwidth($interface->{speed});
            $intf->mtu($interface->{mtu});

            my $res = $intf->update_db();
            if (!defined $res) {
                $self->{'logger'}->error($self->{'db'}->get_error);
                $self->{'db'}->rollback();
                return;
            }
        }
    }

    $self->{'db'}->commit();
    return 1;
}

1;
