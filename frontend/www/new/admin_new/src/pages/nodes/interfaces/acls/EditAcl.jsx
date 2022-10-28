import React, { useContext, useEffect, useState } from "react";
import { withRouter } from "react-router-dom";

import { editAcl, getAcl } from "../../../../api/acls";
import { getInterface } from "../../../../api/interfaces.js";

import { AclForm } from "../../../../components/acls/AclForm";
import { PageContext } from "../../../../contexts/PageContext";

export const editAclComponent = (props) => {
  const { history, match } = props;
  const { setStatus } = useContext(PageContext);
  const [acl, setAcl] = useState(null);
  
  useEffect(() => {
    getAcl(match.params["interfaceAclId"]).then(acl => {
      getInterface(match.params["interfaceId"]).then(intf => {
        acl.interface = intf;
        setAcl(acl);
      }).catch(error => {
        setStatus({type: 'error', message: error.toString()});
      });
    }).catch(error => {
      setStatus({type: 'error', message: error.toString()});
    });
  }, [match]);

  let submitHandler = async (e) => {
    try {
      await editAcl(e);
      setStatus({type:'success', message:`ACL was successfully edited.`});
    } catch (error) {
      setStatus({type:'error', message:error.toString()});
    }
    history.goBack();
  };
  
  let cancelHandler = async () => {
    history.goBack();
  };

  if (acl == null || !acl.interface) {
    return <p>Loading...</p>;
  }
  
  return (
    <div>
      <div>
        <p className="title"><b>Edit ACL:</b> <span style={{opacity: 0.85}}>{acl.interface.node} {acl.interface.name}</span></p>
        <p className="subtitle">Edit ACL entry.</p>
      </div>
      <br />

      <AclForm acl={acl} onSubmit={submitHandler} onCancel={cancelHandler} />
    </div>
  );
};

export const EditAcl = withRouter(editAclComponent);
