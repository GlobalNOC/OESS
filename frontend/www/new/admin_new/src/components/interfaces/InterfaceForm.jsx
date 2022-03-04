import React, { setState, useEffect, useState } from 'react';

import { AutoComplete } from '../generic_components/AutoComplete';

import { getAllWorkgroups } from '../../api/workgroup';

const validateForm = (e) => {
  return true;
};

export const InterfaceForm = (props) => {
  let tName = (props.interface && props.interface.name) ? props.interface.name : '';
  let tDescription = (props.interface && props.interface.description) ? props.interface.description : '';
  let tWorkgroupId = (props.interface && props.interface.workgroup_id) ? parseInt(props.interface.workgroup_id) : -1;
  let tCloudInterconnectType = (props.interface && props.interface.cloud_interconnect_type) ? props.interface.cloud_interconnect_type : '';
  let tCloudInterconnectId = (props.interface && props.interface.cloud_interconnect_id) ? props.interface.cloud_interconnect_id : '';
  let tInterfaceId = (props.interface && props.interface.interface_id) ? props.interface.interface_id : -1;

  const [name, setName] = useState(tName);
  const [description, setDescription] = useState(tDescription);
  const [workgroupId, setWorkgroupId] = useState(tWorkgroupId);
  const [cloudInterconnectType, setCloudInterconnectType] = useState(tCloudInterconnectType);
  const [cloudInterconnectId, setCloudInterconnectId] = useState(tCloudInterconnectId);
  const [interfaceId, setInterfaceId] = useState(tInterfaceId);

  const [workgroups, setWorkgroups] = useState([]);

  useEffect(() => {
    try {
      getAllWorkgroups().then((workgroups) => {
        console.info(workgroups);
        setWorkgroups(workgroups);
      });
    } catch (error) {
      // TODO Show error message to user? If this fails workgroups can't be loaded.
      setWorkgroups([]);
      console.error(error);
    }
  }, []);

  let onSubmit = (e) => {
    e.preventDefault();
    const interface = {
      name,
      description,
      workgroupId,
      cloudInterconnectType,
      cloudInterconnectId,
      interfaceId
    };
    let ok = validateForm(interface);
    if (!ok) return;
    console.log('submit:', interface, 'validated:', ok);

    if (props.onSubmit) {
      props.onSubmit(interface);
    }
  };

  let onCancel = (e) => {
    let ok = confirm('Are you sure you wish to cancel? Any changes will be lost.');
    if (!ok) return;

    if (props.onCancel) {
      props.onCancel(e);
    }
  };

  let suggestions = workgroups.map((wg) => {
    return {name: wg.name, value: parseInt(wg.workgroup_id)};
  });

  let cloudInterconnectInputs = null;
  if (cloudInterconnectType !== "") {
    cloudInterconnectInputs = (
      <>
        <div className="form-group">
          <label htmlFor="cloud-interconnect-id">Cloud Interconnect ID</label>
          <input className="form-control" type="text" id="cloud-interconnect-id" name="cloud-interconnect-id" value={cloudInterconnectId} onChange={(e) => setCloudInterconnectId(e.target.value)} />
        </div>
      </>
    );
  }

  return (
    <form onSubmit={onSubmit}>
      <h4>General</h4>
      <hr/>

      <div className="form-group">
        <label htmlFor="name">Name</label>
        <input className="form-control" type="text" id="name" name="name" value={name} onChange={(e) => setName(e.target.value)} disabled />
      </div>
      <div className="form-group">
        <label htmlFor="description">Description</label>
        <input className="form-control" type="text" id="description" name="description" value={description} onChange={(e) => setDescription(e.target.value)} disabled />
      </div>
      <div className="form-group">
        <label htmlFor="workgroup">Connector</label>
        <AutoComplete id="workgroup" name="workgroup" placeholder="Search by workgroup" value={workgroupId} onChange={(e) => setWorkgroupId(e)} suggestions={suggestions} />
      </div>

      <br/>
      <h4>Cloud Provider</h4>
      <hr/>
      <div className="form-group">
        <label htmlFor="cloud-interconnect-type">Cloud Interconnect Type</label>
        <select className="form-control" id="model" value={cloudInterconnectType} onChange={e => setCloudInterconnectType(e.target.value)}>
          <option value="">Disabled</option>
          <option value="azure-express-route">Azure Express Route</option>
          <option value="aws-hosted-connection">AWS Hosted Connection</option>
          <option value="gcp-partner-interconnect">GCP Partner Interconnect</option>
        </select>
      </div>
      {cloudInterconnectInputs}

      <input type="hidden" name="interface_id" value={interfaceId} />

      <br/>
      <button type="submit" className="btn btn-primary" style={{margin: '0 2px'}}>Submit</button>
      <button type="button" className="btn btn-default" style={{margin: '0 2px'}} data-dismiss="modal" onClick={onCancel}>Cancel</button>
    </form>
  );
};
