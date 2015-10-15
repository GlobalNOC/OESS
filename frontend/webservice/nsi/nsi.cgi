#!/usr/bin/perl

use strict;
use warnings;

use OESS::DBus;
use OESS::NSI::Server;
use Data::Dumper;
use SOAP::Lite;
use SOAP::Transport::HTTP;

#sub SOAP::Deserializer::typecast {
#    my ($self, $value, $name, $attrs, $children, $type) = @_;   
#    warn "Value: " . Data::Dumper::Dumper($value);
#    warn "Name: " . Data::Dumper::Dumper($name);
#    warn "ATTRS: " . Data::Dumper::Dumper($attrs);
#    warn "Children: " . Data::Dumper::Dumper($children);
#    warn "Type: " . Data::Dumper::Dumper($type);

#    if(!defined($type)){
#        return $value;
#    }elsif($type =~ /^{http:\/\/schemas.ogf.org\/nsi\/2013\/12\/framework\/types}/){
#        return $value;
#    }elsif($type =~ /^{http:\/\/schemas.ogf.org\/nsi\/2013\/12\/connection\/provider}/){
#        return $value;
#    }elsif($type =~ /^{http:\/\/schemas.ogf.org\/nsi\/2013\/12\/framework\/headers}/){
#        return $value;
#    }elsif($type =~ /^{http:\/\/schemas.ogf.org\/nsi\/2013\/12\/services\/types}/){
#        return $value;
#    }elsif($type =~ /^{http:\/\/schemas.ogf.org\/nsi\/2013\/12\/connection\/types}/){
#        return $value;
#    }
#    return undef;
#}

SOAP::Transport::HTTP::CGI->dispatch_with({'http://schemas.ogf.org/nsi/2013/12/connection/types' => 'OESS::NSI::Server'})->on_action(
    sub {
        (my $action = shift) =~ s/^("?)(.+)\1$/$2/;
        return $action;
    })->handle;
