---
layout: frontend
title: Glossary
---

## ACL

```yaml
device:    router1.example.net
interface: xe-7/0/1
low:       100
high:      200
workgroup: all
entity:    Example Network
```

An ACL defines a range of VLANs on a `device` `interface` which may be
provisioned to by a `workgroup`. The ACL is associated with an
`entity` which may be selected and searched for by `users` while
creating `connection` `endpoints`.

## Connection

```yaml
name: Virtual Layer2 Network
created_by:
  - name:  John Doe
    email: john.doe@example.net
endpoints:
  - entity:    Example Network
    device:    router1.example.net
    interface: xe-7/0/1
    vlan:      130
    jumbo:     true
    bandwidth: 50
  - entity:    AWS - us-east
    device:    router6.example.net
    interface: xe-7/0/1
    vlan:      300
    jumbo:     true
    bandwidth: 50
```

A connection is a Layer 2 or Layer 3 virtual network that is composed
of two or more `endpoints` and provisioned over the OESS controlled
network.

## Device

```yaml
hostname:   router1.example.net
shortname:  router1
ip_address: 10.0.0.100
interfaces:
  - name: xe-7/0/1
```

A device is a router or switch which is apart of the network topology
controlled by OESS.

## Endpoint

```yaml
entity:    Example Network
device:    router1.example.net
interface: xe-7/0/1
vlan:      130
jumbo:     true
bandwidth: 50
peerings:  []
```

An Endpoint defines the provider side of a `connection's` edge. Layer
3 `endpoints` contain an addtional list of `peerings`.

## Entity

```yaml
name: Example Network
contacts:
  - name:  John Doe
    email: john.doe@example.net
acls:
  - device:    router1.example.net
    interface: xe-7/0/1
    low:       100
    high:      200
    workgroup: all
  - device:    router2.example.net
    interface: xe-7/1/1
    low:       300
    high:      400
    workgroup: all
```

An entity describes a network destination and is composed of `ACLs`
and `users` or engineering contacts. Entities are used while creating
`connections` to help quickly identify and create network `endpoints`.

## Interface

```yaml
device: router1.example.net
name:   xe-7/0/1
role:   customer
```

An interface is a network interface on a `device`. The interface may
act as a trunk to other `devices` or as a physical connection to
a [customer edge](https://en.wikipedia.org/wiki/Customer_edge)
interface.

## Link

```yaml
name: router1-to-router2
interfaces:
  - device:   router1.example.net
    name:     ae0
    role:     trunk
    link:     true
    admin_up: true
  - device:   router2.example.net
    name:     ae0
    role:     trunk
    link:     true
    admin_up: true
```

A physical connection between two network `device` `interfaces`
discovered using the is-is adjacencies configured on each `device`.

## Peering

```yaml
ip_version: ipv4
local_ip:   192.168.1.2/31
local_asn:  64550
peer_ip:    192.168.1.3/31
peer_asn:   64560
md5_key:    null
```

The information required to establish a BGP session between a Layer 3
`connection's` `endpoint` and its peer.

## User

```yaml
name:  John Doe
email: john.doe@example.net
workgroups:
  - name: example-net
```

A user is a creator of `connections` or memeber of `workgroups`. An
OESS user may operate in a read-only mode.

## Workgroup

```yaml
name: example.net
users:
  - name: John Doe
    email: john.doe@example.net
interfaces:
  - device:    router1.example.net
    interface: xe-7/0/1
  - device:    router2.example.net
    interface: xe-7/1/1
```

A workgroup is a group of `users` that own a set of network
`interfaces`. The workgroup may grant other workgroups the right to
provision `endpoints` on these `interfaces` by creating `acls`.
