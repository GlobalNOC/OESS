package OESS::NSI::Server;

use vars qw(@ISA);
@ISA = qw(Exporter SOAP::Server::Parameters);
use SOAP::Lite;

use strict;

use Data::Dumper;
use OESS::DBus;
use OESS::NSI::Utils;
use OESS::NSI::Query;

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
    }else{
	$correlationId = '';
    }
    my $requesterNSA = $envelope->dataof("//Header/nsiHeader/requesterNSA");
    if(defined($requesterNSA)){
        $requesterNSA = $requesterNSA->value;
    }else{
	$requesterNSA = '';
    }
    my $providerNSA = $envelope->dataof("//Header/nsiHeader/providerNSA");
    if(defined($providerNSA)){
        $providerNSA = $providerNSA->value;
    }else{
	$providerNSA = '';
    }
    my $replyTo = $envelope->dataof("//Header/nsiHeader/replyTo");
    if(defined($replyTo)){
        $replyTo = $replyTo->value;
    }else{
	$replyTo = '';
    }

    my $sessionSecurityAttr = $envelope->dataof("//Header/nsiHeader/sessionSecurityAttr");
    if(defined($sessionSecurityAttr)){
        $sessionSecurityAttr = $sessionSecurityAttr->value;
    }else{
	$sessionSecurityAttr = '';
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

    return{ capacity => $cap,
	    directionality => $dir,
	    sourceSTP => $sourceSTP,
	    destSTP => $destSTP}
}

