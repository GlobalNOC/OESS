---
name: administration
title: Administration
layout: frontend
---

## Accessing the Admin Section

Upon Successful login to the OESS UI, if a user has Administrator
priviledges (they are a member of a workgroup that is marked as
administrator) A button on the top right of the page will be displayed
called "Admin".  The Admin button is available from all pages inside
of the OESS application, and is the gateway to make system level
modifications.

**img**

## Adding a new user

Creating a new user in OESS requires access to the Admin section.  A
user can login via multiple usernames (allowing for a shared account
for example) however the username must match the REMOTE_USER
environment variable passed through from apache.  If the username
contains a domain name for example then the user in OESS needs to also
contain that user name.

Usernames are `,` seperated.  The email address is where circuit
notifications are sent for all circuit events (create, remove, edit,
failover, down, restoration)

**img**

## Adding a new workgroup

To create a new workgroup in OESS a user must have access to the admin
section.  In the admin section there is a workgroup tab.  When looking
at the tab there is a list of existing workgroups, and a new workgroup
button.  Click the new workgroup button to create a new workgroup.

Creating a new workgroup requires a workgroup name, the external ID
allows for integration with other applications that may be assisting
with managing the OESS instance (for instance a billing application).

There are 3 workgroup types to choose from

Normal - a normal workgroup, that will only have permissions to access
the ports specified

Admin - Can see and edit any circuit on the network

Demo - Can not provision on the network at all

**img**

## Replacing Node / DPID Change

I've had to do this in testing (because the juniper backup REs have
different DPIDs).

The change is pretty simple depending on what you have done.  If you
know the DPID before the node connects you need to convert the DPID
into its integer form.  Once you do that update the node_instantiation
table in OESS so that the dpid of the end_epoch = -1 record for that
node_id to the new dpid (integer form).

If the node has already joined, the process is slightly more complex.
You can copy the dpid value from the new unapproved node, however you
will need to delete the interfaces, links, node records associated to
this node.

delete from link_instantiation where interface_a_id in (select
interface_id from interface where node_id = X)

delete from link_instantiation where interface_z_id in (select
interface_id from interface where node_id = X)

delete from interface_instantiation where interface_id in (select
interface_id from interface where node_id =?)

delete from interface where node_id = x

delete from node_instantiation where node_id = X

delete from node where node_id = x

finally for both cases this is the query needed to be run to update
the dpid

update node_instantiation set dpid = Y where node_id = X and end_epoch
= -1

## Adding a new Switch

When a new switch starts communicating with OESS, it waits in a
pending aproval state.  The pending approval state is to allow an
administrator to configure the profile of the device, and verify that
the device is suppose to be part of the network.  This prevents
unintended devices from becoming a part of the OESS network.

### NETCONF

Devices that speak NETCONF must be added manually using the Add MPLS
switch button.

**img**

Name takes the hostname of the device that will be displayed to the
user.

Short name is the name of the device as it appears in show isis
adjacencies.

The Latitude and Longitude fields are used to specify the location of
the device.

Vendor, Model, and Software Version defines which NETCONF module is
used by OESS to connect to the device.

After entering the above paramerters, click Add MPLS Device.

## Switch Diffs

Diffing is the process of comparing the OESS's expected state of the
network against the actual network. This happens on a regular
interval.

### NETCONF

Diffing for NETCONF enabled devices is similar to diffing for OpenFlow
enabled devices, except that in some cases a user must influence the
diffing behavior; This occurs when the size of a diff exceeds a
preconfigured threshold. In these cases an administrator must navigate
to the Config Changes section of the admin interface, and manually
approve the diff for the nodes marked Pending Approval.

**img**

## Insert a node in the middle

1. Approve the new Node in the OESS UI, and verify the proper
   parameters are set (Maximum Flows, Message Delay, Vlan range)
0. Break your existing link and insert into the new node
0. Verify in the Admin interface that 2 new links were discovered
0. In Admin section click the Network tab and click the circuit to be modified
0. Click the decom link button
0. OESS will prompt with a message "can not decom, but detected a node in the middle, would you like to migrate" click yes
0. Maintenance complete!
                            
## Automatic Backbone Move
                            
OESS can detect intraswitch link moves.  If a circuit is going from
switch A port 1 to switch B port 10, and a technician moves the link
to switch A port 2 OESS will detect and automatically move all traffic
going over the link to the new port.
                            
No approval or other administrative task is required for this to
happen automatically.

## Managing Workgroups
                            
To modify a workgroups permissions go to the admin section of the OESS
UI.  Click on the Workgroup tabs on the left.  There will be a table
in the center with the names of all of the workgroups.  Find the
workgroup you wish to modify, and then click it.
                            
