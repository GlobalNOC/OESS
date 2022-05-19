import React, { useContext } from "react";

import { config } from '../config.jsx';
import { PageContext } from "../contexts/PageContext.jsx";
import { Route } from "react-router-dom";

import "../style.css";


export const AdminRoute = (props) => {
    const { user } = useContext(PageContext);

    if (user.is_admin) {
        return <Route {...props}>{props.children}</Route>;
    }

    return (
        <center>
            <h1>Not Authorized</h1>
            <p>Click <a href={config.base_url}>here</a> to return home.</p>
        </center>
    );
};
