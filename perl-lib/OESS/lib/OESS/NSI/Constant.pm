#!/usr/bin/perl

package OESS::NSI::Constant;

use strict;
use warnings;

use base "Exporter";

use constant ERROR => -1;
use constant SUCCESS => 0;
use constant UNKNOWN_ERROR => -2;
use constant UNKNOWN_REQUEST => -3;
use constant INVALID_REQUEST_PARAMETERS => -4;
use constant MISSING_REQUEST_PARAMETERS => -5;
use constant RESERVATION_SUCCESS => -6;
use constant RESERVATION_FAIL => -7;
use constant RESERVATION_COMMIT_CONFIRMED => -8;
use constant PROVISIONING_SUCCESS => -9;
use constant PROVISIONING_FAILED => -10;
use constant TERMINATION_SUCCESS => -11;
use constant RELEASE_SUCCESS => 12;
use constant TERMINATION_FAILED => -13;
use constant DO_PROVISIONING => -14;
use constant DO_TERMINATE => -15;
use constant QUERY_SUMMARY => -16;
use constant DO_RELEASE => -17;
use constant RELEASE_FAILED => -18;
use constant DO_RESERVE_ABORT => -19;
our @EXPORT_OK = ('ERROR','SUCCESS','UNKNOWN_ERROR', 'UNKNOWN_REQUEST', 'INVALID_REQUEST_PARAMETERS', 'MISSING_REQUEST_PARAMETERS','RSERVATION_SUCCESS','RESERVATION_FAIL');
our %EXPORT_TAGS = ( all => ['ERROR','SUCCESS','UNKNOWN_ERROR', 'UNKNOWN_REQUEST', 'INVALID_REQUEST_PARAMETERS', 'MISSING_REQUEST_PARAMETERS','RSERVATION_SUCCESS','RESERVATION_FAIL']);

=head1 OESS::NSI::Constant

=cut

1;
