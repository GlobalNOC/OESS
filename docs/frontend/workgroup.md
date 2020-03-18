---
name: workgroup
title: Workgroup
layout: frontend
---

## Interface ACLs

Within OESS an ACL is nothing more than a combination of the
following:

- Interface
- VLAN Range
- Associated Workgroup
- Entity

For now let's ignore the Entity and focus on the first three
components of an ACL. When combined, `Interface`, `VLAN Range`, and
`Workgroup` define a set of VLANs which may be used for provisioning
purposes.

Consider the following example ACLs:

State | Workgroup | Interface | Low | High
--- | --- | --- | ---
Allow | Alpha | rtsw-1.example.net - xe-7/0/1 | 100 | 199
Allow | Bravo | rtsw-1.example.net - xe-7/0/1 | 200 | 299

In this example workgroup `Alpha` may provision an Endpoint on
Interface `xe-7/0/1`, using VLANs `100 - 199` inclusive. Attempting to
provision an Endpoint on any other VLAN outside the designated range
by workgroup `Alpha` would **not** be permitted. Workgroup `Bravo` has
a similar restriction, except that its restricted to VLANs `200 -
299`.

Turning lastly to the Entity, it's best to think of an Entity as a
single Network Destination.

![simple entity](/assets/img/frontend/workgroup/simple_entity.png)
