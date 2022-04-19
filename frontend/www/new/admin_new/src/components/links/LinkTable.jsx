import React, { useContext, useEffect, useState } from "react";
import { withRouter } from "react-router-dom";
import { Link } from "react-router-dom";

import { PageContext } from "../../contexts/PageContext.jsx";
import { CustomTable } from "../generic_components/CustomTable.jsx";

import "../../style.css";


export const LinkTable = (props) => {
    const { history, match } = props;
    const page = useContext(PageContext);

    let columns = [
        {name: '', style: {verticalAlign: 'middle', fontSize: '.6em'}, render: (link) => <span title={link.status}>{(link.status === "up") ? "🟢" : "🔴"}</span>},
        {name: 'ID', key: 'link_id'},
        {name: 'Name', key: 'name'},
        {name: 'URN', key: 'remote_urn'}
    ];

    return <CustomTable columns={columns} rows={props.links} size={15} filter={['link_id', 'name', 'remote_urn']} />;
}
