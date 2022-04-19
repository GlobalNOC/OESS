import React, { useContext, useState, useEffect } from "react";
import { withRouter } from "react-router-dom";

import { createWorkgroup } from '../../api/workgroup.js';
import { WorkgroupForm } from '../../components/workgroups/WorkgroupForm.jsx';
import { PageContext } from "../../contexts/PageContext.jsx";
import { CustomTable } from "../../components/generic_components/CustomTable.jsx";
import { getInterfacesByWorkgroupId } from '../../api/interfaces.js';
import "../../style.css";

export const WorkgroupInterfaces = (props) => {
  const { history } = props;
  const { setStatus } = useContext(PageContext);
  const [ interfaces, setInterfaces]  = useState([]);

  let workgroup_id = window.location.href.split('/')[(window.location.href.split('/').length) - 2];
  useEffect(() => {
    async function getData() {
      setInterfaces( await getInterfacesByWorkgroupId(workgroup_id));
    }
    getData();
  },[]);
  
  let submitHandler = async (e) => {
    try {
      await createWorkgroup(e);
      setStatus({type:'success', message:`Workgroup '${e.name}' was successfully created.`});
    } catch (error) {
      setStatus({type:'error', message:error});
    }
    history.push('/workgroups');
  };

  let cancelHandler = async () => {
    history.push('/workgroups');
  };

  let columns = [
    { name: 'ID', key: 'interface_id' },
    { name: 'Endpoint', key: 'node' },
    { name: 'Interface', key: 'name' },
    { name: 'Description', key: 'description' }
   ];
  
  return (
    <div>
      <div>
        <p className="title"><b>Workgroup Interfaces</b></p>
        <p className="subtitle">Add or remove Workgroup Interfaces.</p>
      </div>
      <br />
        <CustomTable columns={columns} rows={interfaces} size={15} filter={['interface_id', 'interface_name', 'description']}>
        </CustomTable>
    </div>
  );
}

// export const CreateWorkgroup = withRouter(createWorkgroupComponent);
