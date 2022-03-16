import React, { useState } from "react";
import { Link } from "react-router-dom";

import { LinkTable } from "../../components/links/LinkTable";
import { LinkProvider } from "../../components/links/LinkProvider";

export const Links = (props) => {
    return (
        <div>
            <div>
                <p className="title"><b>Links</b></p>
                <p className="subtitle">View Links</p>
            </div>
            <br />
            <LinkProvider render={ props => <LinkTable {...props} /> } />
        </div>
    );
};
