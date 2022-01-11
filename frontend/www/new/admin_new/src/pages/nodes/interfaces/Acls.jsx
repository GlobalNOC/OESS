import React, { useContext, useEffect, useState } from "react";
import { withRouter } from "react-router-dom";

import { AclProvider } from "../../../components/acls/ACLProvider.jsx";
import { AclTable } from "../../../components/acls/AclTable.jsx";

import "../../../style.css";

const aclsComponent = (props) => {
  const { history, match } = props;

  return (
    <div>
      <div>
        <p className="title"><b>Interface ACLs</b></p>
        <p className="subtitle">Create, edit, reorder, or delete ACL entries. ACLs are evaluated top to bottom or first to last.</p>
      </div>
      <br />

      <AclProvider interfaceId={match.params["interfaceId"]} render={ props => <AclTable {...props} />} />
    </div>
  );
};

export const Acls = withRouter(aclsComponent);
