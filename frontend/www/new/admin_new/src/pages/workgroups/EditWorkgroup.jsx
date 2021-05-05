import React, { useContext, useEffect, useState } from "react";
import { withRouter } from "react-router-dom";

import { getWorkgroup, editWorkgroup } from '../../api/workgroup.js';
import { WorkgroupForm } from '../../components/workgroups/WorkgroupForm.jsx';
import { PageContext } from "../../contexts/PageContext.jsx";

import "../../style.css";

const editWorkgroupComponent = (props) => {
  const { history, match } = props;
  const { setStatus } = useContext(PageContext);
  const [workgroup, setWorkgroup] = useState(null);

  useEffect(() => {
    getWorkgroup(match.params["id"]).then((workgroup) => {
      setWorkgroup(workgroup);
    }).catch((error) => {
      setStatus(error);
    });
  }, [match]);

  let submitHandler = async (e) => {
    try {
      await editWorkgroup(e);
      setStatus({type:'success', message:`Workgroup '${e.name}' was successfully edited.`});
    } catch (error) {
      setStatus({type:'error', message:error.toString()});
    }
    history.push('/workgroups');
  };

  let cancelHandler = async () => {
    history.push('/workgroups');
  };

  if (workgroup == null) {
    return <p>Loading...</p>;
  }

  return (
    <div>
      <div>
        <p className="title"><b>Edit Workgroup:</b> {workgroup.name}</p>
        <p className="subtitle">Edit and Manage Workgroup Users and Interfaces.</p>
      </div>
      <br />

      <WorkgroupForm workgroup={workgroup} onSubmit={submitHandler} onCancel={cancelHandler} />
    </div>
  );
};

export const EditWorkgroup = withRouter(editWorkgroupComponent);
