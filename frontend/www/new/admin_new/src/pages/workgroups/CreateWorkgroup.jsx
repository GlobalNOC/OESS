import React from "react";
import ReactDOM from "react-dom";
import { withRouter } from "react-router-dom";

import "../../style.css";


import { createWorkgroup } from '../../api/workgroup.js';

import { WorkgroupForm } from '../../components/workgroups/WorkgroupForm.jsx';


const createWorkgroupComponent = (props) => {
  const { history } = props;

  let submitHandler = async (e) => {
    try {
      let results = await createWorkgroup(e);
      console.info(results);
    } catch (error) {
      console.error(error);
    }
    history.push('/workgroups');
  }

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
