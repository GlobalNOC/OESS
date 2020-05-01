---
layout: user-documentation
title: Workgroups
name: workgroups
---

Each user belongs to one or more workgroups. A workgroup allows a
group of users to jointly manage Device Interfaces and network
Connections (sometimes called VLANs or Circuits).

## Interface ACLs

The ACL section displays a list of all of the interfaces owned by the
user's selected workgroup. This section allows you to view the current
ACL rules applied to a given interface. These rules can be added,
edited, removed, and reordered.

To view the ACL rules currently applied to a given interface, click on
the row for that interface in the Interfaces owned by this Workgroup
table. An Interface ACL table containing the rules will be
displayed. Each rule allows or denies a workgroup (or all workgroups)
the right to use a range of VLAN tags as circuit endpoints. The rules
are executed top to bottom, using first-match-wins semantics.

![interface-acls](/assets/img/frontend/workgroup/interface-acls.png)

### Adding an ACL Rule

To add an ACL rule, click the Add ACL button. A dialog box will be
displayed containing the following fields:

- Workgroup: The workgroup that the rule should be applied to; as a
  special case, a rule can also apply to All workgroups.
- Entity: The searchable name which identifies this set of network
  resources.
- Permission: Whether this rule should allow or deny the workgroup
  access to the specified range of VLAN tags
- VLAN Range: The range of VLAN tags that this rule should apply to
  (the second field can be left blank to apply the rule to a single
  tag)
- Notes: Any notes that the user may wish to be add about the rule
                
Once the fields have been filled out, click the Create ACL button.

### Editing an ACL Rule

To edit an ACL rule, click the edit icon button on the desired ACL. A
dialog box identical to the Add Interface ACL dialog will appear with
the current values filled out. Modify the fields and click the Save
changes button to apply the changes (or Close to discard the changes).

### Removing an ACL Rule

To remove an ACL rule, click the delete icon button on the desired
ACL. A confirmation dialog box will appear. Click OK to remove the
rule.

### Reordering ACL Rules

To reorder the existing ACL rules, click up or down icon buttons on
the desired ACL.