=head2 _parse_schedule{

=cut

sub _parse_schedule{
    my $env = shift;

    my $startTime = $env->dataof('//reserve/criteria/schedule/startTime');
    if(defined($startTime)){
        $startTime = $startTime->value;
    }else{
	$startTime = '';
    }

    my $endTime = $env->dataof('//reserve/criteria/schedule/endTime');
    if(defined($endTime)){
        $endTime = $endTime->value;
    }else{
	$endTime = '';
    }

    my $obj = {startTime => $startTime,
	       endTime => $endTime};

    return $obj;
}

=head2 _parse_serviceType

=cut

sub _parse_serviceType{
    my $env = shift;
    
    my $serviceType = $env->dataof('//reserve/criteria/serviceType');
    if(defined($serviceType)){
        return $serviceType->value;
    }else{
	return '';
    }
}

=head2 _parse_version

=cut

sub _parse_version{
    my $env = shift;
    
    my $version = $env->dataof('//reserve/criteria');
    if(defined($version)){
	
	$version = $version->attr();
    }else{
        $version= '';
    }
    return $version;
}

=head2 _parse_criteria

=cut

sub _parse_criteria{
    my $envelope = shift;

    return {schedule => _parse_schedule($envelope),
	    p2ps => _parse_p2ps($envelope),
	    serviceType => {type => _parse_serviceType($envelope)},
	    version => _parse_version($envelope)
    };
    
}


=head2 reserve

=cut

sub reserve{
    my $self = shift;
    my $envelope = pop;

    my $header = _parse_header($envelope);
    my $connectionId = $envelope->dataof("//reserve/connectionId");
    if(defined($connectionId)){
        $connectionId = $connectionId->value;
    }else{
	$connectionId = '';
    }
    my $gri = $envelope->dataof("//reserve/globalReservationId");
    if(defined($gri)){
        $gri = $gri->value;
    }else{
	$gri = '';
    }
    my $description = $envelope->dataof("//reserve/description")->value;
    my $criteria = _parse_criteria($envelope);

    my $res = _send_to_daemon("reserve", { connectionId => $connectionId,
					   globalReservationId => $gri,
					   description => $description,
					   criteria => $criteria,
					   header => $header 
			      });
    

    my $header = OESS::NSI::Utils::build_header($header);

    my $result;
    if($res < 0){
        $result = SOAP::Data->name( connectionId => 9999999 )->type("");
    }else{
        $result = SOAP::Data->name( connectionId => $res )->type("");
    }
    return ("reserveResponse",$header, $result);
}

=head2 reserveAbort

=cut 

sub reserveAbort{
    my $self = shift;
    my $envelope = pop;


    my $connectionId = $envelope->dataof("//reserveAbort/connectionId");

    if(defined($connectionId)){
        $connectionId =$connectionId->value;
    }

    my $header = _parse_header($envelope);

    my $res = _send_to_daemon("reserveAbort",{ connectionId => $connectionId,
					       header => $header});
    
    my $nsiheader = OESS::NSI::Utils::build_header($header);
    
    return ("acknowledgment",$nsiheader);
}

=head2 reserveCommit

=cut

sub reserveCommit{
    my $self = shift;
    my $envelope = pop;

    my $connectionId = $envelope->dataof("//reserveCommit/connectionId");
    if(defined($connectionId)){
        $connectionId =$connectionId->value;
    }

    my $header = _parse_header($envelope);

    my $res = _send_to_daemon("reserveCommit",{ connectionId => $connectionId,
						header => $header});

    my $nsiheader = OESS::NSI::Utils::build_header($header);

    return ("acknowledgment",$nsiheader);

}

=head2 provision

=cut

sub provision{
    my $self = shift;
    my $envelope = pop;

    my $connectionId = $envelope->dataof("//provision/connectionId");
    if(defined($connectionId)){
        $connectionId =$connectionId->value;
    }

    my $header = _parse_header($envelope);

    my $res = _send_to_daemon("provision",{ connectionId => $connectionId,
					    header => $header});

    my $nsiheader = OESS::NSI::Utils::build_header($header);

    return ("acknowledgment",$nsiheader);
    
}

=head2 release

=cut

sub release{
    my $self = shift;
    my $envelope = pop;

    my $connectionId = $envelope->dataof("//release/connectionId");
    if(defined($connectionId)){
        $connectionId =$connectionId->value;
    }

    my $header = _parse_header($envelope);
    my $res = _send_to_daemon("release",{ connectionId => $connectionId,
					  header => $header});

    my $nsiheader = OESS::NSI::Utils::build_header($header);

    return ("acknowledgment",$nsiheader);

}

=head2 terminate

=cut

sub terminate{
    my $self = shift;
    my $envelope = pop;

    my $connectionId = $envelope->dataof("//terminate/connectionId");
    if(defined($connectionId)){
        $connectionId =$connectionId->value;
    }

    my $header = _parse_header($envelope);

    my $res = _send_to_daemon("terminate",{ connectionId => $connectionId,
					    header => $header});

    my $nsiheader = OESS::NSI::Utils::build_header($header);
    return ("acknowledgment",$nsiheader);

}

=head2 queryRecursive

=cut

sub queryRecursive{
    my $self = shift;
    my $envelope = pop;

    my $connectionId = $envelope->dataof("//queryRecursive/connectionId");
    if(defined($connectionId)){
        $connectionId =$connectionId->value;
    }

    my $gri = $envelope->dataof("//queryRecursive/globalReservationId");
    if(defined($gri)){
        $gri = $gri->value;
    }

    my $header = _parse_header($envelope);

    my $res = _send_to_daemon("queryRecursive", { connectionId => $connectionId,
						  globalReservationId => $gri,
						  header => $header});

    my $nsiheader = OESS::NSI::Utils::build_header($header);

    return ("queryRecursiveResponse",$nsiheader);
}

=head2 querySummary

=cut

sub querySummary{
    my $self = shift;
    my $envelope = pop;
    
    warn "Handling querySummary!!\n";

    my $connectionId = $envelope->dataof("//querySummary/connectionId");
    if(defined($connectionId)){
        $connectionId =$connectionId->value;
    }

    my $gri = $envelope->dataof("//querySummary/globalReservationId");
    if(defined($gri)){
        $gri = $gri->value;
    }

    my $header = _parse_header($envelope);

    my $res = _send_to_daemon("querySummary", { connectionId => $connectionId,
                                                globalReservationId => $gri,
                                                header => $header});
    
    my $nsiheader = OESS::NSI::Utils::build_header($header);
    return ("acknowledgment",$nsiheader);

}

=head2 querySummarySync


=cut

sub querySummarySync{
    my $self = shift;
    my $envelope = pop;


    my $header = _parse_header($envelope);

    warn "Query Summary Sync!!\n";

    #my $query = new OESS::NSI::Query(config_file => '/etc/oess/nsi.conf');
    my @conIds;
    my $connectionId = $envelope->dataof("//querySummarySync/connectionId");
    if(defined($connectionId)){
        @conIds = $connectionId->value;
    }
    my @gris;
    my $gri = $envelope->dataof("//querySummarySync/globalReservationId");
    if(defined($gri)){
        @gris = $gri->value;
    }

    my $query = new OESS::NSI::Query(config_file => '/etc/oess/nsi.conf');    
    my $nsiheader = OESS::NSI::Utils::build_header($header);    
    warn "HERE!\n";
    my $res = $query->do_query_summarysync({ header => $header, connectionIds => \@conIds, gris => \@gris});
    warn "SummarySYnc: " . Data::Dumper::Dumper($res);    
    
    return ("querySummarySyncConfirmed",$nsiheader,$res);
    
}

=head2 queryNotification

=cut

sub queryNotification{
    my $self = shift;
    my $envelope = pop;

    my $connectionId = $envelope->dataof("//queryNotification/connectionId");
    if(defined($connectionId)){
        $connectionId =$connectionId->value;
    }

    my $startNotificationId = $envelope->dataof("//queryNotification/startNotificationId");
    if(defined($startNotificationId)){
        $startNotificationId = $startNotificationId->value;
    }

    my $endNotificationId = $envelope->dataof("//queryNotification/endNotificationId");
    if(defined($endNotificationId)){
        $endNotificationId = $endNotificationId->value;
    }

    my $header = _parse_header($envelope);

    my $res = _send_to_daemon("queryNotification", { connectionId => $connectionId,
                                                     startNotificationId => $startNotificationId,
                                                     endNotificationId => $endNotificationId,
                                                     header => $header});

    my $nsiheader = OESS::NSI::Utils::build_header($header);    

    return ("acknowledgment",$nsiheader);

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
    if(defined($connectionId)){
        $connectionId =$connectionId->value;
    }

    my $startResultId = $envelope->dataof("//queryResult/startResultId");
    if(defined($startResultId)){
        $startResultId = $startResultId->value;
    }

    my $endResultId = $envelope->dataof("//queryResult/endResultId");
    if(defined($endResultId)){
        $endResultId = $endResultId->value;
    }


    my $header = _parse_header($envelope);

    my $res = _send_to_daemon("queryResult", { connectionId => $connectionId,
                                               startResultId => $startResultId,
                                               endResultId => $endResultId,
                                               header => $header});
    my $nsiheader = OESS::NSI::Utils::build_header($header);
    return ("acknowledgment",$nsiheader);
}

=head2 queryResultSync

Unimplemented

=cut
sub queryResultSync{
    my $self = shift;
    my $envelope = pop;

    my $connectionId = $envelope->dataof("//queryNotification/connectionId");
    if(defined($connectionId)){
        $connectionId =$connectionId->value;
    }

    my $startResultId = $envelope->dataof("//queryResult/startResultId");
    if(defined($startResultId)){
        $startResultId = $startResultId->value;
    }

    my $endResultId = $envelope->dataof("//queryResult/endResultId");
    if(defined($endResultId)){
        $endResultId = $endResultId->value;
    }


    my $header = _parse_header($envelope);

    my $nsiheader = OESS::NSI::Utils::build_header($header);
    return ("queryResultSyncConfirmed",$nsiheader);;
}

