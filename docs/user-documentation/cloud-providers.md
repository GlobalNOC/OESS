---
layout: user-documentation
title: Cloud Providers
name: cloud-providers
---

OESS supports provisiong connections to AWS, Microsoft Azure, and
Google Cloud Platform. As provisioning for each cloud is slightly
different, use the videos in this section to setup your cloud enabled
endpoints.

## Amazon Web Services

<center>
<iframe width="560" height="315" src="https://www.youtube.com/embed/J-L-JtDdKfE" frameborder="0" allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>
</center>

### Hosted Connection Workflow

1. User uses the OESS UI to add a Hosted Connection to their Connection by selecting the appropriate AWS Entity and providing their customer id and VLAN.
2. Once submitted OESS performs the following on the backend
    1. Using the interface's `interconnect_id` OESS looks up the cloud configuration's details.
    2. Request from AWS the new Hosted Connection
    3. OESS configures its network interfaces.
3. After the connection is configured, it appears in the Connections pane in the AWS Direct Connect console. Select the hosted connection and choose View details. Then select the confirmation check box and choose Accept connection.
4. Once the user creates a Virtual Interface to use on its Hosted Connection, it may configure the Hosted Connection's Endpoint to enabling peering between AWS and OESS.

## Google Cloud Platform Interconnects

## Microsoft Azure ExpressRoute

<center>
<iframe width="560" height="315" src="https://www.youtube.com/embed/LAcFWk_OiKY" frameborder="0" allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>
</center>

### ExpressRoute Workflow

1. User creates a CrossConnection via the Azure Portal
2. The User then uses the OESS UI to add an Endpoint to their connection by selecting the appropriate Azure Entity and providing the CrossConnection ServiceKey, ASN, and VLAN.
3. Once submitted the OESS performs the following on the backend.
    1. Using the interface's `interconnect_id` (Azure's physical port identifier) OESS looks up the cloud configuration's `subscription_id` and `resource_group`.
        1. This allows us to generate the required URLs for the Azure web API.
        2. This also allows us the lookup Azures sibling interface. **To use both primary and secondary connections the Azure entity must be added twice.**
    2. OESS selects two `/30` prefixes for both the primary and secondary interfaces.
        1. OESS will use `192.168.100.248/30` for the primary interface.
            1. The first address `192.168.100.248/30` is the network address
            2. The lower of the two addresses `192.168.100.249/30` will be used by OESS
            3. The upper of the two addresses `192.168.100.250/30` will be used by Azure
            4. The last address `192.168.100.251/30` is the broadcast address
        2. OESS will use `192.168.100.252/30` for the secondary interface
            1. The first address `192.168.100.252/30` is the network address
            2. The lower of the two addresses `192.168.100.253/30` will be used by OESS
            3. The upper of the two addresses `192.168.100.254/30` will be used by Azure
            4. The last address `192.168.100.255/30` is the broadcast address
    3. OESS then makes the required calls the Azure web API.
    4. OESS configures its network interfaces.
