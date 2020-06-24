#!/usr/bin/perl

=head1 NAME


=cut

our $VERSION = '1.2.5';

use strict;
use warnings;

package OESS::DB;

use GRNOC::Log;
use GRNOC::Config;

use OESS::DB::VRF;
use OESS::DB::Node;
use OESS::DB::Interface;
use OESS::DB::Circuit;
use OESS::DB::Endpoint;

use Data::Dumper;

use DBI;

=head2 new

    my $db = new OESS::DB(config => '/etc/oess/database.xml');

new creates a new C<OESS::DB> connection object. Use this to execute
queries and manage database transactions.

Minimal configuration:

    <configuration>
      <credentials username="" password="" database""/>
    </configuration>

=cut
sub new{
    my $that  = shift;
    my $class = ref($that) || $that;

    my $logger = Log::Log4perl->get_logger("OESS.DB");

    my %args = (
        config => '/etc/oess/database.xml',
        @_
        );

    my $self = \%args;

    bless $self, $class;

    $self->{'logger'} = $logger;

    $self->_process_config($args{'config'});

    $self->_connect_to_db();
    
    return $self;
}

=head2 _connect_to_db

=cut
sub _connect_to_db{
    my $self = shift;
   
    my $creds = $self->{'configuration'}->{'credentials'};
    my $database = $creds->{'database'};
    my $username = $creds->{'username'};
    my $password = $creds->{'password'};

    my $dbh      = DBI->connect("DBI:mysql:$database", $username, $password,
                                {mysql_auto_reconnect => 1 }
        );
    
    if (! $dbh){
        return ;
    }
    $dbh->{'mysql_auto_reconnect'}   = 1;   


    $self->{'dbh'} = $dbh;
}

=head2 _process_config

=cut
sub _process_config{
    my $self = shift;
    my $config = shift;
    
    my $config_filename = $config;
    $config = XML::Simple::XMLin($config_filename);
    my $username = $config->{'credentials'}->{'username'};
    my $password = $config->{'credentials'}->{'password'};
    my $database = $config->{'credentials'}->{'database'};

    $self->{'configuration'} = $config;

}

=head2 execute_query

=cut
sub execute_query{
    my $self = shift;
    my $query = shift;
    my $args = shift;
    my $caller = (caller(1))[3];

    my $sth = $self->{'dbh'}->prepare($query);

    if(!$sth){
        warn "Error in prepare query: $DBI::errstr in $query";
        $self->_set_error("Unable to prepare query: $DBI::errstr in $query");
        return;
    }

    if (! $sth->execute(@$args) ){
        warn "Error in executing query: $caller: $DBI::errstr in $query";
        $self->_set_error("Unable to execute query: $caller: $DBI::errstr in $query");
        return;
    }

    if ($query =~ /^\s*select/i){
        my @array;
        while (my $row = $sth->fetchrow_hashref()){
            push(@array, $row);
        }

         return \@array;
    }

    if ($query =~ /^\s*insert/i){
        my $id = $self->{'dbh'}->{'mysql_insertid'};
        return $id;
    }

    if ($query =~ /^\s*delete/i || $query =~ /^\s*update/i){
        my $count = $sth->rows();
        return $count;
    }
    
    return -1;

}

=head2 start_transaction

    my $error = $db->start_transaction;
    die $error if defined $error;

=cut
sub start_transaction{
    my $self = shift;

    my $ok = $self->{dbh}->begin_work;
    return if $ok;

    my $error = $self->{dbh}->errstr;
    # Logging statement left for legacy cases.
    $self->{logger}->error("Error: $error");

    return $error;
}

=head2 commit

=cut
sub commit{
    my $self = shift;

    $self->{'dbh'}->commit();
}

=head2 rollback

=cut
sub rollback{
    my $self = shift;
    $self->{'dbh'}->rollback();
}

=head2 _set_error

=cut
sub _set_error{
    my $self = shift;
    my $error = shift;
    $self->{'logger'}->error("OESS::DB Error: " . $error);
    $self->{'error'} = $error;
}

=head2 get_error

=cut
sub get_error{
    my $self = shift;
    return $self->{'error'};
}

1;

