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
use constant RESERVATION_COMMIT_FAILED => -20;
use constant RESERVATION_TIMEOUT => -21;
#set our timeout in sec to 5min
use constant RESERVATION_TIMEOUT_SEC => 300;
our @EXPORT_OK = ('ERROR','SUCCESS','UNKNOWN_ERROR', 'UNKNOWN_REQUEST', 'INVALID_REQUEST_PARAMETERS', 'MISSING_REQUEST_PARAMETERS','RSERVATION_SUCCESS','RESERVATION_FAIL');
our %EXPORT_TAGS = ( all => ['ERROR','SUCCESS','UNKNOWN_ERROR', 'UNKNOWN_REQUEST', 'INVALID_REQUEST_PARAMETERS', 'MISSING_REQUEST_PARAMETERS','RSERVATION_SUCCESS','RESERVATION_FAIL']);

=head1 OESS::NSI::Constant

=cut

=head2       DO_PROVISIONING
=head2       DO_RELEASE
=head2       DO_RESERVE_ABORT
=head2       DO_TERMINATE
=head2       ERROR
=head2       MISSING_REQUEST_PARAMETERS
=head2       PROVISIONING_FAILED
=head2       PROVISIONING_SUCCESS
=head2       QUERY_SUMMARY
=head2       RELEASE_FAILED
=head2       RELEASE_SUCCESS
=head2       RESERVATION_COMMIT_CONFIRMED
=head2       RESERVATION_COMMIT_FAILED
=head2       RESERVATION_FAIL
=head2       RESERVATION_SUCCESS
=head2       RESERVATION_TIMEOUT
=head2       RESERVATION_TIMEOUT_SEC
=head2       SUCCESS
=head2       TERMINATION_FAILED
=head2       TERMINATION_SUCCESS
=head2       UNKNOWN_REQUEST

=cut

1;
