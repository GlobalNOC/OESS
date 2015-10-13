package OESS::NSI::Server;
use vars qw(@ISA);
@ISA = qw(Exporter SOAP::Server::Parameters);
use SOAP::Lite;

use strict;
use Data::Dumper;
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

    my $res = $client->process_request($method,$data);

    return $res;
}

=head2 _parse_header

=cut

sub _parse_header{
    my $envelope = shift;

    my $protocolVersion = $envelope->dataof("//Envelope/Header/nsiHeader/protocolVersion");
    if(defined($protocolVersion)){
        $protocolVersion = $protocolVersion->value;
    }
    my $correlationId = $envelope->dataof("///Header/nsiHeader/correlationId");
    if(defined($correlationId)){
        $correlationId = $correlationId->value;
    }
    my $requesterNSA = $envelope->dataof("//Header/nsiHeader/requestorNSA");
    if(defined($requesterNSA)){
        $requesterNSA = $requesterNSA->value;
    }
    my $providerNSA = $envelope->dataof("//Header/nsiHeader/providerNSA");
    if(defined($providerNSA)){
        $providerNSA = $providerNSA->value;
    }
    my $replyTo = $envelope->dataof("//Header/nsiHeader/replyTo");
    if(defined($replyTo)){
        $replyTo = $replyTo->value;
    }
    my $sessionSecurityAttr = $envelope->dataof("//Header/nsiHeader/sessionSecurityAttr");
    if(defined($sessionSecurityAttr)){
        $sessionSecurityAttr = $sessionSecurityAttr->value;
    }

    return { protocolVersion => $protocolVersion,
             correlationId => $correlationId,
             requesterNSA => $requesterNSA,
             providerNSA => $providerNSA,
             replyTo => $replyTo,
             sessionSecurityAttr => $sessionSecurityAttr };
}

=head2 _parse_p2ps

=cut

sub _parse_p2ps{
    my $env = shift;

    my $cap = $env->dataof('//reserve/criteria/p2ps/capacity');
    if(defined($cap)){
        $cap = $cap->value;
    }
    
    my $dir = $env->dataof('//reserve/criteria/p2ps/directionality');
    if(defined($dir)){
        $dir = $dir->value;
    }

    my $sourceSTP = $env->dataof('//reserve/criteria/p2ps/sourceSTP');
    if(defined($sourceSTP)){
        $sourceSTP = $sourceSTP->value;
    }

    my $destSTP = $env->dataof('//reserve/criteria/p2ps/destSTP');
    if(defined($destSTP)){
        $destSTP = $destSTP->value;
    }

    return { capacity => $cap,
             directionality => $dir,
             sourceSTP => $sourceSTP,
             destSTP => $destSTP};
}

