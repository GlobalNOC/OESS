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
Log::Log4perl::init_and_watch("/etc/oess/logging.conf");

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
        my $intf = new OESS::Interface(db => $self->{'db'}, node => $node_name, name => $interface->{'name'});
        if (!defined($intf)) {
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
            my ($res,$err) = OESS::DB::Interface::create( db=>$self->{'db'}, model=>$model);
            if (defined($err)) {
                $self->{'logger'}->warn($err);
                $self->{'db'}->rollback();
                return;
            } else {
                next;
            }
        } else {
        $self->{'logger'}->warn('Found Interface');
        if (!defined($intf)) {
            $self->{'logger'}->warn($self->{'db'}->{'error'});
            $self->{'db'}->rollback();
            return;
        }
        if(defined $interface->{operational_state}) {
            $intf->operational_state($interface->{operational_state});
        }
        if(defined $interface->{speed} && $interface->{speed} ne 0){
            $intf->bandwidth($interface->{speed});
        }
        if(defined $interface->{mtu} && $interface->{mtu} ne 0){
            $intf->mtu($interface->{mtu});
        }
        my $res = $intf->update_db();
        if (!defined($res)) {
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
