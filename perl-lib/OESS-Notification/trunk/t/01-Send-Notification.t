#!/usr/bin/perl

use strict;

use Test::More tests=>4;
use FindBin;
use lib "$FindBin::Bin/../lib";
use OESS::Notification;

my $notification = OESS::Notification->new( 'config_file'=> "$FindBin::Bin/conf/test_config.xml" );

ok($notification->send_notification(  'username' => 'julius_pringrnoc',
                                      'notification_type' => 'provision',
                                      'circuit_data' => { description => 'OESS-FAKE-CIRCUIT-01',
                                                          clr => 'FROM FAKE TO FAKE la la la',
                                                          status => 'primary',
                                                        },
                                      'contact_data' => {
                                                         email_address=>'gmcnaugh@grnoc.iu.edu',
                                                         given_name => 'Grant',
                                                         last_name => 'McNaught'
                                                        }
                                    ), "Sent Provisioning Notification"
  );

ok($notification->send_notification('username' => 'julius_pringrnoc', 
                                    'notification_type' => 'decommission',
                                      'circuit_data' => { description => 'OESS-FAKE-CIRCUIT-01',
                                                          clr => 'FROM FAKE TO FAKE la la la',
                                                          status => 'backup',
                                                        },
                                      'contact_data' => {
                                                         email_address=>'gmcnaugh@grnoc.iu.edu',
                                                         given_name => 'Grant',
                                                         last_name => 'McNaught'
                                                        }
                                    ), "Sent Circuit Decommission Notification"
  );
ok($notification->send_notification('username' => 'julius_pringrnoc', 
                                    'notification_type' => 'modify',
                                      'circuit_data' => { description => 'OESS-FAKE-CIRCUIT-01',
                                                          clr => 'FROM FAKE TO FAKE la la la',
                                                          status => 'backup',
                                                        },
                                      'contact_data' => {
                                                         email_address=>'gmcnaugh@grnoc.iu.edu',
                                                         given_name => 'Grant',
                                                         last_name => 'McNaught'
                                                        }
                                    ), "Sent Circuit Modify Notification"
  );
ok($notification->send_notification('username' => 'julius_pringrnoc', 
                                    'notification_type' => 'failover',
                                      'circuit_data' => { description => 'OESS-FAKE-CIRCUIT-01',
                                                          clr => 'FROM FAKE TO FAKE la la la',
                                                          status=> 'backup',
                                                        },
                                      'contact_data' => {
                                                         email_address=>'gmcnaugh@grnoc.iu.edu',
                                                         given_name => 'Grant',
                                                         last_name => 'McNaught'
                                                        }
                                    ), "Sent failover Notification"
  );


                                  
