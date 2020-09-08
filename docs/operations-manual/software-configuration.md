---
layout: operations-manual
title: Software Configuration
name: software-configuration
---

## Third Party Access Control

OESS currently supports two access control backends.

- Built-in user and workgroup database
- Grouper access management system

### Configuration

To configure an Access Control system other than the Built-In
database, add the following configuration to
`/etc/oess/database.xml`. By default `third_party_mgmt` will be set to
`n`.

#### **Example**

```xml
<third_party_mgmt>y</third_party_management>
```

### Grouper Requirements

Grouper requires a little setup before it may be used with
OESS. Within the OESS stem create the three following Attribute Names
and Attribute Definitions.

**Attribute Name**
- workgroup-external-id
- workgroup-id
- workgroup-type

**Attribute Definition**
- workgroup-external-id: Single value string
- workgroup-id: Single value string
- workgroup-type: Single value string

**Grouper Layout**

The OESS Grouper layout is composed of a stem for each OESS Workgroup
and three Groups within each Workgroup stem. A `users` group within
the OESS stem is created to identify all users who may access OESS.

```
oess/
  admin/
    admin
    normal
    read-only
  alpha/
    admin
    normal
    read-only
  users
```

## Maximum Allowed Bandwidth for Cloud Provider Connections

Each connection to a Cloud Provider will have some bandwidth
restrictions. On the cloud provider side, these restrictions are based
on the speeds defined by the Cloud Provider's web API. On the OESS
side these will likely be set based on some set of business
requirements.

Consider the case where OESS is connected to a Cloud Provider via a
10Gb interconnect. While the Cloud Provider might allow a single 10Gb
connection to the interconnect, because no other connection could be
provisioned without oversubscription, OESS administators may wish to
prevent this.

### Configuration

To configure which speeds may be used on an Endpoint terminating on a
Cloud Provider's interconnect edit
`/etc/oess/interface-speed-config.xml`.

This configuration file contains a list of `interface-selector`s. Each
`interface-selector` is used to classify an Endpoint's Interface.

If the Interface's configured speed is within `min_bandwidth` and
`max_bandwidth`, and is of the same configured
`cloud_interconnect_type`, the Max Bandwidth allowed for an Endpoint
will be restricted to the `speeds` within the `interface-selector`.

#### **Example**

In this example, Azure ExpressRoute Interfaces have been configured to
allow different Endpoint bandwidths based on the underlying Physical
Interface's speed.

- Interfaces between `100Mb` and `1Gb` may only be used to provision `50Mb` Endpoints.
- Interfaces between `10Gb` adn `100Gb` may be used to provision `50Mb`, `500Mb`, and `1Gb` Endpoints.

```xml
<config>
  <interface-selector min_bandwidth="100" max_bandwidth="1000" cloud_interconnect_type="azure-express-route">
    <speed rate="50" />
  </interface-selector>
  <interface-selector min_bandwidth="10000" max_bandwidth="100000" cloud_interconnect_type="azure-express-route">
    <speed rate="50" />
    <speed rate="500" />
    <speed rate="1000" />
  </interface-selector>
</config>
```
