---
name: circuit
title: /circuit.cgi
layout: cgi
---
An interface for provisioning Layer 2 network connections.

### Endpoint JSON

The `provision` method of this CGI requires at least one `endpoint` to be
specified. An `endpoint` is a JSON string describing the network endpoint to be
provisioned.

```js
{
    // Required when editing an existing connection
    "circuit_ep_id":   123,
    // Required
    "name":             "connection",
    // Required
    "description":      "a demo connection",
    // Optional if both node and interface are provided
    "entity":           "customer a - network lab",
    // Optional if entity is provided. Only respected if both node and
    // interface provided
    "node":             "router.example.com",
    // Optional if entity is provided. Only respected if both node and
    // interface provided
    "interface":        "xe-7/0/1",
    // Required
    "tag":              300,
    // Optional. Only provided for QinQ tagged endpoints
    "inner_tag":        null,
    // Required. Specified in Mbps. Indicates how much bandwith shall be
    // reserved for this endpoint. Zero indicates no bandwidth restrictions
    "bandwidth":        0,
    // Include only for endpoints terminating at cloud provider. Value provided
    // is the:
    // - Service Key for an Azure ExpressRoute
    // - Pairing Key for a GCP Partner Interconnect
    // - Cloud Account ID for a AWS Hosted Connection
    // - OCID for an Oracle FastConnect
    "cloud_account_id": null
}
```
