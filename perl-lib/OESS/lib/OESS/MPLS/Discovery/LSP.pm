use OESS::Database;

use Log::Log4perl;
use AnyEvent;


sub new{
    my $class = shift;
    my %args = (
        @_
        );

    my $self = \%args;

    $self->{'logger'} = Log::Log4perl->get_logger('OESS.MPLS.Discovery');
    bless $self, $class;

    if(!defined($self->{'config'})){
        $self->{'config'} = "/etc/oess/database.xml";
    }

    $self->{'db'} = OESS::Database->new( config_file => $self->{'config'} );

    die if(!defined($self->{'db'}));

    return $self;
}

sub process_results{
    my $self = shift;
    my %params = @_;

    return 1;
}



sub check_nodes_list {
    my $nodes-db = get_nodes_from_db();
    my $nodes-net = get_nodes_from_net();
    # we check whether both lists have the same length. If that is true, and each node
    # from the db is in the net list we are good. Everything else is a change, and needs to be reported.
    if (len($nodes-db) == len($nodes-net)) {    
        Foreach $node in $nodes-db {
            if (!exists $node{$nodes-net}) {
                # At least one node from the db is not in the net list, raise alarm
                raise_node_alarm($node);
                next; 
            }
        }
    }
    else
    { 
        # the two lists have different length, we need to figure out what happened.
        # at this point nodes might have joined or left or both, so we will check for this
        # and raise the needed events.
        # First check whether a node left:
        Foreach $node in $nodes-db {
            if (!exists $node{$nodes-net}) {
                # At least one node from the db is not in the net list,
                # that means the node left the network
                raise_node_alarm_node_left($node);
                next; 
            }
        }
        #next, let us check whether a node joined, means was not in the db, but found on the network
        Foreach $node in $nodes-net {
            if (!exists $node{$nodes-db}) {
                # At least one node from the db is not in the net list,
                # that means the node joined the network
                raise_node_alarm_node_joined($node);
                next; 
            }
        }
        
        
    }

sub check_paths_per_node {
    # We call this only when we know that there is no node join or remove to be processed.  
    # for every node in the network, we check that every db side path is on the device, 
    # and every network path is in the db. By that we find out whether we lost an LSP
    my $nodes-db = get_nodes_from_db();
    
    Foreach $node in $nodes-db {
        my $paths-db = get_paths_for_node_db(node);
        my $paths-net = get_paths_for_node_net(node);
        #Now we check if a path is in the db, but not in the net, which means the LSP was removed
        Foreach ($path in $paths-db) {
            if (!exists $path{$nodes-net}) {
                # At least one path on the node from the db is not in the net list,
                # that means the path got removed
                raise_node_alarm_path_removed($node, $path);
                next; 
            }
            else {
                # this path seems to be ok, so we now can check the path details
                # and make sure it is up and running as expected
                check_path_details($node, $path);
            }
        }
        # Now we do it the other way around, and by that checking whether a path was added
        Foreach ($path in $paths-net) {
            if (!exists $path{$nodes-db}) {
                # At least one path on the node from the net is not in the db list,
                # that means the path got added
                raise_node_alarm_path_added($node, $path);
                next; 
            }
            #Is doing the details check twice expensive? if so, we need to avoid it, for now its easier
            else {
                # this path seems to be ok, so we now can check the path details
                # and make sure it is up and running as expected
                check_path_details($node, $path);
            }
            
        }
        
    }        
        

sub get_nodes_from_net(){
    # This function parses the nodes out of the object passed over, and presents them 
    # in an hash that gets returned
}

sub get_nodes_from_db(){
    #this function queries the database, and presents all the nodes returned in an hash
    #same structure as get_nodes_from_net
}
    
sub get_paths_for_node_db($node){
    #This function returns all paths that existing on the node from the db view
    #perhaps better to write seperate functions per lsp type.
}
sub get_paths_for_node_db($node){
    #This function returns all paths that existing on the node from the net view
    #perhaps better to write seperate functions per lsp type.
}
sub raise_node_alarm_node_left($node) {
    #this function gets called when a node left the network, and triggers the related events
}

sub raise_node_alarm_node_joined($node){
    #this function gets called when a node left the network, and triggers the related events
}

sub raise_node_alarm_path_removed($node, $path);{
    #This function triggers all events needed for a removed path. It gets node and path 
    #passed into it
}

sub raise_node_alarm_path_added($node, $path);{
    #This function triggers all events needed for a surprise path discovered. 
    #It gets node and path passed into it.
}

sub check_path_details($node, $path){
    #This will be called when node and path seems correct. It now checks all the 
    #details to make sure things are operating correct
    #We need to define our list here, and create the relevant eventhandlers.
    #might make sense to do it per path type 
} 






sub test {
    print ($VAR1[0]);
}




$VAR1 = {
    'mx240-r4' => {
                          'pending' => 0,
                          'results' => [
			      {
                                           'session_type' => 'Ingress',
                                           'sessions' => [
					       {
                                                             'name' => 'L3VPN-R4-to-R0',
                                                             'destination-address' => '172.16.0.10',
                                                             'description' => '',
                                                             'lsp-state' => 'Up',
                                                             'lsp-type' => 'Static Configured',
                                                             'active-path' => '(primary)',
                                                             'egress-label-operation' => 'Penultimate hop popping',
                                                             'paths' => [
								 {
                                                                            'path-state' => 'Up',
                                                                            'name' => '',
                                                                            'explicit-route' => {
                                                                                                  'explicit-route-type' => '',
                                                                                                  'addresses' => [
                                                                                                                   '172.16.0.44'
                                                                                                                 ]
									    },
                                                                            'setup-priority' => '4',
                                                                            'smart-optimize-timer' => '600',
                                                                            'path-active' => '',
                                                                            'received-rro' => 'Received RRO (ProtectionFlag 1=Available 2=InUse 4=B/W 8=Node 10=SoftPreempt 20=Node-ID):
      172.16.0.44',
                                                                            'title' => 'Primary',
                                                                            'hold-priority' => '4'
								 }
                                                                        ],
                                                             'route-count' => '0',
                                                             'revert-timer' => '600',
                                                             'source-address' => '172.16.0.14',
                                                             'load-balance' => 'random',
                                                             'attributes' => {
                                                                               'encoding-type' => 'Packet',
                                                                               'switching-type' => '',
                                                                               'gpid' => ''
							     }
					       },
					       {
                                                             'name' => 'L3VPN-R4-to-R1',
                                                             'destination-address' => '172.16.0.11',
                                                             'description' => '',
                                                             'lsp-state' => 'Up',
                                                             'lsp-type' => 'Static Configured',
                                                             'active-path' => '(primary)',
                                                             'egress-label-operation' => 'Penultimate hop popping',
                                                             'paths' => [
								 {
                                                                            'path-state' => 'Up',
                                                                            'name' => '',
                                                                            'explicit-route' => {
                                                                                                  'explicit-route-type' => '',
                                                                                                  'addresses' => [
                                                                                                                   '172.16.0.38',
                                                                                                                   '172.16.0.46'
                                                                                                                 ]
									    },
                                                                            'setup-priority' => '4',
                                                                            'smart-optimize-timer' => '600',
                                                                            'path-active' => '',
                                                                            'received-rro' => 'Received RRO (ProtectionFlag 1=Available 2=InUse 4=B/W 8=Node 10=SoftPreempt 20=Node-ID):
      172.16.0.38 172.16.0.46',
                                                                            'title' => 'Primary',
                                                                            'hold-priority' => '4'
								 }
                                                                        ],
                                                             'route-count' => '0',
                                                             'revert-timer' => '600',
                                                             'source-address' => '172.16.0.14',
                                                             'load-balance' => 'random',
                                                             'attributes' => {
                                                                               'encoding-type' => 'Packet',
                                                                               'switching-type' => '',
                                                                               'gpid' => ''
							     }
					       },
					       {
                                                             'name' => 'L3VPN-R4-to-R2',
                                                             'destination-address' => '172.16.0.12',
                                                             'description' => '',
                                                             'lsp-state' => 'Up',
                                                             'lsp-type' => 'Static Configured',
                                                             'active-path' => '(primary)',
                                                             'egress-label-operation' => 'Penultimate hop popping',
                                                             'paths' => [
								 {
                                                                            'path-state' => 'Up',
                                                                            'name' => '',
                                                                            'explicit-route' => {
                                                                                                  'explicit-route-type' => '',
                                                                                                  'addresses' => [
                                                                                                                   '172.16.0.38',
                                                                                                                   '172.16.0.36'
                                                                                                                 ]
									    },
                                                                            'setup-priority' => '4',
                                                                            'smart-optimize-timer' => '600',
                                                                            'path-active' => '',
                                                                            'received-rro' => 'Received RRO (ProtectionFlag 1=Available 2=InUse 4=B/W 8=Node 10=SoftPreempt 20=Node-ID):
      172.16.0.38 172.16.0.36',
                                                                            'title' => 'Primary',
                                                                            'hold-priority' => '4'
								 }
                                                                        ],
                                                             'route-count' => '0',
                                                             'revert-timer' => '600',
                                                             'source-address' => '172.16.0.14',
                                                             'load-balance' => 'random',
                                                             'attributes' => {
                                                                               'encoding-type' => 'Packet',
                                                                               'switching-type' => '',
                                                                               'gpid' => ''
							     }
					       },
					       {
                                                             'name' => 'L3VPN-R4-to-R3',
                                                             'destination-address' => '172.16.0.13',
                                                             'description' => '',
                                                             'lsp-state' => 'Up',
                                                             'lsp-type' => 'Static Configured',
                                                             'active-path' => '(primary)',
                                                             'egress-label-operation' => 'Penultimate hop popping',
                                                             'paths' => [
								 {
                                                                            'path-state' => 'Up',
                                                                            'name' => '',
                                                                            'explicit-route' => {
                                                                                                  'explicit-route-type' => '',
                                                                                                  'addresses' => [
                                                                                                                   '172.16.0.41'
                                                                                                                 ]
									    },
                                                                            'setup-priority' => '4',
                                                                            'smart-optimize-timer' => '600',
                                                                            'path-active' => '',
                                                                            'received-rro' => 'Received RRO (ProtectionFlag 1=Available 2=InUse 4=B/W 8=Node 10=SoftPreempt 20=Node-ID):
      172.16.0.41',
                                                                            'title' => 'Primary',
                                                                            'hold-priority' => '4'
								 }
                                                                        ],
                                                             'route-count' => '0',
                                                             'revert-timer' => '600',
                                                             'source-address' => '172.16.0.14',
                                                             'load-balance' => 'random',
                                                             'attributes' => {
                                                                               'encoding-type' => 'Packet',
                                                                               'switching-type' => '',
                                                                               'gpid' => ''
							     }
					       },
					       {
                                                             'name' => 'L3VPN-R4-to-R5',
                                                             'destination-address' => '172.16.0.15',
                                                             'description' => '',
                                                             'lsp-state' => 'Up',
                                                             'lsp-type' => 'Static Configured',
                                                             'active-path' => '(primary)',
                                                             'egress-label-operation' => 'Penultimate hop popping',
                                                             'paths' => [
								 {
                                                                            'path-state' => 'Up',
                                                                            'name' => '',
                                                                            'explicit-route' => {
                                                                                                  'explicit-route-type' => '',
                                                                                                  'addresses' => [
                                                                                                                   '172.16.0.38'
                                                                                                                 ]
									    },
                                                                            'setup-priority' => '4',
                                                                            'smart-optimize-timer' => '600',
                                                                            'path-active' => '',
                                                                            'received-rro' => 'Received RRO (ProtectionFlag 1=Available 2=InUse 4=B/W 8=Node 10=SoftPreempt 20=Node-ID):
      172.16.0.38',
                                                                            'title' => 'Primary',
                                                                            'hold-priority' => '4'
								 }
                                                                        ],
                                                             'route-count' => '0',
                                                             'revert-timer' => '600',
                                                             'source-address' => '172.16.0.14',
                                                             'load-balance' => 'random',
                                                             'attributes' => {
                                                                               'encoding-type' => 'Packet',
                                                                               'switching-type' => '',
                                                                               'gpid' => ''
							     }
					       }
                                                         ],
                                           'count' => '5'
			      },
			      {
                                           'session_type' => 'Egress',
                                           'sessions' => [
					       {
                                                             'label-in' => '3',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.14',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.11',
                                                             'proto-id' => '0',
                                                             'label-out' => '-',
                                                             'adspec' => 'received MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '-',
                                                             'tunnel-id' => '8692',
                                                             'name' => 'L3VPN-R1-to-R4',
                                                             'psb-lifetime' => '138',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.46',
                                                                                 '172.16.0.38'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.38'
                                                                                                           ]
								 },
								 {
                                                                                         'next-hop' => [
                                                                                                         'localclient'
                                                                                                       ]
								 },
								 {
                                                                                         'previous-hop' => [
                                                                                                             'localclient'
                                                                                                           ]
								 }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Mon Jun 20 06:01:28 2016',
                                                             'lsp-id' => '108'
					       },
					       {
                                                             'label-in' => '3',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.14',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.15',
                                                             'proto-id' => '0',
                                                             'label-out' => '-',
                                                             'adspec' => 'received MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '-',
                                                             'tunnel-id' => '19624',
                                                             'name' => 'L3VPN-R5-to-R4',
                                                             'psb-lifetime' => '149',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.38'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.38'
                                                                                                           ]
								 },
								 {
                                                                                         'next-hop' => [
                                                                                                         'localclient'
                                                                                                       ]
								 },
								 {
                                                                                         'previous-hop' => [
                                                                                                             'localclient'
                                                                                                           ]
								 }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Thu Jun 16 18:35:45 2016',
                                                             'lsp-id' => '2'
					       },
					       {
                                                             'label-in' => '3',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.14',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.12',
                                                             'proto-id' => '0',
                                                             'label-out' => '-',
                                                             'adspec' => 'received MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '-',
                                                             'tunnel-id' => '22649',
                                                             'name' => 'L3VPN-R2-to-R4',
                                                             'psb-lifetime' => '123',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.36',
                                                                                 '172.16.0.38'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.38'
                                                                                                           ]
								 },
								 {
                                                                                         'next-hop' => [
                                                                                                         'localclient'
                                                                                                       ]
								 },
								 {
                                                                                         'previous-hop' => [
                                                                                                             'localclient'
                                                                                                           ]
								 }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Thu Jun 16 18:06:58 2016',
                                                             'lsp-id' => '27'
					       },
					       {
                                                             'label-in' => '3',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.14',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.13',
                                                             'proto-id' => '0',
                                                             'label-out' => '-',
                                                             'adspec' => 'received MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '-',
                                                             'tunnel-id' => '53024',
                                                             'name' => 'L3VPN-R3-to-R4',
                                                             'psb-lifetime' => '141',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.41'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.30'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.41'
                                                                                                           ]
								 },
								 {
                                                                                         'next-hop' => [
                                                                                                         'localclient'
                                                                                                       ]
								 },
								 {
                                                                                         'previous-hop' => [
                                                                                                             'localclient'
                                                                                                           ]
								 }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Thu May 12 18:59:17 2016',
                                                             'lsp-id' => '9'
					       },
					       {
                                                             'label-in' => '3',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.14',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.10',
                                                             'proto-id' => '0',
                                                             'label-out' => '-',
                                                             'adspec' => 'received MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '-',
                                                             'tunnel-id' => '61790',
                                                             'name' => 'L3VPN-R0-to-R4',
                                                             'psb-lifetime' => '122',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.44'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/2/0.40'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.44'
                                                                                                           ]
								 },
								 {
                                                                                         'next-hop' => [
                                                                                                         'localclient'
                                                                                                       ]
								 },
								 {
                                                                                         'previous-hop' => [
                                                                                                             'localclient'
                                                                                                           ]
								 }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Wed Mar 23 16:35:37 2016',
                                                             'lsp-id' => '3'
					       }
                                                         ],
                                           'count' => '5'
			      },
			      {
                                           'session_type' => 'Transit',
                                           'sessions' => [
					       {
                                                             'label-in' => '312256',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.10',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.15',
                                                             'proto-id' => '0',
                                                             'label-out' => '3',
                                                             'adspec' => 'received MTU 1500 sent MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '3',
                                                             'tunnel-id' => '19620',
                                                             'name' => 'L3VPN-R5-to-R0',
                                                             'psb-lifetime' => '125',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.38',
                                                                                 '172.16.0.44'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.38'
                                                                                                           ]
								 },
								 {
                                                                                         'next-hop' => [
                                                                                                         '172.16.0.44'
                                                                                                       ],
                                                                                         'interface-name' => [
                                                                                                               'xe-2/2/0.40'
                                                                                                             ]
								 },
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/2/0.40'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.44'
                                                                                                           ]
								 }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Fri Jun 17 18:13:30 2016',
                                                             'lsp-id' => '3'
					       },
					       {
                                                             'label-in' => '312320',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.12',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.13',
                                                             'proto-id' => '0',
                                                             'label-out' => '300336',
                                                             'adspec' => 'received MTU 1500 sent MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '300336',
                                                             'tunnel-id' => '53015',
                                                             'name' => 'L2VPLS-PRIMARY-LSP-1313',
                                                             'psb-lifetime' => '158',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.41',
                                                                                 '172.16.0.38',
                                                                                 '172.16.0.36'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.30'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.41'
                                                                                                           ]
								 },
								 {
                                                                                         'next-hop' => [
                                                                                                         '172.16.0.38'
                                                                                                       ],
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ]
								 },
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.38'
                                                                                                           ]
								 }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Fri Jun 17 18:13:31 2016',
                                                             'lsp-id' => '31'
					       },
					       {
                                                             'label-in' => '312128',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.12',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.13',
                                                             'proto-id' => '0',
                                                             'label-out' => '300176',
                                                             'adspec' => 'received MTU 1500 sent MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '300176',
                                                             'tunnel-id' => '53016',
                                                             'name' => 'L2VPLS-PRIMARY-LSP-1314',
                                                             'psb-lifetime' => '117',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.41',
                                                                                 '172.16.0.38',
                                                                                 '172.16.0.36'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.30'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.41'
                                                                                                           ]
								 },
								 {
                                                                                         'next-hop' => [
                                                                                                         '172.16.0.38'
                                                                                                       ],
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ]
								 },
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.38'
                                                                                                           ]
								 }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Thu Jun 16 13:54:38 2016',
                                                             'lsp-id' => '17'
					       },
					       {
                                                             'label-in' => '312144',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.12',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.13',
                                                             'proto-id' => '0',
                                                             'label-out' => '300192',
                                                             'adspec' => 'received MTU 1500 sent MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '300192',
                                                             'tunnel-id' => '53017',
                                                             'name' => 'L2VPLS-PRIMARY-LSP-1315',
                                                             'psb-lifetime' => '115',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.41',
                                                                                 '172.16.0.38',
                                                                                 '172.16.0.36'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.30'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.41'
                                                                                                           ]
								 },
								 {
                                                                                         'next-hop' => [
                                                                                                         '172.16.0.38'
                                                                                                       ],
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ]
								 },
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.38'
                                                                                                           ]
								 }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Thu Jun 16 13:54:47 2016',
                                                             'lsp-id' => '17'
					       },
					       {
                                                             'label-in' => '312288',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.12',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.13',
                                                             'proto-id' => '0',
                                                             'label-out' => '300352',
                                                             'adspec' => 'received MTU 1500 sent MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '300352',
                                                             'tunnel-id' => '53018',
                                                             'name' => 'L2VPLS-SECONDARY-LSP-1313',
                                                             'psb-lifetime' => '123',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.41',
                                                                                 '172.16.0.38',
                                                                                 '172.16.0.36'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.30'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.41'
                                                                                                           ]
								 },
								 {
                                                                                         'next-hop' => [
                                                                                                         '172.16.0.38'
                                                                                                       ],
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ]
								 },
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.38'
                                                                                                           ]
								 }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Fri Jun 17 18:13:31 2016',
                                                             'lsp-id' => '35'
					       },
					       {
                                                             'label-in' => '312336',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.12',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.13',
                                                             'proto-id' => '0',
                                                             'label-out' => '300368',
                                                             'adspec' => 'received MTU 1500 sent MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '300368',
                                                             'tunnel-id' => '53023',
                                                             'name' => 'L3VPN-R3-to-R2',
                                                             'psb-lifetime' => '135',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.41',
                                                                                 '172.16.0.38',
                                                                                 '172.16.0.36'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.30'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.41'
                                                                                                           ]
								 },
								 {
                                                                                         'next-hop' => [
                                                                                                         '172.16.0.38'
                                                                                                       ],
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ]
								 },
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.38'
                                                                                                           ]
								 }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Fri Jun 17 18:13:31 2016',
                                                             'lsp-id' => '33'
					       },
					       {
                                                             'label-in' => '312208',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.13',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.15',
                                                             'proto-id' => '0',
                                                             'label-out' => '3',
                                                             'adspec' => 'received MTU 1500 sent MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '3',
                                                             'tunnel-id' => '19623',
                                                             'name' => 'L3VPN-R5-to-R3',
                                                             'psb-lifetime' => '129',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.38',
                                                                                 '172.16.0.41'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.38'
                                                                                                           ]
								 },
								 {
                                                                                         'next-hop' => [
                                                                                                         '172.16.0.41'
                                                                                                       ],
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.30'
                                                                                                             ]
								 },
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.30'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.41'
                                                                                                           ]
								 }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Thu Jun 16 17:27:12 2016',
                                                             'lsp-id' => '2'
					       },
					       {
                                                             'label-in' => '312176',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.13',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.12',
                                                             'proto-id' => '0',
                                                             'label-out' => '3',
                                                             'adspec' => 'received MTU 1500 sent MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '3',
                                                             'tunnel-id' => '22640',
                                                             'name' => 'L2VPLS-PRIMARY-LSP-1313',
                                                             'psb-lifetime' => '127',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.36',
                                                                                 '172.16.0.38',
                                                                                 '172.16.0.41'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.38'
                                                                                                           ]
								 },
								 {
                                                                                         'next-hop' => [
                                                                                                         '172.16.0.41'
                                                                                                       ],
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.30'
                                                                                                             ]
								 },
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.30'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.41'
                                                                                                           ]
								 }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Thu Jun 16 16:01:05 2016',
                                                             'lsp-id' => '28'
					       },
					       {
                                                             'label-in' => '312160',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.13',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.12',
                                                             'proto-id' => '0',
                                                             'label-out' => '3',
                                                             'adspec' => 'received MTU 1500 sent MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '3',
                                                             'tunnel-id' => '22641',
                                                             'name' => 'L2VPLS-PRIMARY-LSP-1314',
                                                             'psb-lifetime' => '146',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.36',
                                                                                 '172.16.0.38',
                                                                                 '172.16.0.41'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.38'
                                                                                                           ]
								 },
								 {
                                                                                         'next-hop' => [
                                                                                                         '172.16.0.41'
                                                                                                       ],
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.30'
                                                                                                             ]
								 },
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.30'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.41'
                                                                                                           ]
								 }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Thu Jun 16 13:54:51 2016',
                                                             'lsp-id' => '17'
					       },
					       {
                                                             'label-in' => '312112',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.13',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.12',
                                                             'proto-id' => '0',
                                                             'label-out' => '3',
                                                             'adspec' => 'received MTU 1500 sent MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '3',
                                                             'tunnel-id' => '22642',
                                                             'name' => 'L2VPLS-PRIMARY-LSP-1315',
                                                             'psb-lifetime' => '131',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.36',
                                                                                 '172.16.0.38',
                                                                                 '172.16.0.41'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.38'
                                                                                                           ]
								 },
								 {
                                                                                         'next-hop' => [
                                                                                                         '172.16.0.41'
                                                                                                       ],
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.30'
                                                                                                             ]
								 },
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.30'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.41'
                                                                                                           ]
								 }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Thu Jun 16 13:54:32 2016',
                                                             'lsp-id' => '17'
					       },
					       {
                                                             'label-in' => '312192',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.13',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.12',
                                                             'proto-id' => '0',
                                                             'label-out' => '3',
                                                             'adspec' => 'received MTU 1500 sent MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '3',
                                                             'tunnel-id' => '22643',
                                                             'name' => 'L2VPLS-SECONDARY-LSP-1313',
                                                             'psb-lifetime' => '140',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.36',
                                                                                 '172.16.0.38',
                                                                                 '172.16.0.41'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.38'
                                                                                                           ]
								 },
								 {
                                                                                         'next-hop' => [
                                                                                                         '172.16.0.41'
                                                                                                       ],
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.30'
                                                                                                             ]
								 },
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.30'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.41'
                                                                                                           ]
								 }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Thu Jun 16 16:32:43 2016',
                                                             'lsp-id' => '30'
					       },
					       {
                                                             'label-in' => '312240',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.13',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.12',
                                                             'proto-id' => '0',
                                                             'label-out' => '3',
                                                             'adspec' => 'received MTU 1500 sent MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '3',
                                                             'tunnel-id' => '22648',
                                                             'name' => 'L3VPN-R2-to-R3',
                                                             'psb-lifetime' => '151',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.36',
                                                                                 '172.16.0.38',
                                                                                 '172.16.0.41'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.38'
                                                                                                           ]
								 },
								 {
                                                                                         'next-hop' => [
                                                                                                         '172.16.0.41'
                                                                                                       ],
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.30'
                                                                                                             ]
								 },
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.30'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.41'
                                                                                                           ]
								 }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Thu Jun 16 23:20:07 2016',
                                                             'lsp-id' => '27'
					       },
					       {
                                                             'label-in' => '312224',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.15',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.13',
                                                             'proto-id' => '0',
                                                             'label-out' => '3',
                                                             'adspec' => 'received MTU 1500 sent MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '3',
                                                             'tunnel-id' => '53025',
                                                             'name' => 'L3VPN-R3-to-R5',
                                                             'psb-lifetime' => '131',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.41',
                                                                                 '172.16.0.38'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.30'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.41'
                                                                                                           ]
								 },
								 {
                                                                                         'next-hop' => [
                                                                                                         '172.16.0.38'
                                                                                                       ],
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ]
								 },
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.38'
                                                                                                           ]
								 }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Thu Jun 16 18:21:04 2016',
                                                             'lsp-id' => '14'
					       },
					       {
                                                             'label-in' => '312272',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.15',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.10',
                                                             'proto-id' => '0',
                                                             'label-out' => '3',
                                                             'adspec' => 'received MTU 1500 sent MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '3',
                                                             'tunnel-id' => '61791',
                                                             'name' => 'L3VPN-R0-to-R5',
                                                             'psb-lifetime' => '150',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.44',
                                                                                 '172.16.0.38'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/2/0.40'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.44'
                                                                                                           ]
								 },
								 {
                                                                                         'next-hop' => [
                                                                                                         '172.16.0.38'
                                                                                                       ],
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ]
								 },
								 {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.25'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.38'
                                                                                                           ]
								 }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Fri Jun 17 18:13:31 2016',
                                                             'lsp-id' => '22'
					       }
                                                         ],
                                           'count' => '14'
			      }
                                       ]
    },
					   'mx240-r2' => {
                          'pending' => 0,
                          'results' => [
			      {
                                           'session_type' => 'Ingress',
                                           'sessions' => [
					       {
                                                             'name' => 'L3VPN-R2-to-R0',
                                                             'destination-address' => '172.16.0.10',
                                                             'description' => '',
                                                             'lsp-state' => 'Up',
                                                             'lsp-type' => 'Static Configured',
                                                             'active-path' => '(primary)',
                                                             'egress-label-operation' => 'Penultimate hop popping',
                                                             'paths' => [
								 {
                                                                            'path-state' => 'Up',
                                                                            'name' => '',
                                                                            'explicit-route' => {
                                                                                                  'explicit-route-type' => '',
                                                                                                  'addresses' => [
                                                                                                                   '172.16.0.34',
                                                                                                                   '172.16.0.32'
                                                                                                                 ]
									    },
                                                                            'setup-priority' => '4',
                                                                            'smart-optimize-timer' => '600',
                                                                            'path-active' => '',
                                                                            'received-rro' => 'Received RRO (ProtectionFlag 1=Available 2=InUse 4=B/W 8=Node 10=SoftPreempt 20=Node-ID):
      172.16.0.34 172.16.0.32',
                                                                            'title' => 'Primary',
                                                                            'hold-priority' => '4'
								 }
                                                                        ],
                                                             'route-count' => '0',
                                                             'revert-timer' => '600',
                                                             'source-address' => '172.16.0.12',
                                                             'load-balance' => 'random',
                                                             'attributes' => {
                                                                               'encoding-type' => 'Packet',
                                                                               'switching-type' => '',
                                                                               'gpid' => ''
							     }
					       },
					       {
                                                             'name' => 'L3VPN-R2-to-R1',
                                                             'destination-address' => '172.16.0.11',
                                                             'description' => '',
                                                                 'path-state' => 'Up',
                                                                            'name' => '',
							     'explicit-route' => {
                                                                                                  'explicit-route-type' => '',
                                                                                                  'addresses' => [
                                                                                                                   '172.16.0.34'
                                                                                                                 ]
							     },
                                                                            'set   'smart-optimize-timer' => '600',
                                                                            'path-active' => '',
                                                                            'received-rro' => 'Received RRO (ProtectionFlag 1=Available 2=InUse 4=B/W 8=Node 10=SoftPreempt 20=Node-ID):
      172.16.0.34',
                   nce' => 'random',
									    'attributes' => {
                                                                               'encoding-type' => 'Packet',
                                                                               'switching-type' => '',
                                                                               'gpid' => ''
									}
					       },
					       {
                                                             'name' => 'L3VPN-R2-to-R3',
                                                             'destination-address' => '172.16.0.13',
                                                             'description' => '',
                                                             'lsp-state' => 'Up',
                                                             'lsp-type' => 'Static Configured',
                                                             'active-path' => '(primary)',
                                                             'egress-label-operation' => 'Penultimate hop popping',
                                                             'paths' => [
								 {
                                                                            'path-state' => 'Up',
                                                                            'name' => '',
                                                                            'explicit-route' => {
                                                                                                  'explicit-route-type' => '',
                                                                                                  'addresses' => [
                                                                                           '172.16.0.37',
                                                                                                                   '172.16.0.39',
                                                                                                                   '172.16.0.41'
                                                                                                    16.0.41',
                                                                            'title' => 'Primary',
                                                                          'gpid' => ''
                                                                             }
                                                           },
                                                           {
                                                             'name' => 'L2VPLS-PRIMARY-LSP-1313',
                                                             'destination-address' => '172.16.0.13',
                                                             'description' => '',
                                                             'lsp-state' => 'Up',
                                                             'lsp-type' => 'Static Configured',
                                                             'active-path' => 'L2VPLS-PRIMARY-PATH-1313 (primary)',
                                                             'egress-label-operation' => 'Penultimate hop popping',
                                                             'paths' => [
                                                                          {
                                                                            'path-state' => 'Up',
                                                                            'name' => 'L2VPLS-PRIMARY-PATH-1313',
                                                                            'explicit-route' => {
                                                                                                  'explicit-route-type' => '',
                                                                                                  'addresses' => [72.16.0.41'
                                                                                                                 ]
									    },
                                                                            'setup-priority' => '4',
								 }
                                                                        ],
							     {
                                                             'name' => 'L2VPLS-SECONDARY-LSP-1313',
                                                             'destination-address' => '172.16.0.13',
                                                             'description' => '',
                                                             'lsp-state' => 'Up',
                                                             'lsp-type' => 'Static Configured',
                                                             'active-path' => 'L2VPLS-SECONDARY-PATH-1313 (primary)',
                                                             'egress-label-operation' => 'Penultimate hop popping',
                                                             'paths' => [
                                                   'name' => 'L2VPLS-SECONDARY-PATH-1313',
								 'explicit-route' => {
                                                                                                  'explicit-route-type' => '',
                                                                                                  'addresses' => [
                                                                                                                   '172.16.0.37',
                                                                                                                   '172.16.0.39',
                                                                                                                   '172.16.0.41'
                                                                                                                 ]
								 },
                                                                            'setup-priority' => '4',
                                                                            'smart-optimize-timer' => '600',
                                                                            'path-active' => '',
                                                                            'received-rro' => 'Received RRO (ProtectionFlag 1=Available 2=InUse 4=B/W 8=Node 10=SoftPreempt 20=Node-ID):
      172.16.0.37 172.16.0.39 172.16.0.41',
                                                                            'title' => 'Primary',
                                                                            'hold-priority' => '4'
								 }
                                                                        ],
                                                             'route-count' => '0',
                                                             'revert-timer' => '600',
                                                             'source-address' => '172.16.0.12',
                                                             'load-balance' => 'random',
                                                             'attributes' => {
                                                                               'encoding-type' => 'Packet',
                                                                               'switching-type' => '',
                                                                               'gpid' => ''
							     }
					       },
					       {
                                                             'name' => 'L2VPLS-PRIMARY-LSP-1314',
                                                             'destination-address' => ''description' => '',
                                                             'lsp-state' => 'Up',
                                                             'lsp-type' => 'Static Configured',
                                                             'active-path' => 'L2VPLS                                                                                              'addresses' => [
                                                                                                                   '172.16.0.37',
                                                                                                                   '172.16.0.39',
                                                                                                                   '172.16.0.41'
                                                                                                                 ]
					       },
                                                                            'setup-priority' => '4',
                                                                            'smart-optimize-timer' => '600',
                                                                                                             'received-rro' => 'Received RRO (ProtectionFlag 1=Available 2=InUse 4=B/W 8=Node 10=SoftPreempt 20=Node-ID):
      172.16.0.37 172.16.0.39 172.16.0.41',
                                                                            'title' => 'Primary',
                                                                            'hold-priority' => '4'
					       }
                                                                        ],
                                                             'route-count' => '0',
                                                             'revert-timer' => '600',
                                                             'source-address' => '172.16.0.12',
                                                                     'encoding-type' => 'Packet',
                                                                               'switching-type' => '',
                                                                               'gpid' => ''
			      }
				       },
    {
                                                             'name' => 'L2VPLS-SECONDARY-LSP-1314',
                                                             'destination-address' => '172.16.0.13',
                                                             'description' => '',
                                                             'lsp-state' => 'Up',
                                                             'lsp-type' => 'Static Configured',
                                                             'active-path' => 'L2VPLS-SECONDARY-PATH-1314 (primary)',
                                                             'egress-label-operation' => 'Penultimate hop popping',
                                                             'paths' => [
								 {
                                                                            'path-state' => 'Up',
                                                                            'name' => 'L2VPLS-SECONDARY-PATH-1314',
                                                                            'explicit-route' => {
                                                                                                                                                        'title' => 'Primary',
                                                                            'hold-priority' => '4'
									    }
                                                                        ],
                                                             'route-count' => '0',
                                                             'revert-timer' => '600',
                                                             'source-address' => '172.16.0.12',
                                                             'load-balance' => 'random',
								 'attributes' => {
                                                                               'encoding-type' => 'Packet',
                                                                               'switching-type' => '',
                                                                               'gpid' => ''
								 }
								 },
							     {
                                                             'name' => 'L2VPLS-PRIMARY-LSP-1315',
                                                             'destination-address' => '172.16.0.13',
                                                             'description' => '',
                                                             'lsp-state' => 'Up',
                                                             'lsp-type' => 'Static Configured',
                                                             'active-path' => 'L2VPLS-PRIMARY-PATH-1315 (primary)',
                                                             'egress-label-operation' => 'Penultimate hop popping',
							     {
                                                                            'path-state' => 'Up',
                                                                            'name' => 'L2VPLS-PRIMARY-PATH-1315',
                                                                            'explicit-route' => {
                                                                                                  'explicit-route-type' => '',
                                                                                                  'addresses' => [
                                                                                                                                                                                                                     ],
                                                             'route-count' => '0',
                                                             'revert-timer' => '600',
                                                             'source-address' => '172.16.0.12',
                                                             'load-balance' => 'random',
												      'attributes' => {
                                                                               'encoding-type' => 'Packet',
                                                                               'switching-type' => '',
                                                                                                  'name' => 'L2VPLS-SECONDARY-LSP-1315',
                                                             'destination-address' => '172.16.0.13',
                                                             'description' => '',
                                                             'lsp-state' => 'Up',
                                                             'lsp-type' => 'Static Configured',
									       'explicit-route' => {
                                                                                                  'explicit-route-type' => '',
                                                                                                  'addresses' => [
                                      riority' => '4',
                                                                            'smart-optimize-timer' => '600',
                                                                            'path-active' => '',
                                                                            'received-rro' => 'Received RRO (ProtectionFlag 1=Available 2=InUse 4=B/W 8=Node 10=SoftPreempt 20=Node-ID):
      172.16.0.34 172.16.0.32 172.16.0.42',
                                                                            'title' => 'Primary',
                                                                            'hold-priority' => '4'
                                                                          }
                                                                        ],
                                                             'rout        'source-address' => '172.16.0.12',
                                             'lsp-state' => 'Up',
                                                             'lsp-type' => 'Static Configured',
                                                             'active-path' => '(primary)',
                                                             'egress-label-operation' => 'Penultimate hop popping',
                                                             'paths' => [
								 {
                                                                            'path-state' => 'Up',
                                                                            'name' => '',
                                                                            'explicit-route' => {
                                                              ' => [
                                                                                                                   '172.16.0.37',
                                                                                                                   '172.16.0.39'
                                                                                                      'title' => 'Primary',
                                                                            'hold-priority' => '4'
                                                                          }
                                                                        ],
                                                             'route-count' => '0',
                                                             'revert-timer' => '600',
                                                             'source-address' => '172.16.0.12',
                                                             'load-balance' => 'random',
                                                             'attributes' => {
                                                                               'encoding-type' => 'Packet',
                                                                               'switching-type' => '',
                                                                               'gpid' => ''
                                                                             }
                                                           },
                                                           {
                                                             'name' => 'L3VPN-R2-to-R5',
                                                             'destination-address' => '172.16.0.15',
                                                             'description' => '',
                                                             'lsp-state' => 'Up',
                                                             'lsp-type' => 'Static Configured',
                                                             'active-path' => '(primary)',
                                                             'egress-label-operation' => 'Penultimate hop popping',
                                                             'paths' => [
                                                                          {
                                                                            'path-state' => 'Up',
                                                                            'name' => '',
                                                                            'explicit-route' => {
                                                                                                  'explicit-route-type' => '',
                                                                                                  'addresses' => [
                                                                                                                   '172.16.0.37'
                                                                                                                 ]
                                                                                                },
                                                                            'setup-priority' => '4',
                                                                            'smart-optimize-timer' => '600',
                                                                            'path-active' => '',
                                                                            'received-rro' => 'Received RRO (ProtectionFlag 1=Available 2=InUse 4=B/W 8=Node 10=SoftPreempt 20=Node-ID):
      172.16.0.37',
                                                                            'title' => 'Primary',
                                                                            'hold-priority' => '4'
                                                                          }
                                                                        ],
                                                             'route-count' => '0',
                                                             'revert-timer' => '600',
                                                             'source-address' => '172.16.0.12',
                                                             'load-balance' => 'random',
                                                             'attributes' => {
                                                                               'encoding-type' => 'Packet',
                                                                               'switching-type' => '',
                                                                               'gpid' => ''
                                                                             }
                                                           }
                                                         ],
                                           'count' => '11'
                                         },
                                         {
                                           'session_type' => 'Egress',
                                           'sessions' => [
                                                           {
                                                             'label-in' => '3',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.12',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.11',
                                                             'proto-id' => '0',
                                                             'label-out' => '-',
                                                             'adspec' => 'received MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '-',
                                                             'tunnel-id' => '8690',
                                                             'name' => 'L3VPN-R1-to-R2',
                                                             'psb-lifetime' => '156',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.34'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
                                                                                       {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.15'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.34'
                                                                                                           ]
                                                                                       },
                                                                                       {
                                                                                         'next-hop' => [
                                                                                                         'localclient'
                                                                                                       ]
                                                                                       },
                                                                                       {
                                                                                         'previous-hop' => [
                                                                                                             'localclient'
                                                                                                           ]
                                                                                       }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Mon Jun 20 05:37:38 2016',
                                                             'lsp-id' => '90'
                                                           },
                                                           {
                                                             'label-in' => '3',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.12',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.15',
                                                             'proto-id' => '0',
                                                             'label-out' => '-',
                                                             'adspec' => 'received MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '-',
                                                             'tunnel-id' => '19622',
                                                             'name' => 'L3VPN-R5-to-R2',
                                                             'psb-lifetime' => '157',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.37'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
                                                                                       {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.20'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.37'
                                                                                                           ]
                                                                                       },
                                                                                       {
                                                                                         'next-hop' => [
                                                                                                         'localclient'
                                                                                                       ]
                                                                                       },
                                                                                       {
                                                                                         'previous-hop' => [
                                                                                                             'localclient'
                                                                                                           ]
                                                                                       }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Thu Jun 16 13:36:44 2016',
                                                             'lsp-id' => '1'
                                                           },
                                                           {
                                                             'label-in' => '3',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.12',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.14',
                                                             'proto-id' => '0',
                                                             'label-out' => '-',
                                                             'adspec' => 'received MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '-',
                                                             'tunnel-id' => '46217',
                                                             'name' => 'L3VPN-R4-to-R2',
                                                             'psb-lifetime' => '148',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.39',
                                                                                 '172.16.0.37'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
                                                                                       {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.20'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.37'
                                                                                                           ]
                                                                                       },
                                                                                       {
                                                                                         'next-hop' => [
                                                                                                         'localclient'
                                                                                                       ]
                                                                                       },
                                                                                       {
                                                                                         'previous-hop' => [
                                                                                                             'localclient'
                                                                                                           ]
                                                                                       }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Thu Jun 16 18:15:25 2016',
                                                             'lsp-id' => '63'
                                                           },
                                                           {
                                                             'label-in' => '3',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.12',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.13',
                                                             'proto-id' => '0',
                                                             'label-out' => '-',
                                                             'adspec' => 'received MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '-',
                                                             'tunnel-id' => '53015',
                                                             'name' => 'L2VPLS-PRIMARY-LSP-1313',
                                                             'psb-lifetime' => '118',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.41',
                                                                                 '172.16.0.39',
                                                                                 '172.16.0.37'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
                                                                                       {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.20'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.37'
                                                                                                           ]
                                                                                       },
                                                                                       {
                                                                                         'next-hop' => [
                                                                                                         'localclient'
                                                                                                       ]
                                                                                       },
                                                                                       {
                                                                                         'previous-hop' => [
                                                                                                             'localclient'
                                                                                                           ]
                                                                                       }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Fri Jun 17 17:56:06 2016',
                                                             'lsp-id' => '31'
                                                           },
                                                           {
                                                             'label-in' => '3',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.12',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.13',
                                                             'proto-id' => '0',
                                                             'label-out' => '-',
                                                             'adspec' => 'received MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '-',
                                                             'tunnel-id' => '53016',
                                                             'name' => 'L2VPLS-PRIMARY-LSP-1314',
                                                             'psb-lifetime' => '136',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.41',
                                                                                 '172.16.0.39',
                                                                                 '172.16.0.37'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
                                                                                       {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.20'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.37'
                                                                                                           ]
                                                                                       },
                                                                                       {
                                                                                         'next-hop' => [
                                                                                                         'localclient'
                                                                                                       ]
                                                                                       },
                                                                                       {
                                                                                         'previous-hop' => [
                                                                                                             'localclient'
                                                                                                           ]
                                                                                       }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Thu Jun 16 13:37:14 2016',
                                                             'lsp-id' => '17'
                                                           },
                                                           {
                                                             'label-in' => '3',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.12',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.13',
                                                             'proto-id' => '0',
                                                             'label-out' => '-',
                                                             'adspec' => 'received MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '-',
                                                             'tunnel-id' => '53017',
                                                             'name' => 'L2VPLS-PRIMARY-LSP-1315',
                                                             'psb-lifetime' => '142',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.41',
                                                                                 '172.16.0.39',
                                                                                 '172.16.0.37'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
                                                                                       {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.20'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.37'
                                                                                                           ]
                                                                                       },
                                                                                       {
                                                                                         'next-hop' => [
                                                                                                         'localclient'
                                                                                                       ]
                                                                                       },
                                                                                       {
                                                                                         'previous-hop' => [
                                                                                                             'localclient'
                                                                                                           ]
                                                                                       }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Thu Jun 16 13:37:23 2016',
                                                             'lsp-id' => '17'
                                                           },
                                                           {
                                                             'label-in' => '3',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.12',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.13',
                                                             'proto-id' => '0',
                                                             'label-out' => '-',
                                                             'adspec' => 'received MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '-',
                                                             'tunnel-id' => '53018',
                                                             'name' => 'L2VPLS-SECONDARY-LSP-1313',
                                                             'psb-lifetime' => '119',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.41',
                                                                                 '172.16.0.39',
                                                                                 '172.16.0.37'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
                                                                                       {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.20'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.37'
                                                                                                           ]
                                                                                       },
                                                                                       {
                                                                                         'next-hop' => [
                                                                                                         'localclient'
                                                                                                       ]
                                                                                       },
                                                                                       {
                                                                                         'previous-hop' => [
                                                                                                             'localclient'
                                                                                                           ]
                                                                                       }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Fri Jun 17 17:56:06 2016',
                                                             'lsp-id' => '35'
                                                           },
                                                           {
                                                             'label-in' => '3',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.12',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.13',
                                                             'proto-id' => '0',
                                                             'label-out' => '-',
                                                             'adspec' => 'received MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '-',
                                                             'tunnel-id' => '53019',
                                                             'name' => 'L2VPLS-SECONDARY-LSP-1314',
                                                             'psb-lifetime' => '151',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.42',
                                                                                 '172.16.0.32',
                                                                                 '172.16.0.34'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
                                                                                       {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.15'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.34'
                                                                                                           ]
                                                                                       },
                                                                                       {
                                                                                         'next-hop' => [
                                                                                                         'localclient'
                                                                                                       ]
                                                                                       },
                                                                                       {
                                                                                         'previous-hop' => [
                                                                                                             'localclient'
                                                                                                           ]
                                                                                       }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Mon Jun 20 05:38:25 2016',
                                                             'lsp-id' => '51'
                                                           },
                                                           {
                                                             'label-in' => '3',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.12',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.13',
                                                             'proto-id' => '0',
                                                             'label-out' => '-',
                                                             'adspec' => 'received MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '-',
                                                             'tunnel-id' => '53020',
                                                             'name' => 'L2VPLS-SECONDARY-LSP-1315',
                                                             'psb-lifetime' => '117',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.42',
                                                                                 '172.16.0.32',
                                                                                 '172.16.0.34'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
                                                                                       {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.15'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.34'
                                                                                                           ]
                                                                                       },
                                                                                       {
                                                                                         'next-hop' => [
                                                                                                         'localclient'
                                                                                                       ]
                                                                                       },
                                                                                       {
                                                                                         'previous-hop' => [
                                                                                                             'localclient'
                                                                                                           ]
                                                                                       }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Mon Jun 20 05:38:34 2016',
                                                             'lsp-id' => '51'
                                                           },
                                                           {
                                                             'label-in' => '3',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.12',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.13',
                                                             'proto-id' => '0',
                                                             'label-out' => '-',
                                                             'adspec' => 'received MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '-',
                                                             'tunnel-id' => '53023',
                                                             'name' => 'L3VPN-R3-to-R2',
                                                             'psb-lifetime' => '121',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.41',
                                                                                 '172.16.0.39',
                                                                                 '172.16.0.37'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
                                                                                       {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/0/0.20'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.37'
                                                                                                           ]
                                                                                       },
                                                                                       {
                                                                                         'next-hop' => [
                                                                                                         'localclient'
                                                                                                       ]
                                                                                       },
                                                                                       {
                                                                                         'previous-hop' => [
                                                                                                             'localclient'
                                                                                                           ]
                                                                                       }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Fri Jun 17 17:56:06 2016',
                                                             'lsp-id' => '33'
                                                           },
                                                           {
                                                             'label-in' => '3',
                                                             'lsp-path-type' => 'Primary',
                                                             'destination-address' => '172.16.0.12',
                                                             'suggested-lable-in' => '-',
                                                             'rsb-count' => '1',
                                                             'recovery-label-in' => '-',
                                                             'source-address' => '172.16.0.10',
                                                             'proto-id' => '0',
                                                             'label-out' => '-',
                                                             'adspec' => 'received MTU 1500',
                                                             'suggested-label-out' => '-',
                                                             'recovery-label-out' => '-',
                                                             'tunnel-id' => '61788',
                                                             'name' => 'L3VPN-R0-to-R2',
                                                             'psb-lifetime' => '159',
                                                             'lsp-state' => 'Up',
                                                             'record-route' => [
                                                                                 '172.16.0.32',
                                                                                 '172.16.0.34'
                                                                               ],
                                                             'description' => '',
                                                             'route-count' => '0',
                                                             'packet-information' => [
                                                                                       {
                                                                                         'interface-name' => [
                                                                                                               'xe-2/1/0.15'
                                                                                                             ],
                                                                                         'previous-hop' => [
                                                                                                             '172.16.0.34'
                                                                                                           ]
                                                                                       },
                                                                                       {
                                                                                         'next-hop' => [
                                                                                                         'localclient'
                                                                                                       ]
                                                                                       },
                                                                                       {
                                                                                         'previous-hop' => [
                                                                                                             'localclient'
                                                                                                           ]
                                                                                       }
                                                                                     ],
                                                             'resv-style' => 'SE',
                                                             'psb-creation-time' => 'Mon Jun 20 05:43:40 2016',
                                                             'lsp-id' => '151'
                                                           }
                                                         ],
                                           'count' => '11'
                                         },
                                         {
                                           'session_type' => 'Transit',
                                           'sessions' => undef,
                                           'count' => '0'
                                         }
                                       ]
                        },
          }
    1;
