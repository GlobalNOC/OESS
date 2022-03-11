import React, { useContext, useEffect, useState } from "react";
import { withRouter } from "react-router-dom";

import { getNode, editNode } from '../../api/nodes.js';
import { NodeForm } from '../../components/nodes/NodeForm.jsx';
import { PageContext } from "../../contexts/PageContext.jsx";

import "../../style.css";

const editNodeComponent = (props) => {
  const { history, match } = props;
  const { setStatus } = useContext(PageContext);
  const [node, setNode] = useState(null);

  useEffect(() => {
    getNode(match.params["id"]).then((node) => {
      setNode(node);
    }).catch((error) => {
      setStatus(error);
    });
  }, [match]);

  let submitHandler = async (e) => {
    try {
      await editNode(e);
      setStatus({type:'success', message:`Node '${e.name}' was successfully edited.`});
    } catch (error) {
      setStatus({type:'error', message:error.toString()});
    }
    history.goBack();
  };

  let cancelHandler = async () => {
    history.goBack();
  };

  if (node == null) {
    return <p>Loading...</p>;
  }

  return (
    <div>
      <div>
        <p className="title"><b>Edit Node:</b> {node.name}</p>
        <p className="subtitle">Edit and Manage Node Entities and Interfaces.</p>
      </div>
      <br />

      <NodeForm node={node} onSubmit={submitHandler} onCancel={cancelHandler} />
    </div>
  );
};

export const EditNode = withRouter(editNodeComponent);
