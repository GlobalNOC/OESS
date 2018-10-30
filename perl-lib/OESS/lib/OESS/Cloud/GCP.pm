package OESS::Cloud::GCP;

use strict;
use warnings;

use Data::Dumper;
use Log::Log4perl;
use WebService::Google::Client;
use XML::Simple;

=head1 OESS::Cloud::GCP

B<Configuration:>

The credentials for each interconnect must be defined under the
C<cloud> tag in C</etc/oess/database.xml>. Valid interconnect type for
GCP connections is C<gcp-partner-interconnect>.

    <connection region="us-east-1"
                interconnect_type="gcp-partner-interconnect"
                interconnect_id="dxcon-aaa12345"
                access_key="..."
                secret_key="..."
                workgroup="GCP" />

Associate credentials with a physical endpoint by setting the
C<interconnect_id> of the interface in the OESS database.

=cut

=head2 new

    my $gcp = OESS::Cloud::GCP->new();

=cut
sub new {
    my $class = shift;
    my $self  = {
        config => '/etc/oess/database.xml',
        logger => Log::Log4perl->get_logger('OESS.Cloud.GCP'),
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

sub query {
    my $self = shift;

    my $gapi = WebService::Google::Client->new(debug => 0);
    my $file = './gapi.conf';

    if (!$gapi->auth_storage->file_exists($file)) {
        warn "JSON file with tokens doesn't exist!";
        exit 1;
    }

    $gapi->auth_storage->setup({ type => 'jsonfile', path => $file });
    # $gapi->user($user);

    my $t = $gapi->Calendar->CalendarList->list->json;
    warn Dumper($t);
    
    return 1;
}
    
