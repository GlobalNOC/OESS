---
layout: administration
title: Configuration Changes
name: configuration-changes
---

## Switch Diffs

Diffing is the process of comparing the OESS's expected state of the
network against the actual network. This happens on a regular
interval.

Diffing for NETCONF enabled devices is similar to diffing for OpenFlow
enabled devices, except that in some cases a user must influence the
diffing behavior; This occurs when the size of a diff exceeds a
preconfigured threshold. In these cases an administrator must navigate
to the Config Changes section of the admin interface, and manually
approve the diff for the nodes marked Pending Approval.

<center>
    <img src="{{ "/assets/img/frontend/administration/approve-device-diffs.png" | relative_url }}"/>
</center>
<br/>
