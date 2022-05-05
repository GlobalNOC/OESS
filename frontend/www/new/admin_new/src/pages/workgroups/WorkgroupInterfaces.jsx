import React, { useContext, useState, useEffect } from "react";
import { withRouter } from "react-router-dom";

import { PageContext } from "../../contexts/PageContext.jsx";
import { BaseModal } from "../../components/generic_components/BaseModal.jsx";
import { CustomTable } from "../../components/generic_components/CustomTable.jsx";
import { AddWorkgroupInterfaceForm } from "../../components/workgroups/AddWorkgroupInterfaceForm.jsx";
import { getInterfacesByWorkgroupId, editInterface } from '../../api/interfaces.js';

import "../../style.css";

export const WorkgroupInterfaces = (props) => {
  const { history, match } = props;
  const { setStatus } = useContext(PageContext);
  const [ interfaces, setInterfaces]  = useState([]);
  const [ addInterfaceModalVisible, setAddInterfaceModalVisible ] = useState(false);

  let workgroup_id = match.params['id'];

  useEffect(() => {
    getInterfacesByWorkgroupId(workgroup_id).then(interfaces => {
      setInterfaces(interfaces);
    }).catch(error => {
      setStatus({type: 'error', message: error.toString()});
    });
  },[]);

  let addInterface = async (data) => {
    let payload = {
      interfaceId: data.interfaceId,
      workgroupId: workgroup_id,
    }

    try {
      await editInterface(payload);
      history.go(0);
    } catch(error) {
      setAddInterfaceModalVisible(false);
      setStatus({type: 'error', message: error.toString()});
    }
}

  let removeInterface = async (data) => {
    let ok = confirm(`Are you sure you want to remove ${data.node} - ${data.name} from workgroup?`);
    if (!ok) {
      return;
    }

    let payload = {
      interfaceId: data.interface_id,
      workgroupId: -1,
    }

    try {
      await editInterface(payload);
      history.go(0);
    } catch(error) {
      setAddInterfaceModalVisible(false);
      setStatus({type: 'error', message: error.toString()});
    }
  }

  const rowButtons = (data) => {
    return <button type="button" className="btn btn-default btn-xs" onClick={(e) => removeInterface(data)}>Remove Interface</button>;
  }

  let columns = [
    { name: 'ID', key: 'interface_id' },
    { name: 'Node', key: 'node' },
    { name: 'Interface', key: 'name' },
    { name: 'Description', key: 'description' },
    { name: '', render: rowButtons, style: {textAlign: 'right'} },
   ];
  
  return (
    <div>
      <BaseModal visible={addInterfaceModalVisible} header="Add interface to workgroup" modalID="migrate-interface-modal" onClose={() => setAddInterfaceModalVisible(false)}>
        <AddWorkgroupInterfaceForm onSubmit={addInterface} onCancel={() => setAddInterfaceModalVisible(false)} />
      </BaseModal>

      <div>
        <p className="title"><b>Workgroup Interfaces</b></p>
        <p className="subtitle">Add or remove Workgroup Interfaces.</p>
      </div>
      <br />
      <CustomTable columns={columns} rows={interfaces} size={15} filter={['interface_id', 'node', 'name', 'description']}>
        <CustomTable.MenuItem><button className="btn btn-default" onClick={() => setAddInterfaceModalVisible(true)}>Add Interface</button></CustomTable.MenuItem>
      </CustomTable>
    </div>
  );
}
