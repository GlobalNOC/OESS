import React, { setState, useState } from 'react';

const validateForm = (e) => {
  return true;
};

export const NodeForm = (props) => {
  let node = (props.node === null) ? {} : props.node;

  const [name, setName] = useState(node.name || '');
  const [shortName, setShortName] = useState(node.short_name || '');
  const [longitude, setLongitude] = useState(node.longitude || 0.0);
  const [latitude, setLatitude] = useState(node.latitude || 0.0);
  const [vlanRange, setVlanRange] = useState(node.vlan_range || '1-4095');
  const [ipAddress, setIpAddress] = useState(node.ip_address || '');
  const [tcpPort, setTcpPort] = useState(node.tcp_port || 830);
  const [make, setMake] = useState(node.make || 'Juniper');
  const [model, setModel] = useState(node.model || 'MX');
  const [controller, setController] = useState(node.controller || 'netconf');
  const [swVersion, setSwVersion] = useState(node.sw_version || 'unknown');
  const [nodeId, setNodeId] = useState(node.node_id || 0);

  let onSubmit = (e) => {
    e.preventDefault();
    const node = {
      name,
      shortName,
      longitude,
      latitude,
      vlanRange,
      ipAddress,
      tcpPort,
      make,
      model,
      controller,
      nodeId
    };
    let ok = validateForm(node);
    if (!ok) return;
    console.log('submit:', node, 'validated:', ok);

    if (props.onSubmit) {
      props.onSubmit(node);
    }
  };

  let onCancel = (e) => {
    let ok = confirm('Are you sure you wish to cancel? Any changes will be lost.');
    if (!ok) return;

    if (props.onCancel) {
      props.onCancel(e);
    }
  };

  let nsoControllerInputs = null;
  if (controller === 'netconf') {
    nsoControllerInputs = (
      <div>
        <br/>
        <h4>NetConf</h4>
        <hr/>

        <div className="form-group">
          <label htmlFor="tcp-port">TCP Port</label>
          <input type="number" className="form-control" id="tcp-port" placeholder="830" value={tcpPort} onChange={e => setTcpPort(e.target.value)} />
        </div>
      </div>
    );
  }

  return (
    <form onSubmit={onSubmit}>
      <h4>Hardware</h4>
      <hr/>
      <div className="form-group">
        <label htmlFor="name">Name</label>
        <input type="text" className="form-control" id="name" placeholder="sw1.example.com" value={name} onChange={e => setName(e.target.value)} />
      </div>
      <div className="form-group">
        <label htmlFor="short-name">Short Name</label>
        <input type="text" className="form-control" id="short-name" placeholder="sw1" value={shortName} onChange={e => setShortName(e.target.value)} />
      </div>
      <div className="form-group">
        <label htmlFor="ip-address">IP Address</label>
        <input type="text" className="form-control" id="ip-address" placeholder="192.168.1.1" value={ipAddress} onChange={e => setIpAddress(e.target.value)} />
      </div>
      <div style={{display: 'inline-flex', width: '100%', gap: '12px'}}>
        <div className="form-group" style={{flex: '1'}}>
          <label htmlFor="make">Make</label>
          <select className="form-control" id="make" value={make} onChange={e => setMake(e.target.value)}>
          <option value="Cisco">Cisco</option>
          <option value="Juniper">Juniper</option>
          </select>
        </div>
        <div className="form-group" style={{flex: '1'}}>
          <label htmlFor="model">Model</label>
          <select className="form-control" id="model" value={model} onChange={e => setModel(e.target.value)}>
            <option value="MX">MX</option>
            <option value="QFX">QFX</option>
            <option value="NCS-5500">NCS-5500</option>
            <option value="8000">8000</option>
          </select>
        </div>
      </div>
      <div className="form-group">
        <label htmlFor="sw-version">Firmware</label>
        <input disabled type="text" className="form-control" id="sw-version" value={swVersion} onChange={e => setSwVersion(e.target.value)} />
      </div>
      <div style={{display: 'inline-flex', width: '100%', gap: '12px'}}>
        <div className="form-group" style={{flex: '1'}}>
          <label htmlFor="latitude">Latitude</label>
          <input type="text" className="form-control" id="latitude" placeholder="0.0" value={latitude} onChange={e => setLatitude(e.target.value)} />
        </div>
        <div className="form-group" style={{flex: '1'}}>
          <label htmlFor="longitude">Longitude</label>
          <input type="text" className="form-control" id="longitude" placeholder="0.0" value={longitude} onChange={e => setLongitude(e.target.value)} />
        </div>
      </div>

      <br/>
      <br/>
      <h4>Provisioning</h4>
      <hr/>

      <div className="form-group">
        <label htmlFor="controller">Controller</label>
        <select className="form-control" id="controller" value={controller} onChange={e => setController(e.target.value)}>
          <option value="netconf">NETCONF</option>
          <option value="nso">NSO</option>
        </select>
      </div>
      <div className="form-group">
        <label htmlFor="vlan-range">VLAN Ranges</label>
        <input type="text" className="form-control" id="vlan-range" value={vlanRange} onChange={e => setVlanRange(e.target.value)} />
      </div>

      {nsoControllerInputs}
      <br/>
      <input type="hidden" name="node_id" value={nodeId} />

      <button type="submit" className="btn btn-primary" style={{margin: '0 2px'}}>Submit</button>
      <button type="button" className="btn btn-default" style={{margin: '0 2px'}} data-dismiss="modal" onClick={onCancel}>Cancel</button>
    </form>
  );
};
