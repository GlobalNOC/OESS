package OESS::Mock;

use strict;
use warnings;

use Data::Dumper;
use Test::Deep::NoTest;

our $AUTOLOAD;

=head2 new

    my $mock = OESS::MPLS::Device::Mock->new;
    my $out  = ObjectUnderTest(component => $mock);

new creates an object that tracks the subroutines called against
it. This object may be used to pre-define the result of a called
subroutine or validate a subroutine was called.

=cut
sub new {
    my ($class, $args) = @_;
    my $self = {};

    bless $self, $class;

    $self->{conn_obj} = 1;
    return $self;
}

=head2 new_sub

    new_sub(
      name   => 'sum',
      result => 2
    );

new_sub defines a subroutine on this object named C<name> that returns
C<result>.

=cut
sub new_sub {
    my $self = shift;
    my %args = @_;

    my $name = $args{name};
    my $result = $args{result};

    $self->{$name} = {
        count  => 0,
        result => $result
    };
}

=head2 sub_called

    my $err = sub_called(
      name  => 'sum',
      count => 1,               # Optional
      args  => {a => 1, b => 1} # Optional
    );

sub_called validates that C<name> was called C<count> times and was
provided with the specified C<args>. Returns an error string if
unexpected behavior is encountered.

=cut
sub sub_called {
    my $self = shift;
    my %args = @_;

    my $name = $args{name};
    my $args = $args{args};
    my $count = $args{count};

    if (!defined $self->{$name} || $self->{$name}->{count} == 0) {
        return "Method '$name' wasn't called.";
    }

    if (defined $count && $self->{$name}->{count} != $count) {
        my $n = $self->{$name}->{count};
        return "Method '$name' was called $n times, but we expected $count times.";
    }

    if (defined $args) {
        my $ok = eq_deeply($self->{$name}->{args}, $args);
        if (!$ok) {
            return "Method '$name' was called with unexpected arguments: " . Dumper($self->{$name}->{args}) . "\nExpected: " . Dumper($args);
        }
    }

    return undef;
}

=head2 sub_called_config

    my $hash = sub_called_config(
      name  => 'sum'
    );

sub_called_config returns a hash of the registered subs config along
with the most recently used arguments.

=cut
sub sub_called_config {
    my $self = shift;
    my %args = @_;

    my $name = $args{name};

    return $self->{$name};
}

sub AUTOLOAD {
    my $self = shift;
    my @args = @_;

    my @sub  = split('::', $AUTOLOAD);
    my $name = $sub[@sub - 1];

    if (!defined $self->{$name}) {
        $self->{$name} = {
            args   => \@args,
            count  => 0,
            result => undef,
        };
    }

    $self->{$name}->{args}  = \@args;
    $self->{$name}->{count} += 1;
    return $self->{$name}->{result};
}

1;
