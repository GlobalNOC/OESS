---
layout: api
title: OESS API
name: api
---

## How to get help

https://globalnoc.iu.edu/sdn/oess.html - The OESS homepage

http://github.com/GlobalNOC/OESS - The latest code, development history, and release tags.

oess-users@globalnoc.iu.edu - The OESS mailing list if you need to
discuss something with a human or haven't been able to answer your
question using the above resources.

## Request format

Request formatAll services may be called with either GET or POST
requests.In the case of a GET request, parameters should be encoded as
URLarguments. In the case of a POST request, the parameters should be
passed in as application/x-www-form-urlencodeddata. Whichmethod on the
service to runis indicated by the special methodparameter.In some
methods, aparameter may be list-valued; this is represented by
multiple instances of the parameter in the URL or POST data.

Example URL for a GET request calling the `get_circuit_history` method:

```
https://<hostname>/oess/services/data.cgi?method=get_circuit_history&circuit_id=999
```

## Response format

Allmethods return JSON-formatted data; the top-level item is an
object.Mostmethods use the following convention(with the method
inmeasurement.cgi being a notable exception):

If an error occurs, the `error` field of the top-level object will be
set, and there may be explanatory text in the `error_text` field; If
the method’s operation was successful,any results will be put in the
resultsfield. In the example responses in this document, there are a
number of // C++-style commentsshown; these are not actually part of
the returned response, but serve to help explain the meaning of fields
in the returned object.

Example of aresponse for asuccessful operation:
```
{
  "results": [ // arrayof users’ information
    {
      "email_address": "johndoe@grnoc.iu.edu",
      "user_id":"5111"// numeric OESS userID
    },
    {
      "email_address": "janedoe@grnoc.iu.edu",
      "user_id":"5122"
    },
    ...
  ]
}
```

Example of an error response:
```
{
  "error_text": "get_existing_circuits: required input parameter workgroup_id is missing",
  "error":1,
  "results":null
}
```

## OESS concepts and data types

### Users

An OESS user is an entity that performs operationsin the OESS system. A user has a unique numeric user ID. Zero or more usernames, as used to authenticate to the web server (see “Authentication” below), are mapped to an OESS user; no username may map to more than one OESS user.

### Workgroups

Every OESS user should be a member of at least one workgroup; It's
possible for a user to be a member of multiple workgroups. Many
operations (e.g., creating a circuit) are performed in the context of
a single workgroup, so a particular workgroup must be specified for
the operation. Once auser has logged in totheOESSapplication,they are
asked to select a workgroup to work under;people using the API will
generally need to do something similar, either in a configuration file
or as a run-time argument.Each workgroup may own zero or more endpoint
interfaces on the network; no interface is owned by more than one
workgroup.

A workgroup has a name (a string; unique within an OESS instance) and
an ID (a unique integer).The workgroup IDis used in numerousmethodsand
allows OESS to determine which pieces of data the user is allowed to
seeand which operations the user may perform.

A workgroup also has a type, whichis one of normal(the vast majority
of workgroups in a typical OESS instance), admin(usually only one
workgroup), or demo(usuallyzero or one workgroup). A workgroup’s
typeis relatedto the operations that may be performed using that
workgroup; for more details, see “Allowedoperations” below.

### Nodes

Nodesare switching elements on the network. Each has a unique name (a string) and a unique integer ID; one or the other is used to specify a node, depending on the method in question.

A node may be configured to be used with OpenFlow, with MPLS (typically controlled using NETCONF), or both.

### Interfaces

Interfacesare network interfaces on nodes. Each has a name (possibly
duplicated on other nodes, but unique for its associated node; a
string) and an integer ID (unique in the OESS instance). Depending on
the method, an interface may be specified by its ID or by a (node
name, interface name) pair.A trunk interfaceis an interface that is an
endpoint of alink (see next); an endpoint interfaceis an interface
that is not a trunk interface, and marks the boundary of the
OESS-managed network (typically, an end system or a different network
is on the other side of the boundary).An interface may be owned by a
(single)workgroup; except for a few exceptional cases, trunk
interfaces do not need to be owned by a workgroup.An interface is
OpenFlow-based,MPLS-based, or both. If the same (on-node) interface is
accessible from both OpenFlow and MPLS, it mayshow up in OESS as two
interfaces, depending on the details of the node’s interface naming
scheme and OpenFlow/MPLS implementations.

An interface has an associated list of ACL entries, which the owning
workgroupof an interfaceuseto allow or denyworkgroups (including
itself!) the right to terminate circuits at a certain range of VLAN
tags on the interface.See the add_aclmethod of workgroup_manage.cgi
for more details.

### Links

Links are connections between nodes; they connect interfaces on
different nodes, and are auto-discovered by OESS (though require
confirmation by the administrators to be used). Each hasa unique name
(a string) and a unique integer ID.Links are OpenFlow-basedMPLS-based,
or both.

### Circuits

Circuits are what most users are ultimately concerned with. A circuit
consists of a number of endpoints, specified by (interface, VLAN tag)
pairs (thespecial VLAN tag value ‒1 refers to untagged frames), and
some paths, each a set of links over which circuit traffic will
travel: a primary path (optional for MPLS-based circuits) and an
(optional) secondary path for link-level resiliency.(Behind the
scenes, MPLS-based circuits also have a tertiary path, which is used
if the primary and secondary paths (if specified) are unusable.)A
circuit has a unique name (a string) and a unique integer ID. It can
also be assigned an external identifier, which is usedby OESS to store
circuit identifiers used by OSCARS and NSI agents.Acircuit is either
OpenFlow-based or MPLS-based–never both.

### Numbers

Numbers are sometimes represented in response fields as strings:
comments will generally refer to the value in question being
numeric.BooleansBoolean values are represented in method parametersand
response fieldsas 0 (false) or 1 (true).In responses, these may be the
strings “0” and “1”, instead of the numbers 0 and 1.

### Enumerations

Some method parameters and outputfields may only havea limited number
of values. This is represented in the parameter/field description
using set notation. For example,if a parameter may only have the value
“a”, “b”, or “lemon”, its listed value type will be {a,b,lemon}.

### MAC Addresses

MAC addresses may be specified in the form `01:02:03:04:0A:0b` or in
the form `01-02-03-04-0A-0b` where capitalization doesn’t matter, but
field separator (: or -) must be consistent in a given address.

## Authentication

OESS relies upon the hosting web server for authentication and
application-wide authorization (i.e., whether or not someone is
allowed to access OESS at all). The default Apachesetup protects OESS
using HTTP Basic authentication, backed by an .htpasswd file. However,
an instance may use a different authentication mechanism,as configured
onthe web server. You should contact the administrator of the system
to determine which type of authentication should be used for
programmatic access. For instance, currently theservices for theAL2S
instance of OESS may be accessed from an endpoint using
Shibbolethbrowser-centricauthentication(for human use of the OESS
frontendwith federated login)or from an endpoint using HTTP Basic
authentication(for easy programmatic use).

As mentioned in “Users” above, zero or more web-server-level usernames
are mapped onto a single OESS user; the possibility of the same
principal needing to use different kinds of authentication in
different contexts is a driver of this layer of indirection.
