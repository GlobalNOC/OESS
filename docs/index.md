---
# You don't need to edit this file, it's empty on purpose.
# Edit theme's home layout instead if you wanna make some changes
# See: https://jekyllrb.com/docs/themes/#overriding-theme-defaults
layout: page
title: "OESS: Open Exchange Software Suite"
---

OESS is a set of software used to configure and control dynamic
(user-controlled) layer 2 virtual circuit (VLAN) networks on OpenFlow
or MPLS enabled switches. OESS provides circuit provisioning,
automatic circuit failover, per-interface permissions, and automatic
per-VLAN statistics. It includes a simple and user friendly web-based
user interface as well as a web services API.

## Features

- self service virtual circuit provisioning web portal
- integrated per port / vlan usage monitoring
- sub-second provisioning
- automatic failover and restoration to and from backup path
- work groups for shared managment of resources
- admin web interface for service management
- switch and topology discovery
- IDCP based inter-domain circuit provisioning
- PefSONAR data export
- NSI based inter-domain circuit provisioning


### MPLS Only Features

- QinQ Tagged Endpoints
- Quality of Service (QoS)

## Hardware Compatibility

### OpenFlow

Vendor | Model | Firmware | Multi-Point | Match on DL_DST
--- | --- | --- | --- | ---
Brocade | MLXe | ... | Yes | Yes
Cisco | ASR9000 | ... | No | Yes
Dell | S4810 | ... | No | Yes
IBM | G8264 | ... | No | Yes
Juniper | MX960 | ... | Yes | Yes
NEC | PF5820 | ... | No | Yes

### MPLS
L2VPN, L2VPLS, L2CCC, and L3VPN

Vendor | Model | Firmware | Multi-Point
--- | --- | --- | --- | ---
Juniper | MX960 | ... | Yes
Juniper | MX240 | ... | Yes

### VXLAN
EVPN

Vendor | Model | Firmware | Multi-Point
--- | --- | --- | --- | ---
Juniper | QFX10001 | ... | Yes
