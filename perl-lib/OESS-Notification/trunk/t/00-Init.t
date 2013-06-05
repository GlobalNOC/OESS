#!/usr/bin/perl

use strict;

use Test::More tests=> 2;
use FindBin;
use lib "$FindBin::Bin/../lib";

require_ok( 'OESS::Notification') or BAIL_OUT("Couldn't load OESS::Notification, no point in continuing");

can_ok('OESS::Notification', qw(new get_notification_data send_notification circuit_notification) ) ;



