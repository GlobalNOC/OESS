package OESS::Cloud::Azure;

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Log::Log4perl;

=head1 OESS::Cloud::Azure

=cut

=head2 new

    my $azure = OESS::Cloud::Azure->new();

=cut
sub new {
    my $class = shift;
    my $args  = {
        config => '/etc/oess/database.xml',
        logger => Log::Log4perl->get_logger('OESS.Cloud.Azure'),
        @_
    };
    my $self = bless $args, $class;

    $self->{creds} = XML::Simple::XMLin($self->{config});
    $self->{connections} = {};

    foreach my $conn (@{$self->{creds}->{cloud}->{connection}}) {
        if ($conn->{interconnect_type} ne 'azure-expressroute') {
            next;
        }
        $self->{connections}->{$conn->{interconnect_id}} = $conn;
    }

    return $self;
}

return 1;
