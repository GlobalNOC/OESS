---
layout: user-documentation
title: Provisioning
name: provisioning
---

From the provisioning page, users are able to create network
connections by providing some basic details about their desired
connections and then selecting the networks they wish to connect with.

## Details

Each connection is identified by its description and is provisioned
according the schedule defined by the user.

![connection-details](/assets/img/frontend/provisioning/connection-details.png)

## Endpoints

Once the user has provided a description of the connection and
determined when it shall be provisioned, the user may select the
networks they wish to connect with. Click the New Endpoint button and
a modal which contains a hierarchical view of the available networks
will be displayed. Navigate the hierarchy to find your desired
endpoints and then click Add Endpoint.

<center>
    <img src="/assets/img/frontend/provisioning/new-endpoint-selected.png" width="50%"/>
</center>

### Peers

When creating a Layer 3 Connection an additional button will appear
after adding an endpoint. Click the New Peering button and a modal
which allows for the defnitiion of a BGP peering will be
defined. Enter the required details and then press Adding Peering.

<center>
    <img src="/assets/img/frontend/provisioning/new-peering.png" width="50%"/>
</center>

### Public Cloud Providers

OESS supports provisiong connections to AWS, Microsoft Azure, and
Google Cloud Platform. As provisioning for each cloud is slightly
different, use the videos in this section to setup your cloud enabled
endpoints. Additional details may be
found [here](/user-documentation/cloud-providers.html).

#### AWS Hosted Connection

<center>
<iframe width="560" height="315" src="https://www.youtube.com/embed/J-L-JtDdKfE" frameborder="0" allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>
</center>

#### Microsoft ExpressRoute

<center>
<iframe width="560" height="315" src="https://www.youtube.com/embed/LAcFWk_OiKY" frameborder="0" allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>
</center>

#### Google Partner Interconnect

## Saving the Connection

Once you've defined the connection's details and created at least two
endpoints you may save your connection. Click the save button in the
upper right corner of the page. After a few moments the connection
will be provisioned and you will be redirected to the connection's
details page.

![connection-details-3](/assets/img/frontend/provisioning/connection-details-3.png)
