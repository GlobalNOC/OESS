import React, { useContext } from "react";
import { withRouter } from "react-router-dom";

import { createNode } from '../../api/nodes.js';
import { NodeForm } from '../../components/nodes/NodeForm.jsx';
import { PageContext } from "../../contexts/PageContext.jsx";

import "../../style.css";

const createNodeComponent = (props) => {
  const { history } = props;
  const { setStatus } = useContext(PageContext);

  let submitHandler = async (e) => {
    try {
      await createNode(e);
      console.log(e);
      setStatus({type:'success', message:`Node '${e.name}' was successfully created.`});
    } catch (error) {
      setStatus({type:'error', message:error});
    }
    // history.push('/nodes');
  };

  let cancelHandler = async () => {
    history.push('/nodes');
  };

  return (
    <div>
      <div>
        <p className="title"><b>Create Node</b></p>
        <p className="subtitle">Create a new Node.</p>
      </div>
      <br />

      <NodeForm node={null} onSubmit={submitHandler} onCancel={cancelHandler} />
    </div>
  );
}

export const CreateNode = withRouter(createNodeComponent);
