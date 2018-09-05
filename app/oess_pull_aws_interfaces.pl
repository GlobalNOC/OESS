#!/usr/bin/perl

# cron script for pulling down aws virtual interface addresses

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Log::Log4perl;
use Paws;
use XML::Simple;

sub new {
    my $class = shift;
    my $self  = {
        config => '/etc/oess/database.xml',
        logger => Log::Log4perl->get_logger('OESS.Cloud.AWS'),
        @_
    };
    bless $self, $class;

    $self->{creds} = XML::Simple::XMLin($self->{config});
    $self->{connections} = {};

    foreach my $conn (@{$self->{creds}->{cloud}->{connection}}) {
        $self->{connections}->{$conn->{interconnect_id}} = $conn;
    }
    return $self;
}

  my $dc = Paws->service(
        'DirectConnect',
        region => $self->{connections}->{$interconnect_id}->{region}
    );

# DescribeVirtualInterfaces

   my $resp = $dc->DescribeVirtualInterfaces(


    );

    warn "interfaces " . Dumper $resp;


