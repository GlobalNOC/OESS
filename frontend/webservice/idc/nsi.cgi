#!/usr/bin/perl

use strict;
use warnings;

use OESS::DBus;
use OESS::NSI::Server;
use Data::Dumper;
use SOAP::Lite;
use SOAP::Transport::HTTP;

sub new_handler{

    SOAP::Trace::trace('()');
    my $self = shift;
    $self = $self->new if !ref $self; # inits the server when called in a static context
    $self->init_context();
    # we want to restore it when we are done
    local $SOAP::Constants::DEFAULT_XML_SCHEMA
        = $SOAP::Constants::DEFAULT_XML_SCHEMA;

    # SOAP version WILL NOT be restored when we are done.
    # is it problem?

    my $result = eval {
        local $SIG{__DIE__};
        # why is this here:
        $self->serializer->soapversion(1.1);
        my $request = eval { $self->deserializer->deserialize($_[0]) };
 
        die SOAP::Fault
            ->faultcode($SOAP::Constants::FAULT_VERSION_MISMATCH)
            ->faultstring($@)
            if $@ && $@ =~ /^$SOAP::Constants::WRONG_VERSION/;

        die "Application failed during request deserialization: $@" if $@;
        my $som = ref $request;
        die "Can't find root element in the message"
            unless $request->match($som->envelope);
        $self->serializer->soapversion(SOAP::Lite->soapversion);
        $self->serializer->xmlschema($SOAP::Constants::DEFAULT_XML_SCHEMA
            = $self->deserializer->xmlschema)
            if $self->deserializer->xmlschema;

        die SOAP::Fault
            ->faultcode($SOAP::Constants::FAULT_MUST_UNDERSTAND)
            ->faultstring("Unrecognized header has mustUnderstand attribute set to 'true'")
            if !$SOAP::Constants::DO_NOT_CHECK_MUSTUNDERSTAND &&
            grep {
                    $_->mustUnderstand
                    && (!$_->actor || $_->actor eq $SOAP::Constants::NEXT_ACTOR)
        } $request->dataof($som->headers);
        die "Can't find method element in the message"
            unless $request->match($som->method);
        # TODO - SOAP::Dispatcher plugs in here
        # my $handler = $self->dispatcher->find_handler($request);
        my($class, $method_uri, $method_name) = $self->find_target($request);
        my @results = eval {
            local $^W;
            my @parameters = $request->paramsin;

            # SOAP::Trace::dispatch($fullname);
            SOAP::Trace::parameters(@parameters);

            push @parameters, $request
                if UNIVERSAL::isa($class => 'SOAP::Server::Parameters');

            no strict qw(refs);
          SOAP::Server::Object->references(
                defined $parameters[0]
                && ref $parameters[0]
                && UNIVERSAL::isa($parameters[0] => $class)
              ? do {
                  my $object = shift @parameters;
                SOAP::Server::Object->object(ref $class
                            ? $class
                            : $object
                        )->$method_name(SOAP::Server::Object->objects(@parameters)),

                        # send object back as a header
                        # preserve name, specify URI
                          SOAP::Header
                            ->uri($SOAP::Constants::NS_SL_HEADER => $object)
                            ->name($request->dataof($som->method.'/[1]')->name)
              } # end do block

                    # SOAP::Dispatcher will plug-in here as well
                    # $handler->dispatch(SOAP::Server::Object->objects(@parameters)
              : $class->$method_name(SOAP::Server::Object->objects(@parameters)) );
        }; # end eval block
        SOAP::Trace::result(@results);

        # let application errors pass through with 'Server' code
        die ref $@
            ? $@
            : $@ =~ /^Can\'t locate object method "$method_name"/
                ? "Failed to locate method ($method_name) in class ($class)"
                : SOAP::Fault->faultcode($SOAP::Constants::FAULT_SERVER)->faultstring($@)
                if $@;

        my $method_response = shift(@results);
        $self->serializer->encodingStyle('');
        $self->serializer->register_ns("http://schemas.ogf.org/nsi/2013/12/connection/types","ctypes");
        my $result = $self->serializer
            ->prefix('s') # distinguish generated element names between client and server
            #->uri($method_uri)
            ->envelope(response => "ctypes:" . $method_response, @results);
        
        $result =~ s/xsi:nil=\"true\"//g;
        
        return $result;
    };

}

*{SOAP::Server::handle} = \&new_handler;

SOAP::Transport::HTTP::CGI->dispatch_with({'http://schemas.ogf.org/nsi/2013/12/connection/types' => 'OESS::NSI::Server'})->on_action(
    sub {
        (my $action = shift) =~ s/^("?)(.+)\1$/$2/;
        return $action;
    })->handle;
