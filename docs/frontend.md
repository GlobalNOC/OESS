---
layout: frontend
title: Frontend
permalink: /frontend/
---

This section describes how to use the OESS web interface to create
layer-2 circuits across the configured OpenFlow and/or MPLS
infrastructure. It assumes that you have already installed and
configured OESS, that nodes have been configured in OESS and links
discovered, and that workgroups and users have been defined.

## Logging In

Upon successful login, you will be presented with a page to choose
which workgroup you will work as; the page also lists current features
and known issues. In all parts of the UI, if you run into issues you
can select the Feedback button to email the developers. If your
account has been granted administration rights, you will also see an
Admin button on the upper right.

**img**

## Creating a Connection

To create a new connection, select the connection type from the `New
Connection` dropdown menu in the site navigation bar. From there, the
system will guide you through several steps, the culmination of which
is a working circuit.

## Explore

Use this section of the site to browse destination networks and their
relationships with eachother.

**img**

## Workgroups

Each user belongs to one or more workgroups. A workgroup allows a
group of users to jointly manage a set of resources - a workgroup may
own network interfaces and circuits (also called VLANs in a couple of
places in OESS). Once a workgroup is selected, you can then select
from one of six options: view the Active VLANS, view the current
Network Status, view the Available Resources (the interfaces (and VLAN
tags thereupon) the workgroup may use when creating circuits), get a
list of other Users in the workgroup, perform Actions such as creating
a new circuit, or manage the ACL rules for the interfaces the
workgroup owns.

**img**

The Active VLANS tab lets you see all the circuits your workgroup
owns, as well as other circuits using your workgroup's interfaces (the
latter show up in gray text). Search allows you to filter based on the
contents of the circuit descriptions. The table also can be filtered
to contain only circuits with endpoints on a particular node or that
have paths that go over a particular node. Clicking on a row in this
table will take you to the Circuit Details for that circuit, where you
can look at live traffic or edit the circuit.

## Circuit Details

The Circuit Details page is where you go to examine or change a
particular circuit. It shows the circuit's description, its endpoints,
and its metadata. When you first go to the page, you'll see the
circuit's path through the network and live network Utilization. The
History tab shows the history of the circuit and who has edited it in
the past. Scheduled Events shows any actions that have been scheduled
for the future, such as edits and removals. The Circuit Layout tab
shows a text representation of the circuit design, and for
OpenFlow-based circuits, the Raw Circuit Layout tab displays the
OpenFlow rules used to construct the circuit.

**img**
