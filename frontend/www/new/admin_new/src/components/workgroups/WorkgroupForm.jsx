import React, { setState, useState } from 'react';

const validateForm = (e) => {
  return true;
};

export const WorkgroupForm = (props) => {
  let tName = (props.workgroup && props.workgroup.name) ? props.workgroup.name : '';
  let tDescription = (props.workgroup && props.workgroup.description) ? props.workgroup.description : '';
  let tExternalId = (props.workgroup && props.workgroup.external_id) ? props.workgroup.external_id : '';
  let tType = (props.workgroup && props.workgroup.type) ? props.workgroup.type : 'normal';
  let tWorkgroupId = (props.workgroup && props.workgroup.workgroup_id) ? props.workgroup.workgroup_id : 0;

  const [name, setName] = useState(tName);
  const [description, setDescription] = useState(tDescription);
  const [externalId, setExternalId] = useState(tExternalId);
  const [type, setType] = useState(tType);
  const [workgroupId, setWorkgroupId] = useState(tWorkgroupId);

  let onSubmit = (e) => {
    e.preventDefault();
    const workgroup = {
      name,
      description,
      externalId,
      type,
      workgroupId
    };
    let ok = validateForm(workgroup);
    if (!ok) return;
    console.log('submit:', workgroup, 'validated:', ok);

    if (props.onSubmit) {
      props.onSubmit(workgroup);
    }
  };

  let onCancel = (e) => {
    let ok = confirm('Are you sure you wish to cancel? Any changes will be lost.');
    if (!ok) return;

    if (props.onCancel) {
      props.onCancel(e);
    }
  };

  return (
    <form onSubmit={onSubmit}>
      <div className="form-group">
        <label htmlFor="name">Name</label>
        <input className="form-control" type="text" id="name" name="name" value={name} maxlength="20" onChange={(e) => setName(e.target.value)} />
      </div>
      <div className="form-group">
        <label htmlFor="description">Description</label>
        <input className="form-control" type="text" id="description" name="description" value={description} onChange={(e) => setDescription(e.target.value)} />
      </div>
      <div className="form-group">
        <label htmlFor="external-id">External ID</label>
        <input className="form-control" type="text" id="external-id" name="external_id" value={externalId} onChange={(e) => setExternalId(e.target.value)} />
      </div>
      <label>Type</label><br/>
      <label className="radio-inline">
        <input type="radio" id="normal" name="type" value="normal" checked={type === 'normal'} onChange={(e) => setType(e.target.value)} />
        Normal
      </label>
      <label className="radio-inline">
        <input type="radio" id="admin" name="type" value="admin" checked={type === 'admin'} onChange={(e) => setType(e.target.value)} />
        Admin
      </label>
      <br/> {/* inline radio buttons have bad spacing */}
      <br/>
      <input type="hidden" name="workgroup_id" value={workgroupId} />

      <button type="submit" className="btn btn-primary" style={{margin: '0 2px'}}>Submit</button>
      <button type="button" className="btn btn-default" style={{margin: '0 2px'}} data-dismiss="modal" onClick={onCancel}>Cancel</button>
    </form>
  );
};
