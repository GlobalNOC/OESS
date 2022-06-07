import React, { useEffect, useState } from "react";

import { getInterfaces } from "../../api/interfaces";
import { getNodes } from "../../api/nodes";

import { AutoComplete } from "../generic_components/AutoComplete";


export const AddWorkgroupInterfaceForm = (props) => {
  const [nodeId, setNodeId] = useState(-1);
  const [nodes, setNodes] = useState([]);
  
  const [interfaceId, setInterfaceId] = useState(-1);
  const [interfaces, setInterfaces] = useState([]);

  const validateForm = (e) => {
    return true;
  };

  useEffect(() => {
    try {
      getNodes().then((nodes) => {
        setNodes(nodes);
      });
    } catch (error) {
      // TODO Show error message to user? If this fails nodes can't be loaded.
      setNodes([]);
      console.error(error);
    }
  }, [props.interfaceId]);

  useEffect(() => {
    try {
      getInterfaces(nodeId).then((interfaces) => {
        setInterfaces(interfaces);
        setInterfaceId(-1);
      });
    } catch (error) {
      // TODO Show error message to user? If this fails interfaces can't be loaded.
      setInterfaces([]);
      setInterfaceId(-1);
      console.error(error);
    }
  }, [nodeId]);
  
  const onSubmit = (e) => {
    e.preventDefault();
    const payload = {
      interfaceId: interfaceId,
    };
    let ok = validateForm(payload);
    if (!ok) return;

    if (props.onSubmit) {
      props.onSubmit(payload);
    }
  };

  const onCancel = (e) => {
    if (props.onCancel) {
      props.onCancel(e);
    }
  };

  let nodeSuggestions = nodes.map(n => {
    return {name: n.name, value: parseInt(n.node_id)};
  });
  let intfSuggestions = interfaces.map(i => {
    return {name: i.name, value: parseInt(i.interface_id)};
  });

  return (
    <form onSubmit={onSubmit}>
      <div className="form-group">
        <label htmlFor="interfaceNode">Node</label>
        <AutoComplete id="interfaceNode" name="interfaceNode" placeholder="Search by node" value={nodeId} onChange={e => setNodeId(e)} suggestions={nodeSuggestions} />
      </div>
      <div className="form-group">
        <label htmlFor="interfaceName">Interface</label>
        <AutoComplete id="interfaceName" name="interfaceName" placeholder="Search by interface" value={interfaceId} onChange={e => setInterfaceId(e)} suggestions={intfSuggestions} />
      </div>
      <br/>

      <button type="submit" className="btn btn-primary" style={{margin: '0 2px'}}>Add Interface</button>
      <button type="button" className="btn btn-default" style={{margin: '0 2px'}} data-dismiss="modal" onClick={onCancel}>Cancel</button>
    </form>
  );
}
