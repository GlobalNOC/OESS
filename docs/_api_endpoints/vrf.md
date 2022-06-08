---
name: vrf
title: /vrf.cgi
layout: cgi
---
An interface for provisioning Layer 3 network connections.

### Endpoint JSON

The `provision` method of this CGI requires at least one `endpoint` to be
specified. An `endpoint` is a JSON string describing the network endpoint to be
provisioned.

```js
{
    // Required when editing an existing endpoint
    "vrf_endpoint_id":   123,
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
    // Required. Zero or One. Indicates MTU setting
    "jumbo":            1,
    // Include only for endpoints terminating at cloud provider. Value provided
    // is the:
    // - Service Key for an Azure ExpressRoute
    // - Pairing Key for a GCP Partner Interconnect
    // - Cloud Account ID for a AWS Hosted Connection
    // - OCID for an Oracle FastConnect
    "cloud_account_id": null,
    // Required. At least one peer must be provided per endpoint
    "peers":            [
        {
            // Required. ipv4 or ipv6
            "ip_version": "ipv4",
            // Required
            "local_ip":   "192.168.1.3/31",
            // Required
            "peer_asn":   65650,
            // Required
            "peer_ip":    "192.168.1.2/31",
            // Required. Null if BGP auth is disabled
            "md5_key":    null,
            // Zero or One. Indicates BFD state
            "bfd":        0
        }
    ]
}
```
