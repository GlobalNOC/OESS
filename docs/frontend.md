---
layout: frontend
title: Frontend
permalink: /frontend/
---

This section describes how to use the OESS web interface. It assumes
that you have already installed and configured OESS, that nodes have
been configured in OESS and links discovered, and that workgroups and
users have been defined.

## Logging In

After the user has logged in, they will be forwarded to the user's
homepage. From this page the user may view all Connections to which
they have access, modify or delete existing Connections, change the
user's selected workgroup, and create new Connections.

![user-homepage](/assets/img/frontend/user-homepage.png)

## Network Connections

The connections that the user has access to are listed on the user
homepage. By selecting the down arrow on a listed connection the user
is shown a more detailed view of the connection. Selecting the trash
icon will delete the connection. The user will be prompted for
verification prior to the removal. Selecting the eye icon will forward
the user to the connection's details page. From this page the user is
given even more options which are
described [here](/frontend/provisioning).

## Workgroup Selection

Each user belongs to one or more workgroups. To change the selected
workgroup, click the workgroup selection dropdown in the rightmost
corner of the navigation bar and select the desired workgroup. If the
user account has been granted administration rights, all workgroups
will be listed and available for selection; These users will also see
a link to the admin section next to the workgroup selection dropdown.

## New Connections

To create a new connection, click the new connection dropdown in the
navigation bar and select either "Layer 2" or "Layer 3". From there,
you will be redirected to the the Connection Creation
page. See [here](/frontend/provisioning) for a detailed look at
creating a new connection.

## Troubleshooting

If you encounter an issue you may use the Feedback link in the site
footer to email the developers.
