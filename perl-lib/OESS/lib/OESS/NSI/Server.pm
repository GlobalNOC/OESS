#!/usr/bin/perl

package OESS::NSI::Server;

use strict;
use warnings;

use vars qw(@ISA);
@ISA = qw(Exporter SOAP::Sever::Parameters);
use SOAP::Lite;

use OESS::DBus;


sub _send_to_daemon{
    my $method = shift;
    my $data = shift;

    my $bus = Net::DBus->system;

    my $client;
    my $service;

    eval {
        $service = $bus->get_service("org.nddi.nsi");
        $client  = $service->get_object("/controller1");
    };

    if ($@) {
        warn "Error in _connect_to_fwdctl: $@";
    }
        
    if ( !defined($client) ) {
        return;
    }

    $client->process_request();
   
}


=head2 reserve

=cut

sub reserve{

    my $self = shift;
    my $envelope = pop;

    warn Data::Dumper::Dumper($envelope);
    
    my $connectionId = $envelope->dataof("//reserve/connectionId");
    my $gri = $envelope->dataof("//reserve/globalReservationId");;
    my $description = $envelope->dataof("//reserve/description");;
    my $criteria = $envelope->dataof("//reserve/criteria");;

    my $res = _send_to_daemon("reserve",{ connectionID => $connectionId,
					  globalReservationId => $gri,
					  description => $description,
					  criteria => $criteria,
					  replyTo => $replyTo }  );

    return $res;
}

=head2 reserveAbort

=cut 

sub reserveAbort{
    my $connectionId = shift;

    my $res = _send_to_daemon("reserveAbort",{ connectionID => $connectionId,
					       replyTo=> $replyTo});

    return $res;
}

=head2 reserveCommit

=cut

sub reserveCommit{
    
    my $connectionId = shift;

    my $res = _send_to_daemon("reserveCommit",{ connectionID => $connectionId,
						replyTo=> $replyTo});

    return $res;

}

=head2 provision

=cut

sub provision{
    my $connectionId = shift;

    my $res = _send_to_daemon("provision",{ connectionID => $connectionId,
					    replyTo=> $replyTo});

    return $res;
    
}

=head2 release

=cut

sub release{
    
    my $connectionId = shift;

    my $res = _send_to_daemon("release",{ connectionID => $connectionId,
					  replyTo=> $replyTo});

    return $res;

}

=head2 terminate

=cut

sub terminate{

    my $connectionId = shift;

    my $res = _send_to_daemon("terminate",{ connectionID => $connectionId,
					    replyTo=> $replyTo});

    return $res;

}

=head2 queryRecursive

=cut

sub queryRecursive{
    my $connectionId = shift;
    my $gri = shift;

    my $res = _send_to_daemon("queryRecursive", { connectionID => $connectionId,
						  globalReservationId => $gri,
						  replyTo=> $replyTo});

    return $res;
}

=head2 querySummary

=cut

sub querySummary{

    my $connectionId = shift;
    my $gri = shift;

    my $res = _send_to_daemon("queryRecursive", { connectionID => $connectionId,
                                                  globalReservationId => $gri,
						  replyTo=> $replyTo});

    return $res;

}

=head2 querySummarySync

Unimplemented

=cut

sub querySummarySync{
    return;
}

=head2 queryNotification

=cut

sub queryNotification{

    my $connectionId = shift;
    my $startNotificationId = shift;
    my $endNotificationId = shift;

    my $res = _send_to_daemon("queryRecursive", { connectionID => $connectionId,
                                                  startNotificationId => $startNotificationId,
						  endNotificationId => $endNotificationId,
						  replyTo=> $replyTo});

    return $res;

}

=head2 queryNotificationSync

Unimplemented

=cut

sub queryNotificationSync{
    return;
}

=head2 queryResult

=cut

sub queryResult{
    my $connectionId = shift;
    my $startResultId = shift;
    my $endResultId = shift;

    my $connectionId = shift;
    my $gri = shift;

    my $res = _send_to_daemon("queryRecursive", { connectionID => $connectionId,
                                                  startResultId => $startResultId,
						  endResultId => $endResultId,
						  replyTo=> $replyTo});

    return $res;
}

=head2 queryResultSync

Unimplemented

=cut
sub queryResultSync{
    return;
}
