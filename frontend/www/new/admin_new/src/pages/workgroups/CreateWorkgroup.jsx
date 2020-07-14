import React from "react";
import ReactDOM from "react-dom";
import { withRouter } from "react-router-dom";

import "../../style.css";


import { getAllWorkgroups } from '../../api/workgroup.js';

import { WorkgroupForm } from '../../components/workgroups/WorkgroupForm.jsx';


const createWorkgroup = (props) => {
  const { history } = props;

  let submitHandler = (e) => {
    console.log(e);
  }
  let cancelHandler = (e) => {
    console.log('goto workgroups');
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

export const CreateWorkgroup = withRouter(createWorkgroup);
