import React, { setState, useState } from 'react';

const validateForm = (e) => {
  return true;
}

export const WorkgroupForm = (props) => {
  let tName = (props.workgroup && props.workgroup.name) ? props.workgroup.name : '';
  let tExternalId = (props.workgroup && props.workgroup.external_id) ? props.workgroup.external_id : '';
  let tType = (props.workgroup && props.workgroup.type) ? props.workgroup.type : 'normal';
  let tWorkgroupId = (props.workgroup && props.workgroup.workgroup_id) ? props.workgroup.workgroup_id : null;

  const [name, setName] = useState(tName);
  const [externalId, setExternalId] = useState(tExternalId);
  const [type, setType] = useState(tType);
  const [workgroupId, setWorkgroupId] = useState(tWorkgroupId);

  let onSubmit = (e) => {
    e.preventDefault();
    const workgroup = {
      name,
      externalId,
      type,
      workgroupId
    };
    let ok = validateForm(workgroup);
    if (!ok) return;
    console.log('submit', workgroup, 'validated:', ok);

    if (props.onSubmit) {
      props.onSubmit(e);
    }
  }

  let onCancel = (props.onCancel) ? props.onCancel : (e) => {
    console.log('cancel', workgroup);
  }

  return (
    <form onSubmit={onSubmit}>
      <div className="form-group">
        <label>Name</label>
        <input className="form-control" type="text" name="name" value={name} onChange={(e) => setName(e.target.value)} />
      </div>
      <div className="form-group">
        <label>External ID</label>
        <input className="form-control" type="text" name="external_id" value={externalId} onChange={(e) => setExternalId(e.target.value)} />
      </div>
      <label class="radio-inline">
        <input type="radio" id="normal" name="type" value="normal" checked={type === 'normal'} onChange={(e) => setType(e.target.value)} />
        Normal
      </label>
      <label class="radio-inline">
        <input type="radio" id="admin" name="type" value="admin" checked={type === 'admin'} onChange={(e) => setType(e.target.value)} />
        Admin
      </label>
      <br/> {/* inline radio buttons have bad spacing */}
      <br/>
      <input type="hidden" name="workgroup_id" value={workgroupId} />

      <button type="submit" className="btn btn-primary" style={{margin: '0 2px'}}>Submit</button>
      <button type="button" className="btn btn-default" style={{margin: '0 2px'}} data-dismiss="modal">Cancel</button>
    </form>
  );
}
