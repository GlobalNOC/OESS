#!/usr/bin/perl

# cron script for pulling down aws virtual interface addresses

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Log::Log4perl;
use Paws;
use XML::Simple;

my $self;

sub new {
    #my $class = shift;
    $self  = {
        config => '/etc/oess/database.xml',
        logger => Log::Log4perl->get_logger('OESS.Cloud.AWS'),
        @_
    };
    #bless $self, $class;

    $self->{creds} = XML::Simple::XMLin($self->{config});
    $self->{connections} = {};

    foreach my $conn (@{$self->{creds}->{cloud}->{connection}}) {
        $self->{connections}->{$conn->{interconnect_id}} = $conn;
    }
    #return $self;
}

new();

#warn "self-connections " . Dumper $self->{connections};
#warn "self-creds " . Dumper $self->{creds};

# old
# region => $self->{connections}->{$interconnect_id}->{region}

  my $dc = Paws->service(
        'DirectConnect',
        region => "us-east-1"
    );

# DescribeVirtualInterfaces

   my $resp = $dc->DescribeVirtualInterfaces(


    );

    warn "interfaces " . Dumper $resp;


