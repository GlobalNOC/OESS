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

$CIRCUIT_TYPE = '^(openflow|mpls)$';

=head2 ACL_ALLOW_DENY

Regex for validation of ACL allow/deny entry

=cut

$ACL_ALLOW_DENY = '^(allow|deny)$';
