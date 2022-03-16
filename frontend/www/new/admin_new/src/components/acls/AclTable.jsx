import React from "react";
import { useEffect } from "react";
import { useState } from "react";

import { Link } from "react-router-dom";
import { withRouter } from "react-router-dom";

import { deleteAcl, decreaseAclPriority, increaseAclPriority } from '../../api/acls.js';

import { CustomTable } from "../generic_components/CustomTable.jsx";
import { PageContext } from "../../contexts/PageContext.jsx";

import "../../style.css";
import { useContext } from "react";

const aclTableComponent = (props) => {
    const { history, match } = props;
    const page = useContext(PageContext);

    const onDeleteAcl = (acl) => {
        deleteAcl(acl.interface_acl_id).then(result => {
            props.reloadAcls();
            page.setStatus({type: 'success', message: `ACL entry was successfully deleted.`});
        }).catch(error => {
            console.error(error);
            page.setStatus({type: 'error', message: error});
        });
    };

    const editAcl = (acl) => {
        console.log(acl);
    };

    const decreasePriority = (acl) => {
        decreaseAclPriority({
            interfaceAclId: acl.interface_acl_id,
            evalPosition: acl.eval_position,
            allowDeny: acl.allow_deny,
            start: acl.start,
            end: acl.end,
            interfaceId: acl.interface_id,
            notes: acl.notes,
            entityId: acl.entity_id || -1,
            workgroupId: acl.workgroup_id || -1
        }).then(result => {
            props.reloadAcls();
            page.setStatus({type: 'success', message: `ACL entry was successfully edited.`});
        }).catch(error => {
            console.error(error);
            page.setStatus({type: 'error', message: error});
        });
    }

    const increasePriority = (acl) => {
        increaseAclPriority({
            interfaceAclId: acl.interface_acl_id,
            evalPosition: acl.eval_position,
            allowDeny: acl.allow_deny,
            start: acl.start,
            end: acl.end,
            interfaceId: acl.interface_id,
            notes: acl.notes,
            entityId: acl.entity_id || -1,
            workgroupId: acl.workgroup_id || -1
        }).then(result => {
            props.reloadAcls();
            page.setStatus({type: 'success', message: `ACL entry was successfully edited.`});
        }).catch(error => {
            console.error(error);
            page.setStatus({type: 'error', message: error});
        });
    }

    const rowButtons = (data) => {
        return (
            <>
                <button type="button" className="btn btn-default btn-xs" onClick={e => increasePriority(data)}>
                    &nbsp;<span className="glyphicon glyphicon-chevron-up" aria-hidden="true"></span>&nbsp;
                </button>&nbsp;
                <button type="button" className="btn btn-default btn-xs" onClick={e => decreasePriority(data)}>
                    &nbsp;<span className="glyphicon glyphicon-chevron-down" aria-hidden="true"></span>&nbsp;
                </button>&nbsp;
                <div className="btn-group">
                    <Link to={`/nodes/${match.params['id']}/interfaces/${data.interface_id}/acls/${data.interface_acl_id}`} className="btn btn-default btn-xs">Edit ACL</Link>
                    <button type="button" className="btn btn-default btn-xs dropdown-toggle" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false">
                        <span>▾</span>{/* className="caret" doesn't work idk why */}
                        <span className="sr-only">Toggle Dropdown</span>
                    </button>
                    <ul className="dropdown-menu" style={{fontSize: '12px'}}>
                        <li><a href="#" onClick={e => onDeleteAcl(data)}>Delete ACL</a></li>
                    </ul>
                </div>
            </>
        );
    }

    let columns = [
        { name: 'Permission', key: 'allow_deny' },
        { name: 'Workgroup', render: d => (d.workgroup_name == null) ? 'Any' : d.workgroup_name },
        { name: 'Entity', key: 'entity_name' },
        { name: 'Start', key: 'start' },
        { name: 'End', key: 'end' },
        { name: '', render: rowButtons, style: {textAlign: 'right' } }
    ];

    return (
        <CustomTable columns={columns} rows={props.acls} size={5}>
            <CustomTable.MenuItem>
                <Link to={`/nodes/${match.params['id']}/interfaces/${match.params['interfaceId']}/acls/new`} className="btn btn-default">Create ACL</Link>
            </CustomTable.MenuItem>
        </CustomTable>
    );
};

export const AclTable = withRouter(aclTableComponent);