=head2 _parse_schedule{

=cut

sub _parse_schedule{
    my $env = shift;

    my $startTime = $env->dataof('//reserve/criteria/schedule/startTime');
    if(defined($startTime)){
        $startTime = $startTime->value;
    }

    my $endTime = $env->dataof('//reserve/criteria/schedule/endTime');
    if(defined($endTime)){
        $endTime = $endTime->value;
    }

    return { startTime => $startTime,
             endTime => $endTime};
}

=head2 _parse_serviceType

=cut

sub _parse_serviceType{
    my $env = shift;
    
    my $serviceType = $env->dataof('//reserve/criteria/serviceType');
    if(defined($serviceType)){
        return $serviceType->value;
    }
}

=head2 _parse_criteria

=cut

sub _parse_criteria{
    my $envelope = shift;

    return {schedule => _parse_schedule($envelope),
            p2ps => _parse_p2ps($envelope),
            serviceType => _parse_serviceType($envelope) };

}


=head2 reserve

=cut

sub reserve{
    my $self = shift;
    my $envelope = pop;

    my $header = _parse_header($envelope);
    my $connectionId = $envelope->dataof("//reserve/connectionId");
    my $gri = $envelope->dataof("//reserve/globalReservationId");
    my $description = $envelope->dataof("//reserve/description")->value;
    my $criteria = _parse_criteria($envelope);

    my $res = _send_to_daemon("reserve",{ connectionId => $connectionId,
					  globalReservationId => $gri,
					  description => $description,
					  criteria => $criteria,
					  header => $header }  );


    my $header = SOAP::Header->name( 'header:nsiHeader' => \SOAP::Data->value(
                                         SOAP::Data->name(protocolVersion => $header->{'protocolVersion'}),
                                         SOAP::Data->name(correlationId => $header->{'correlationId'}),
                                         SOAP::Data->name(requesterNSA => $header->{'requesterNSA'}),
                                         SOAP::Data->name(providerNSA => $header->{'providerNSA'}),
                                         SOAP::Data->name(replyTo => undef),
                                         SOAP::Data->name(sessionSecurityAttr => $header->{'sessionSecurityAttr'})))->attr({ 'xmlns:header' => 'http://schemas.ogf.org/nsi/2013/12/framework/headers'});
    my $result = SOAP::Data->name( connectionId => $res);

    return ($header, $result);
}

=head2 reserveAbort

=cut 

sub reserveAbort{
    my $self = shift;
    my $envelope = pop;


    my $connectionId = $envelope->dataof("//reserveAbort/connectionId");
    my $header = _parse_header($envelope);

    my $res = _send_to_daemon("reserveAbort",{ connectionId => $connectionId,
					       header => $header});

    return $res;
}

=head2 reserveCommit

=cut

sub reserveCommit{
    my $self = shift;
    my $envelope = pop;

    my $connectionId = $envelope->dataof("//reserveCommit/connectionId");
    my $header = _parse_header($envelope);

    my $res = _send_to_daemon("reserveCommit",{ connectionId => $connectionId,
						header => $header});

    return $res;

}

=head2 provision

=cut

sub provision{
    my $self = shift;
    my $envelope = pop;

    my $connectionId = $envelope->dataof("//provision/connectionId");
    my $header = _parse_header($envelope);

    my $res = _send_to_daemon("provision",{ connectionId => $connectionId,
					    header => $header});

    return $res;
    
}

=head2 release

=cut

sub release{
    my $self = shift;
    my $envelope = pop;

    my $connectionId = $envelope->dataof("//release/connectionId");
    my $header = _parse_header($envelope);
    my $res = _send_to_daemon("release",{ connectionId => $connectionId,
					  header => $header});

    return $res;

}

=head2 terminate

=cut

sub terminate{
    my $self = shift;
    my $envelope = pop;

    my $connectionId = $envelope->dataof("//terminate/connectionId");
    my $header = _parse_header($envelope);

    my $res = _send_to_daemon("terminate",{ connectionId => $connectionId,
					    header => $header});

    return $res;

}

=head2 queryRecursive

=cut

sub queryRecursive{
    my $self = shift;
    my $envelope = pop;

    my $connectionId = $envelope->dataof("//queryRecursive/connectionId");
    my $gri = $envelope->dataof("//queryRecursive/globalReservationId");
    my $header = _parse_header($envelope);

    my $res = _send_to_daemon("queryRecursive", { connectionId => $connectionId,
						  globalReservationId => $gri,
						  header => $header});

    return $res;
}

=head2 querySummary

=cut

sub querySummary{
    my $self = shift;
    my $envelope = pop;

    my $connectionId = $envelope->dataof("//querySummary/connectionId");
    my $gri = $envelope->dataof("//querySummary/globalReservationId");
    my $header = _parse_header($envelope);

    my $res = _send_to_daemon("querySummary", { connectionId => $connectionId,
                                                  globalReservationId => $gri,
						  header => $header});

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
    my $self = shift;
    my $envelope = pop;

    my $connectionId = $envelope->dataof("//queryNotification/connectionId");
    my $startNotificationId = $envelope->dataof("//queryNotification/startNotificationId");
    my $endNotificationId = $envelope->dataof("//queryNotification/endNotificationId");

    my $header = _parse_header($envelope);

    my $res = _send_to_daemon("queryNotification", { connectionId => $connectionId,
                                                     startNotificationId => $startNotificationId,
                                                     endNotificationId => $endNotificationId,
                                                     header => $header});
    
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
    my $self = shift;
    my $envelope = pop;

    my $connectionId = $envelope->dataof("//queryNotification/connectionId");
    my $startResultId = $envelope->dataof("//queryResult/startResultId");
    my $endResultId = $envelope->dataof("//queryResult/endResultId");

    my $header = _parse_header($envelope);

    my $res = _send_to_daemon("queryResult", { connectionId => $connectionId,
                                               startResultId => $startResultId,
                                               endResultId => $endResultId,
                                               header => $header});
    
    return $res;
}

=head2 queryResultSync

Unimplemented

=cut
sub queryResultSync{
    return;
}
