#!/usr/bin/perl

use strict;

use Test::More tests=>4;
use FindBin;
use lib "$FindBin::Bin/../lib";
use OESS::Notification;
use OESS::DBus;

my $bus     = Net::DBus->system;
my $service = $bus->export_service("org.nddi.notification");


my $notification = OESS::Notification->new( 'service'=> $service, 'config_file'=> "$FindBin::Bin/conf/test_config.xml" );

$notification->{'template_path'} = "$FindBin::Bin/../etc/";

ok($notification->send_notification( 
                                      'to' => [{email_address=>'gmcnaugh@grnoc.iu.edu'} ],
                                      'workgroup' => 'OESS Test Fake Workgroup',
                                      'notification_type' => 'provision',
                                      'circuit_data' => { description => 'OESS-FAKE-CIRCUIT-01',
                                                          clr => 'FROM FAKE TO FAKE la la la',
                                                          status => 'primary',
                                                          
                                                        }
                                      
                                    ), "Sent Provisioning Notification"
  );

ok($notification->send_notification(
                                    'to' => [{email_address=>'gmcnaugh@grnoc.iu.edu'} ],
                                      'workgroup' => 'OESS Test Fake Workgroup',
                                      'notification_type' => 'decommission',
                                      'circuit_data' => { description => 'OESS-FAKE-CIRCUIT-01',
                                                          clr => 'FROM FAKE TO FAKE la la la',
                                                          status => 'primary',
                                                          
                                                        }
                                    ), "Sent Circuit Decommission Notification"
  );
ok($notification->send_notification(
                                    'to' => [{email_address=>'gmcnaugh@grnoc.iu.edu'} ],
                                      'workgroup' => 'OESS Test Fake Workgroup',
                                      'notification_type' => 'modify',
                                      'circuit_data' => { description => 'OESS-FAKE-CIRCUIT-01',
                                                          clr => 'FROM FAKE TO FAKE la la la',
                                                          status => 'primary',
                                                          
                                                        }
                                    ), "Sent Circuit Modify Notification"
  );
ok($notification->send_notification(
                                    'to' => [{email_address=>'gmcnaugh@grnoc.iu.edu'} ],
                                      'workgroup' => 'OESS Test Fake Workgroup',
                                      'notification_type' => 'failover_success',
                                      'circuit_data' => { description => 'OESS-FAKE-CIRCUIT-01',
                                                          clr => 'FROM FAKE TO FAKE la la la',
                                                          status => 'primary',
                                                          
                                                        }
                                    
                                    ), "Sent failover Notification"
  );


                                  
