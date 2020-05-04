---
layout: user-documentation
title: Network Entities
name: network-entities
---

## Introduction

Interfaces owned by a workgroup may be organized under a **network
entity**. Network entities are collections of network interfaces which
are owned by a single network, and when used together, may provide
redundant connectivity to a network. Entities are organized into a
hierarchy based on their relationship to the oess controlled network
and may be searched for by name when provisioning and using the entity
explorer.


## Entity Explorer

Navigate to the Entity Explorer using the Explore link in the
navbar. The left most navigation menu will show the top level entites
available to users; Click these to view their details and their child
entities. The primary content will show the contacts responsible for
managing the selected entity and any details about the entity that
have been provided. Use the search bar at the top of the page to
quickly navigate the hierarchy when the entity you're searching for is
already known.

## Create and Manage a Network Entity

Using the entity explorer navigate to the entity under which you wish
your new entity to be organized. Assuming you have the proper
permissions the `Add Entity` button will be displayed. Click this
button and complete the provided form. Afer the form has been
submitted the new entity will be available. _Note: It is not currently
possible for an entity to be organized under multiple entities without
help from a system administrator._

To modify an entity, if you have the proper permissions the `Edit
Entity` button will be displayed. Click this button and complete the
provided form. Afer the form has been submitted, changes to the entity
will be made.

## Associate Interfaces with an Entity

To associate an interface with an entity create or modify an existing
Interface ACL under the Workgroup page. Under the entity option, use
the entity name you wish to associate with the (interface, vlan)
pair. After saving the ACL, whenever the Entity is used in
provisioning, the associated interface will be auto-selected and the
associated VLANs will be available for selection.
