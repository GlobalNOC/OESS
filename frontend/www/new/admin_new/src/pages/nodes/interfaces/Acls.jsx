import React, { useContext, useEffect, useState } from "react";
import { withRouter } from "react-router-dom";

import { AclProvider } from "../../../components/acls/AclProvider.jsx";
import { AclTable } from "../../../components/acls/AclTable.jsx";
import { getInterface } from "../../../api/interfaces.js";
import { PageContext } from "../../../contexts/PageContext.jsx";

import "../../../style.css";

const aclsComponent = (props) => {
  const { history, match } = props;
  const [intf, setIntf] = useState(null);
  const { setStatus } = useContext(PageContext);

  useEffect(() => {
    getInterface(match.params["interfaceId"]).then(intf => {
      setIntf(intf);
    }).catch(error => {
      console.error(error);
      setStatus({type: 'error', message: error.toString()});
    });
  }, [match]);

  if (intf == null) {
    return <p>Loading</p>;
  };

  return (
    <div>
      <div>
        <p className="title"><b>Interface ACLs:</b> <span style={{opacity: 0.85}}>{intf.node} {intf.name}</span></p>
        <p className="subtitle">Create, edit, reorder, or delete ACL entries. ACLs are evaluated top to bottom or first to last.</p>
      </div>
      <br />

      <AclProvider interfaceId={match.params["interfaceId"]} render={ props => <AclTable {...props} />} />
    </div>
  );
};

export const Acls = withRouter(aclsComponent);