On the new window that has opened, 2 seperate lists appear.  The left
list contains all of the users currently part of the workgroup.  The
right list contains the list of all the edge interfaces the workgroup
is currently allowed to provision on.

**img**

### Adding Users
                            
Underneath each of the tables is an add button. The add users button
will provide a list of all users currently configured in OESS.  Find
the user to add to the workgroup (if the user does not exist see the
add a user to OESS section). Clicking the user in the table adds the
user to the Users list.

**img**

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

**img**

### Removing Users

To remove a user from a workgroup click the remove button next to
their name in the user table.
                            
### Removing interfaces

To remove an interface from a workgroup click the remove button next
to the interface in the Owned Interfaces table.

**img**
                            
### Editing Workgroup
                            
At the top of the workgroup page is the Edit Workgroup Details
button. Clicking this button displays a dialog that allows you to edit
the Name, External ID, Node MAC Address Limit, Circuit Limit, and
Circuit Endpoint Limit of a workgroup.

**img**

## Link Weights / Metrics

**img**

By default, a circuit's shortest path is determined by the hop count
between the A and Z endpoints. However, this behaviour can be altered
by adding a weight to the intermediate links via the "metric"
field. If a weight is added, the path with the lowest aggregate weight
will be the shortest path. To modify the metric of a circuit, in Admin
section, click the Network tab and click the circuit to be
modified. Enter the desired value in the metric field and then click
the "Update Link" button.

**img**

If there are multiple links between two nodes clicking the line
representing the links will cause the Select Link panel to
appear. Choose a link and click the Select button to open the link
details panel for the link.


## Managing Interface ACL Rules
                            
To manage interface ACL rules from the admin section, click on the
Network Tab. Click on the node in the map that contains the interface
whose ACL rules you wish to modify.

**img**

A dialog box that contains the node's informatin will appear. At the
bottom of the dialog is a table of all the interfaces contained within
the node. Click the "View ACLs" button in the last column of the table
to open a dialog that contains the interface's ACL information.

**img**

From here you can follow the Using the Frontend-ACL documentation for
information on how to add, edit, remove, and reorder ACL rules.

## Working with Hybrid Mode Switches
                             
Working with hybrid mode switches, may mean that you need to restrict
vlan ranges or change the vlan where discovery happens. Most
restrictions exist in the Admin Section -> Networking tab.  Click on a
node to set its restrictions.  For example if you have protected vlans
20-30 for non-openflow use, you will want to change the vlan range on
the nodes to 1-19,31-4095.  If a switch does not support untagged when
in hybrid mode, the discovery vlan can be set by editing the
/etc/oess/database.xml file and adding
`<discovery_vlan>XXX</discovery_vlan>` to the configuration. Once
this is done restart OESS for this change to take effect.

## Circuit Loops

In OESS 1.1.8+ the Circuit loop feature allows you to loop all traffic
that is recieved on a node, back to the source.  This disrupts traffic
forwarding on that circuit.

Enabling this is fairly simple select the circuit you want to loop and
then click the Loop Circuit button.  This will take you to a page that
provides many warnings that you will distrupt traffic forwarding for
this circuit if you continue.  You must then select a node in the path
to loop all traffic at.

Once you select a node and confirm that you wish to do this, OESS will
install flows that send all traffic recieved on that node for that
circuit back at the source of the traffic.  This may be useful to test
a link in a path.

When you loop a circuit you will see a purple circuit indicating the
node that was looped, and the circuit status will be looped.

**img**

## Link / Node Maintenances

Link and Node maintenances performe a "Soft" down of a link or in the
case of Nodes all links attached to the node.  This proactivly causes
circuits to "fail over" to their backup path if one is configured.  It
will then prevent the circuits from restoring to primary and prevent
notifications for flapping links/nodes.  Putting a node or link into
maintenance mode does not disrupt forwarding for circuits that have no
backup path or can not be moved to an alternate path.  There is a
momentary disruption while circuits do change paths.

Upon completion of the maintenance, the engineer clicks the "Complete
Maintenance" button and OESS will signal link up events, and restore
circuits to the primary path.

To put a Link or Node into maintenance mode, goto the admin section of
OESS, and click the network tab.  Click on the link or node you want
to put into maintenance mode.  At the bottom of the popup will be a
button that says "put device/link into maintenance".

**img**

You can see what devices / links are in maintenance mode by going to
the Maintenance tab on the admin section.  This is where you can see
what maintenances are currently happening, and complete them if they
are ready to be completed.

**img**
