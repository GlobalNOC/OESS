import React, { useContext } from "react";
import { withRouter } from "react-router-dom";

import { createWorkgroup } from '../../api/workgroup.js';
import { WorkgroupForm } from '../../components/workgroups/WorkgroupForm.jsx';
import { PageContext } from "../../contexts/PageContext.jsx";

import "../../style.css";

const createWorkgroupComponent = (props) => {
  const { history } = props;
  const { setStatus } = useContext(PageContext);

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

  return (
    <div>
      <div>
        <p className="title"><b>Create Workgroup</b></p>
        <p className="subtitle">Create a new Workgroup.</p>
      </div>
      <br />

      <WorkgroupForm workgroup={null} onSubmit={submitHandler} onCancel={cancelHandler} />
    </div>
  );
}

export const CreateWorkgroup = withRouter(createWorkgroupComponent);
