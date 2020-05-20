---
layout: administration
title: User and Workgroup Management
name: user-workgroup-management
---

## Users

### New Users

Creating a new user in OESS requires access to the Admin section.  A
user can login via multiple usernames (allowing for a shared account
for example) however the username must match the REMOTE_USER
environment variable passed through from apache.  If the username
contains a domain name for example then the user in OESS needs to also
contain that user name.

Underneath each of the tables is an add button. The add users button
will provide a list of all users currently configured in OESS.  Find
the user to add to the workgroup (if the user does not exist see the
add a user to OESS section). Clicking the user in the table adds the
user to the Users list.

Usernames are `,` seperated.  The email address is where circuit
notifications are sent for all circuit events (create, remove, edit,
failover, down, restoration)

<center>
    <img src="{{ "/assets/img/frontend/administration/add-user.png" | relative_url }}" />
</center>
<br/>

### Removing Users

To remove a user from a workgroup click the remove button next to
their name in the user table.

<center>
    <img src="{{ "/assets/img/frontend/administration/remove-users.png" | relative_url }}" />
</center>
<br/>

## Workgroups

### New Workgroups

To create a new workgroup in OESS a user must have access to the admin
section.  In the admin section there is a workgroup tab.  When looking
at the tab there is a list of existing workgroups, and a new workgroup
button.  Click the new workgroup button to create a new workgroup.

Creating a new workgroup requires a workgroup name, the external ID
allows for integration with other applications that may be assisting
with managing the OESS instance (for instance a billing application).

There are 3 workgroup types to choose from

Normal - a normal workgroup, that will only have permissions to access
the ports specified

Admin - Can see and edit any circuit on the network

Demo - Can not provision on the network at all

<center>
    <img src="{{ "/assets/img/frontend/administration/add-workgroup.png" | relative_url }}" />
</center>
<br/>

### Managing Workgroups
                            
To modify a workgroups permissions go to the admin section of the OESS
UI.  Click on the Workgroup tabs on the left.  There will be a table
in the center with the names of all of the workgroups.  Find the
workgroup you wish to modify, and then click it.

At the top of the new window that has opened, is the Edit Workgroup
Details button. Clicking this button displays a dialog that allows you
to edit the Name, External ID, Node MAC Address Limit, Circuit Limit,
and Circuit Endpoint Limit of a workgroup.

<center>
    <img src="{{ "/assets/img/frontend/administration/edit-workgroup.png" | relative_url }}" />
</center>
<br/>

Below the Edit Workgroup Details button are two seperate lists. The
left list contains all of the users currently part of the
workgroup. The right list contains the list of all the edge interfaces
the workgroup is currently ownes or manages.

<center>
    <img src="{{ "/assets/img/frontend/administration/manage-workgroup.png" | relative_url }}" />
</center>
<br/>
