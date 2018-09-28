#!/usr/bin/perl

use strict;
use warnings;

package OESS::Config;

use XML::Simple;

=head1 NAME

OESS::Config

=cut

=head1 VERSION

2.0.0

=cut

=head1 SYNOPSIS

use OESS::Config

my $config = OESS::Config->new();

my $local_as = $config->local_as();
my $db_creds = $config->db_credentials();
my $db_server = $config->db_server();

=cut

=head2 new

=cut
sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS.Config");    

    my %args = (
        config_filename => '/etc/oess/database.xml' ,
        @_,
        );

    my $self = \%args;

    

    bless $self, $class;

    $self->{'logger'} = $logger;

    $self->_process_config();

    return $self;
}

=head2 _process_config

=cut
sub _process_config{
    my $self = shift;

    my $config = XML::Simple::XMLin($self->{'config_filename'});
    $self->{'config'} = $config;
}

=head2 local_as

returns the configured local_as number

=cut
sub local_as{
    my $self = shift;

    return $self->{'config'}->{'local_as'};
}

=head2 db_credentials

=cut
sub db_credentials{
    my $self = shift;

    my $creds = $self->{'config'}->{'credentials'};
    my $database = $creds->{'database'};
    my $username = $creds->{'username'};
    my $password = $creds->{'password'};

    return {database => $database,
            username => $username,
            password => $password};
}

=head2 get_cloud_config

=cut
sub get_cloud_config{
    my $self = shift;

    return $self->{'config'}->{'cloud'};
}

=head2 base_url

=cut
sub base_url{
    my $self = shift;
    return $self->{'config'}->{'base_url'};
}

1;
