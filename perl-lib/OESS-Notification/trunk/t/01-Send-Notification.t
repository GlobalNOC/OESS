#!/usr/bin/perl

use strict;

use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use OESS::Notification;

my $notification = OESS::Notification->new( 'config_file'=> "$FindBin::Bin/conf/test_config.xml" );

ok($notification->send_notification( 'notification_type' => 'provision',
                                      'circuit_data' => { circuit_name => 'OESS-FAKE-CIRCUIT-01',
                                                          clr => 'FROM FAKE TO FAKE la la la',
                                                        },
                                      'contact_data' => {
                                                         email_address=>'gmcnaugh@grnoc.iu.edu',
                                                         given_name => 'Grant',
                                                         last_name => 'McNaught'
                                                        }
                                    ), "Sent Provisioning Notification"
  );

                                  
