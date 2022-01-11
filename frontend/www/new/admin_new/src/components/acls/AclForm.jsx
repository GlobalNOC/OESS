import React, { useState } from "react";

import { EntityAutoComplte } from "../entities/EntityAutoComplete";
import { WorkgroupAutoComplte } from "../workgroups/WorkgroupAutoComplete";


export const AclForm = (props) => {
  let acl = (props.acl == null) ? {} : props.acl;
  console.log('AclForm', props, acl);

  const [interfaceAclId, setInterfaceAclId] = useState(acl.interface_acl_id || -1);
  const [interfaceId, setInterfaceId] = useState(acl.interface_id || -1);
  const [start, setStart] = useState(acl.start || 2);
  const [end, setEnd] = useState(acl.end || 4094);
  const [notes, setNotes] = useState(acl.notes || '');
  const [allowDeny, setAllowDeny] = useState(acl.allow_deny || 'allow');
  const [evalPosition, setEvalPosition] = useState(acl.eval_position || -1);
  const [entityId, setEntityId] = useState(acl.entity_id || -1);
  const [workgroupId, setWorkgroupId] = useState(acl.workgroup_id || -1);

  const validateForm = (e) => {
    return true;
  };

  const submitHandler = (e) => {
    e.preventDefault();

    const acl = {
      interfaceAclId,
      interfaceId,
      start,
      end,
      notes,
      allowDeny,
      evalPosition,
      entityId,
      workgroupId
    };
    let ok = validateForm(acl);
    if (!ok) return;
    console.log('submit:', acl, 'validated', ok);

    if (props.onSubmit) {
      props.onSubmit(acl);
    }
  };

  let cancelHandler = (e) => {
    let ok = confirm('Are you sure you wish to cancel? Any changes will be lost.');
    if (!ok) return;

    if (props.onCancel) {
      props.onCancel(e);
    }
  };

  return (
    <form onSubmit={submitHandler}>
      <div className="form-group" style={{flex: '1'}}>
        <label htmlFor="allow_deny">Allow / Deny</label>
        <select className="form-control" id="allow_deny" value={allowDeny} onChange={e => setAllowDeny(e.target.value)}>
          <option value="allow">Allow</option>
          <option value="deny">Deny</option>
        </select>
      </div>
      <div className="form-group">
        <label htmlFor="workgroup_id">Workgroup</label>
        <WorkgroupAutoComplte id="workgroup_id" name="workgroup_id" nullOption={{name: 'All', value: -1}} value={workgroupId} onChange={e => setWorkgroupId(e)} />
      </div>
      <div className="form-group">
        <label htmlFor="entity_id">Entity</label>
        <EntityAutoComplte id="entity_id" name="entity_id" nullOption={{name: 'None', value: -1}} value={entityId} onChange={e => setEntityId(e)} />
      </div>
      <div className="form-group">
        <label htmlFor="start">Start</label>
        <input type="number" className="form-control" id="start" placeholder="2" min="2" max="4094" value={start} onChange={e => setStart(e.target.value)} />
      </div>
      <div className="form-group">
        <label htmlFor="end">End</label>
        <input type="number" className="form-control" id="end" placeholder="4094" min="2" max="4094" value={end} onChange={e => setEnd(e.target.value)} />
      </div>
      <div className="form-group">
        <label htmlFor="notes">Notes</label>
        <textarea className="form-control" rows="3" id="notes" placeholder="..." value={notes} onChange={e => setNotes(e.target.value)} />
      </div>
      <br/>
      <input type="hidden" name="interface_acl_id" value={interfaceAclId} />

      <button type="submit" className="btn btn-primary" style={{margin: '0 2px'}}>Submit</button>
      <button type="button" className="btn btn-default" style={{margin: '0 2px'}} data-dismiss="modal" onClick={cancelHandler}>Cancel</button>
    </form>
  );
};
