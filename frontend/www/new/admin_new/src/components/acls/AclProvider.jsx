import React, { useContext, useEffect, useState } from "react";

import { getAcls } from '../../api/acls.js';
import { PageContext } from "../../contexts/PageContext.jsx";

export const AclProvider = (props) => {
    const page = useContext(PageContext);
    const [aclEntries, setAclEntries] = useState([]);

    useEffect(() => {
        getAcls(props.interfaceId).then(acls => {
            setAclEntries(acls);
        }).catch(error => {
            console.error(error);
            page.setStatus({type: 'error', message: error.toString()});
        });
    }, [props.interfaceId]);

    const reloadAcls = () => {
        getAcls(props.interfaceId).then(acls => {
            console.info("Reloading ACLs");
            setAclEntries(acls);
        }).catch(error => {
            console.error(error);
            page.setStatus({type: 'error', message: error.toString()});
        });
    };

    return props.render({ acls: aclEntries, reloadAcls });
}
