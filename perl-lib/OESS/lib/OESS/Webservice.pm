## Common constants and functions used by webservices
##----------------------------------------------------------------------
##
## Copyright 2017 Trustees of Indiana University
##
##   Licensed under the Apache License, Version 2.0 (the "License");
##   you may not use this file except in compliance with the License.
##   You may obtain a copy of the License at
##
##       http://www.apache.org/licenses/LICENSE-2.0
##   Unless required by applicable law or agreed to in writing, software
##   distributed under the License is distributed on an "AS IS" BASIS,
##   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
##   See the License for the specific language governing permissions and
##   limitations under the License.

package OESS::Webservice;

use strict;
use warnings;

=head2 CIRCUIT_TYPE

Regex for validation of circuit (and link!) types

=cut

our $CIRCUIT_TYPE = '^(openflow|mpls)$';

=head2 CIRCUIT_TYPE_WITH_ALL

Regex for validation of circuit (and link!) types, along with 'all' option

=cut

our $CIRCUIT_TYPE_WITH_ALL = '^(openflow|mpls|all)$';

=head2 ACL_ALLOW_DENY

Regex for validation of ACL allow/deny entry

=cut

our $ACL_ALLOW_DENY = '^(allow|deny)$';

=head2 validate_vlan_tag_range

    my ($vlan_range, $err) = validate_vlan_tag_range('1-4095');
    die $err if defined $err;

Validate a string representing a list of VLAN tag ranges. Expects a
string formatted like '100-300, 400-400, 500-600'. Returns a cleaned up
version of the string for storage.

=cut

sub validate_vlan_tag_range {
    my $str = shift;

    $str =~ s/^[,\s]*|[,\s]*$//g; # Strip leading/trailing commas and whitespace
    my @ranges = split(',', $str);

    # Filter out any empty strings
    my $filtered_ranges = [];
    foreach my $range (@ranges) {
        # Strip leading/trailing whitespace
        $range =~ s/^\s*|\s*$//g;
        if ($range ne '') {
            push @$filtered_ranges, $range;
        }
    }

    # 1. Validate range formated exactly like "{lowerNumber}-{higherNumber}"
    # 2. Validate lowerNumber < higherNumber && 1 <= numbers >= 4095
    foreach my $range (@$filtered_ranges) {
        if ($range !~ /^\d+-\d+$/) {
            return (undef, 'Input must be a comma separated list of VLAN ranges. Ex 1-4095');
        }

        my @parts = split('-', $range);
        $parts[0] = int($parts[0]);
        $parts[1] = int($parts[1]);
        if ($parts[0] < 1 || $parts[0] > 4095 || $parts[1] < 1 || $parts[1] > 4095 || $parts[0] > $parts[1]) {
            return (undef, 'Input must be a comma separated list of VLAN ranges. Ex 1-4095');
        }
    }

    return (join(",", @$filtered_ranges), undef);
}