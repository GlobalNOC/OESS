---
name: administration
title: Administration
layout: frontend
---

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

## Working with Hybrid Mode Switches
                             
Working with hybrid mode switches, may mean that you need to restrict
vlan ranges or change the vlan where discovery happens. Most
restrictions exist in the Admin Section -> Networking tab.  Click on a
node to set its restrictions.  For example if you have protected vlans
20-30 for non-openflow use, you will want to change the vlan range on
the nodes to 1-19,31-4095.  If a switch does not support untagged when
in hybrid mode, the discovery vlan can be set by editing the
/etc/oess/database.xml file and adding
`<discovery_vlan>XXX</discovery_vlan>` to the configuration. Once this
is done restart OESS for this change to take effect.
