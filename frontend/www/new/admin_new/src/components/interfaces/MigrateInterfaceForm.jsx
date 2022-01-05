import React, { useEffect, useState } from "react";

import { getInterfaces } from "../../api/interfaces";
import { getNodes } from "../../api/nodes";

import { AutoComplete } from "../generic_components/AutoComplete";


export const MigrateInterfaceForm = (props) => {
  const [nodeId, setNodeId] = useState(-1);
  const [nodes, setNodes] = useState([]);
  
  const [dstInterfaceId, setDstInterfaceId] = useState(-1);
  const [interfaces, setInterfaces] = useState([]);

  const validateForm = (e) => {
    // TODO Validate that both interfaces are under the same network
    // controller. This concept might be something to integrate more widely
    // within this component.
    return true;
  };

  useEffect(() => {
    try {
      getInterfaces(nodeId).then((interfaces) => {
        setInterfaces(interfaces);
        setDstInterfaceId(-1);
      });
    } catch (error) {
      // TODO Show error message to user? If this fails interfaces can't be loaded.
      setInterfaces([]);
      setDstInterfaceId(-1);
      console.error(error);
    }
  }, [nodeId]);
  
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

  const onSubmit = (e) => {
    e.preventDefault();
    const payload = {
      srcInterfaceId: parseInt(props.interfaceId),
      dstInterfaceId: dstInterfaceId,
    };
    let ok = validateForm(payload);
    if (!ok) return;
    console.log('submit:', payload, 'validated:', ok);

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
      <div className="alert alert-warning" role="alert">
        <p>
          <b>Warning:</b> Migrating an interface will move all Connection Endpoints, all ACLs, all Interface configuration, and will trigger a diff of the affected nodes.
        </p>
      </div>

      <div className="form-group">
        <label htmlFor="dstInterfaceNode">Node</label>
        <AutoComplete id="dstInterfaceNode" name="dstInterfaceNode" placeholder="Search by node" value={nodeId} onChange={e => setNodeId(e)} suggestions={nodeSuggestions} />
      </div>
      <div className="form-group">
        <label htmlFor="dstInterfaceName">Interface</label>
        <AutoComplete id="dstInterfaceName" name="dstInterfaceName" placeholder="Search by interface" value={dstInterfaceId} onChange={e => setDstInterfaceId(e)} suggestions={intfSuggestions} />
      </div>

      <br/>
      <input type="hidden" name="src_interface_id" value={props.interfaceId} />
      <input type="hidden" name="dst_interface_id" value={dstInterfaceId} />

      <button type="submit" className="btn btn-primary" style={{margin: '0 2px'}}>Migrate Interface</button>
      <button type="button" className="btn btn-default" style={{margin: '0 2px'}} data-dismiss="modal" onClick={onCancel}>Cancel</button>
    </form>
  );
}
