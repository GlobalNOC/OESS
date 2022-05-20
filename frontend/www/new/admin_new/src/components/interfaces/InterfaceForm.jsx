import React, { setState, useEffect, useState } from 'react';

import { AutoComplete } from '../generic_components/AutoComplete';

import { getAllWorkgroups } from '../../api/workgroup';


export const InterfaceForm = (props) => {
  let tName = (props.intf && props.intf.name) ? props.intf.name : '';
  let tDescription = (props.intf && props.intf.description) ? props.intf.description : '';
  let tWorkgroupId = (props.intf && props.intf.workgroup_id) ? parseInt(props.intf.workgroup_id) : -1;
  let tMplsVlanTagRange = (props.intf && props.intf.mpls_vlan_tag_range) ? props.intf.mpls_vlan_tag_range : '1-4095';
  let tCloudInterconnectType = (props.intf && props.intf.cloud_interconnect_type) ? props.intf.cloud_interconnect_type : '';
  let tCloudInterconnectId = (props.intf && props.intf.cloud_interconnect_id) ? props.intf.cloud_interconnect_id : '';
  let tInterfaceId = (props.intf && props.intf.interface_id) ? props.intf.interface_id : -1;

  const [name, setName] = useState(tName);
  const [description, setDescription] = useState(tDescription);
  const [mplsVlanTagRange, setMplsVlanTagRange] = useState(tMplsVlanTagRange);
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

  const validateVlanRange = (e) => {
    const elem = e.target;
    const val = elem.value;

    // Remove all leading and trailing whitespace and commas
    let cleanedUpVal = val.replaceAll(/^[, ]*|[, ]*$/g, '');
    let error = '';

    // 1. Split by comma
    // 2. Strip leading/trailing whitespace from ranges
    // 3. Filter out empty strings
    // 4. Validate range formated exactly like "{lowerNumber}-{higherNumber}"
    // 5. Validate lowerNumber < higherNumber && 1 <= numbers >= 4095
    let rangesArray = cleanedUpVal.split(',')
      .map(s => s.replaceAll(/^\s*|\s*$/g, ''))
      .filter(s => (s !== '') ? true : false)
      .map(s => {
        let ok = /^\d+-\d+$/.test(s);
        if (!ok) {
          error = 'Input must be a comma separated list of VLAN ranges. Ex 1-4095';
        }
        let parts = s.split('-');
        if (parts[0] < 1 || parts[0] > 4095 || parts[1] < 1 || parts[1] > 4095 || parseInt(parts[0]) > parseInt(parts[1])) {
          error = 'Input must be a comma separated list of VLAN ranges. Ex 1-4095';
        }
        return s;
      });
    
    elem.setCustomValidity(error);
    elem.reportValidity();
  };

  let onSubmit = (e) => {
    e.preventDefault();
    const intf = {
      name,
      description,
      mplsVlanTagRange,
      workgroupId,
      cloudInterconnectType,
      cloudInterconnectId,
      interfaceId
    };

    console.log('submit:', intf, 'validated:', true);
    if (props.onSubmit) {
      props.onSubmit(intf);
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
      <div className="form-group">
        <label className="control-label" htmlFor="mpls-vlan-tag-range">VLAN Ranges</label>
        <input className="form-control" type="text" id="mpls-vlan-tag-range" name="mpls-vlan-tag-range" value={mplsVlanTagRange} onChange={(e) => setMplsVlanTagRange(e.target.value)} onBlur={validateVlanRange} />
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
          <option value="oracle-fast-connect">Oracle FastConnect</option>
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
