import React from 'react';
import { PageContext } from "../../contexts/PageContext.jsx";

import { LinkProvider } from "../../components/links/LinkProvider.jsx";
import { LinkTable } from "../../components/links/LinkTable.jsx";

class Links extends React.Component {
    constructor(props){
        super(props);
    }
    render(){
        return (
            <>
                <div>
                    <p className="title"><b>Links</b></p>
                    <p className="subtitle">Create, edit, reorder, or delete Link entries.</p>
                </div>
                <br />
                <LinkProvider render={ props => <LinkTable {...props } />}/>
            </>
        );
    }
}

Links.contextType = PageContext;
export { Links };