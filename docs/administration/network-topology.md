---
layout: administration
title: Network Topology
name: network-topology
---

## Switches

### New Switches

When a new switch starts communicating with OESS, it waits in a
pending aproval state.  The pending approval state is to allow an
administrator to configure the profile of the device, and verify that
the device is suppose to be part of the network.  This prevents
unintended devices from becoming a part of the OESS network.

#### NETCONF

Devices that speak NETCONF must be added manually using the Add MPLS
switch button.

<center>
    <img src="/assets/img/frontend/administration/add-netconf-device.png" />
</center>
<br/>

Name takes the hostname of the device that will be displayed to the
user.

Short name is the name of the device as it appears in show isis
adjacencies.

The Latitude and Longitude fields are used to specify the location of
the device.

Vendor, Model, and Software Version defines which NETCONF module is
used by OESS to connect to the device.

After entering the above paramerters, click Add MPLS Device.

### Insert a node in the middle

1. Approve the new Node in the OESS UI, and verify the proper
   parameters are set (Maximum Flows, Message Delay, Vlan range)
0. Break your existing link and insert into the new node
0. Verify in the Admin interface that 2 new links were discovered
0. In Admin section click the Network tab and click the circuit to be modified
0. Click the decom link button
0. OESS will prompt with a message "can not decom, but detected a node in the middle, would you like to migrate" click yes
0. Maintenance complete!

## Interfaces

### Adding Interfaces
                            
The add interface button opens up a map of the Network.  Clicking a
node on the map will show a list of all the interfaces on the device.
Clicking an interface in the list will add that interface to the
workgroup.
                            
When running a node in Dual Stack mode (OpenFlow and NETCONF), you
will find two of each interface. One interface was discovered using
OpenFlow, and the second using NETCONF. Be sure to include both
interfaces if you wish to enable provisioning of OpenFlow and NETCONF
circuits.

<center>
    <img src="/assets/img/frontend/administration/add-interfaces.png" />
</center>
<br/>

### Removing interfaces

To remove an interface from a workgroup click the remove button next
to the interface in the Owned Interfaces table.

<center>
    <img src="/assets/img/frontend/administration/remove-interfaces.png" />
</center>
<br/>

## Interface ACLs
                            
To manage interface ACL rules from the admin section, click on the
Network Tab. Click on the node in the map that contains the interface
whose ACL rules you wish to modify.

<center>
    <img src="/assets/img/frontend/administration/manage-acls.png" />
</center>

A dialog box that contains the node's informatin will appear. At the
bottom of the dialog is a table of all the interfaces contained within
the node. Click the "View ACLs" button in the last column of the table
to open a dialog that contains the interface's ACL information.

<center>
    <img src="/assets/img/frontend/administration/edit-acl.png" />
</center>
<br/>

From here you can follow the Using the Frontend-ACL documentation for
information on how to add, edit, remove, and reorder ACL rules.

## Links

### Weights / Metrics

<center>
    <img src="/assets/img/frontend/administration/edit-link.png" />
</center>
<br/>

By default, a circuit's shortest path is determined by the hop count
between the A and Z endpoints. However, this behaviour can be altered
by adding a weight to the intermediate links via the "metric"
field. If a weight is added, the path with the lowest aggregate weight
will be the shortest path. To modify the metric of a circuit, in Admin
section, click the Network tab and click the circuit to be
modified. Enter the desired value in the metric field and then click
the "Update Link" button.

<center>
    <img src="/assets/img/frontend/administration/select-link.png" />
</center>
<br/>

If there are multiple links between two nodes clicking the line
representing the links will cause the Select Link panel to
appear. Choose a link and click the Select button to open the link
details panel for the link.

### Automatic Backbone Move
                            
OESS can detect intraswitch link moves.  If a circuit is going from
switch A port 1 to switch B port 10, and a technician moves the link
to switch A port 2 OESS will detect and automatically move all traffic
going over the link to the new port.
                            
No approval or other administrative task is required for this to
happen automatically.
