---
layout: user-documentation
title: Cloud Connections
name: cloud-connections
---

OESS supports provisiong connections to AWS, Microsoft Azure, and
Google Cloud Platform. As provisioning for each cloud is slightly
different, use the videos in this section to setup your cloud enabled
endpoints.

## Amazon Web Services: Hosted Connections

<iframe width="560" height="315" src="https://www.youtube.com/embed/OhE-Rclp6Pg" frameborder="0" allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>

### Workflow Overview

1. Create a new Connection in OESS.
0. Create an Endpoint to AWS using your AWS Customer Id.
0. Create an Endpoint to your network.
0. Create a peer for each created Endpoint.
0. Save the Connection.
0. Under the Connections pane in the AWS Direct Connect console, select the newly created Hosted Connection and choose View details. Select the confirmation check box and choose Accept connection.
0. Create a Virtual Interface to use on the Hosted Connection, and configure the Hosted Connection's Endpoint in OESS to enabling peering between AWS and OESS.

---

## Google Cloud Platform: Partner Interconnects

<iframe width="560" height="315" src="https://www.youtube.com/embed/iMYEIIGQwAw" frameborder="0" allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>

### Workflow Overview

1. Create a Partner Interconnect via the GCP web portal. Note the generated Pairing Keys; These are used to create Endpoints within OESS.
0. Create a new Connection in OESS.
0. Create an Endpoint to GCP using each Pairing Key mentioned in Step 1.
0. Create an Endpoint to your network.
0. Create a peer for each created Endpoint.
0. Save the Connection.
0. Return to the GCP web portal and approve the Interconnect.

---

## Microsoft Azure: ExpressRoutes

<iframe width="560" height="315" src="https://www.youtube.com/embed/mH2CTFw3qdQ" frameborder="0" allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>

### Workflow Overview

1. Create an ExpressRoute via the Azure web portal. Note the generated Service Key; This is ued to create Endpoints within OESS.
0. Create a new Connection in OESS.
0. Create two Endpoints to Azure using the Service Key mentioned in Step 1.
0. Create an Endpoint to your network.
0. Create a peer for each created Endpoint.
0. Save the Connection.

**Note:** If manually configuring peer addresses, Azure expects a
`/30` for both the primary and secondary Endpoints. The first address
will be used by the peer and the second will be used by Azure. For
example, if `192.168.100.248/30` is used, `192.168.100.249/30` will be
used by the peer and `192.168.100.250/30` will be used by Azure.
