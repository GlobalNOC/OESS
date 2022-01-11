import React, { useContext } from "react";
import { withRouter } from "react-router-dom";

import { createAcl } from "../../../../api/acls";
import { AclForm } from "../../../../components/acls/AclForm";
import { PageContext } from "../../../../contexts/PageContext";


export const createAclComponent = (props) => {
  const { history, match } = props;
  const { setStatus } = useContext(PageContext);
  
  let submitHandler = async (e) => {
    try {
      await createAcl(e);
      setStatus({type:'success', message:`ACL was successfully created.`});
    } catch (error) {
      setStatus({type:'error', message:error});
    }
    history.go(-1);
  };
  
  let cancelHandler = async () => {
    history.go(-1);
  };
  
  return (
    <div>
      <div>
        <p className="title"><b>Create ACL</b></p>
        <p className="subtitle">Create a new ACL entry.</p>
      </div>
      <br />

      <AclForm acl={{interface_id: match.params['interfaceId']}} onSubmit={submitHandler} onCancel={cancelHandler} />
    </div>
  );
};

export const CreateAcl = withRouter(createAclComponent);
