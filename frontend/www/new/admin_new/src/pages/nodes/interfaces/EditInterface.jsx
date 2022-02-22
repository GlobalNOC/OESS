import React, { useContext, useEffect, useState } from "react";
import { withRouter } from "react-router-dom";

import { InterfaceForm } from "../../../components/interfaces/InterfaceForm.jsx";
import { PageContext } from "../../../contexts/PageContext.jsx";

import { getInterface, editInterface } from "../../../api/interfaces.js";

import "../../../style.css";

const editInterfaceComponent = (props) => {
  const { history, match } = props;
  const { setStatus } = useContext(PageContext);

  const [interface, setInterface] = useState(null);

  useEffect(() => {
    getInterface(match.params["interfaceId"]).then(intf => {
      console.log('intf', intf);
      setInterface(intf);
    }).catch(error => {
      console.error(error);
      setStatus({type: 'error', message: error.toString()});
    });
  }, [match]);
    
  let submitHandler = async (e) => {
    try {
      await editInterface(e);
      setStatus({type:'success', message:`Interface '${e.name}' was successfully edited.`});
    } catch (error) {
      setStatus({type:'error', message:error.toString()});
    }
    history.goBack();
  };
    
  let cancelHandler = async () => {
    history.goBack();
  };

  if (interface == null) {
    return <p>Loading</p>;
  };

  return (
    <div>
      <div>
        <p className="title"><b>Edit Interface:</b> {interface.name}</p>
        <p className="subtitle">Edit Interface.</p>
      </div>
      <br />

      <InterfaceForm interface={interface} onSubmit={submitHandler} onCancel={cancelHandler} />
    </div>
  );
};

export const EditInterface = withRouter(editInterfaceComponent);
