import React, { useContext, useEffect, useState } from "react";
import { withRouter } from "react-router-dom";

import { InterfaceForm } from "../../../components/interfaces/InterfaceForm.jsx";
import { PageContext } from "../../../contexts/PageContext.jsx";

import { getInterface, editInterface } from "../../../api/interfaces.js";

import "../../../style.css";

const editInterfaceComponent = (props) => {
  const { history, match } = props;
  const { setStatus } = useContext(PageContext);

  const [intf, setIntf] = useState(null);

  useEffect(() => {
    getInterface(match.params["interfaceId"]).then(intf => {
      console.log('intf', intf);
      setIntf(intf);
    }).catch(error => {
      console.error(error);
      setStatus({type: 'error', message: error.toString()});
    });
  }, [match]);
    
  let submitHandler = async (e) => {
    try {
      await editInterface(e);
      setStatus({type:'success', message:`Interface '${e.name}' was successfully edited.`});
      history.goBack();
    } catch (error) {
      setStatus({type:'error', message:error.toString()});
    }
  };
    
  let cancelHandler = async () => {
    history.goBack();
  };

  if (intf == null) {
    return <p>Loading</p>;
  };

  return (
    <div>
      <div>
        <p className="title"><b>Edit Interface:</b> <span style={{opacity: 0.85}}>{intf.name}</span></p>
        <p className="subtitle">Edit Interface.</p>
      </div>
      <br />

      <InterfaceForm intf={intf} onSubmit={submitHandler} onCancel={cancelHandler} />
    </div>
  );
};

export const EditInterface = withRouter(editInterfaceComponent);
