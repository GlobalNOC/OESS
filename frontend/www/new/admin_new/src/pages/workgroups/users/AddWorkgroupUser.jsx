import React, { useContext } from "react";
import { withRouter } from "react-router-dom";

import { addWorkgroupUser } from '../../../api/workgroup.js';
import { AddWorkgroupUserForm } from '../../../components/workgroups/AddWorkgroupUserForm.jsx';
import { PageContext } from "../../../contexts/PageContext.jsx";

import "../../../style.css";

const addWorkgroupUserComponent = (props) => {
  const { history, match } = props;
  const { setStatus } = useContext(PageContext);

  let submitHandler = async (e) => {
    try {
      await addWorkgroupUser(e.workgroupId, e.userId, e.role);
      setStatus({type:'success', message:`User '${e.username}' was successfully added.`});
    } catch (error) {
      setStatus({type:'error', message:error});
    }
    history.push(`/workgroups/${match.params["id"]}/users`);
  };

  let cancelHandler = async () => {
    history.goBack();
  };

  return (
    <div>
      <div>
        <p className="title"><b>Add User</b></p>
        <p className="subtitle">Add a User to Workgroup.</p>
      </div>
      <br />

      <AddWorkgroupUserForm workgroupId={parseInt(match.params["id"])} onSubmit={submitHandler} onCancel={cancelHandler} />
    </div>
  );
}

export const AddWorkgroupUser = withRouter(addWorkgroupUserComponent);
