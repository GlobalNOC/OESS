import React from "react";
import { useEffect } from "react";
import { useState } from "react";
import { Link } from "react-router-dom";
import { withRouter } from "react-router-dom";
import { Table } from '../generic_components/Table.jsx';
import { PageContext } from "../../contexts/PageContext.jsx";
import "../../style.css";
import { useContext } from "react";
import { deleteLink } from "../../api/links.js";

const LinkTable = (props) => {
    const { history, match } = props;
    const page = useContext(PageContext);

    const onDeleteLink = (linkID) => {
        deleteLink(linkID).then(result => {
           props.reloadLinks();
           page.setStatus({type: 'success', message: 'Link entry was successfully deleted.'});
        }).catch(error => {
             console.error(error);
             page.setStatus({type: 'error', message: error});
        });
    };

    const editLink = (link) => {
      console.log(link);
    };

    let rowButtons = (data) => {
        return (
            <>
                <div className="btn-group">
                    <Link to={`/${data.link_id}`} className="btn btn-default btn-xs">Edit Link</Link>
                    <button type="button" className="btn btn-default btn-xs dropdown-toggle" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false">
                        <span>▾</span>{/* className="caret" doesn't work idk why */}
                        <span className="sr-only">Toggle Dropdown</span>
                    </button>
                    <ul className="dropdown-menu" style={{fontSize: '12px'}}>
                        <li><a href="#" onClick={e => onDeleteLink(data.link_id)}>Delete Link</a></li>
                    </ul>                    
                </div>
            </>
        );
    };

    let columns = [
        {name: 'Name', key: 'name'},
        {name: 'Status', key: 'status'},
        {name: 'URN', key: 'remote_urn'},
        { name: '', render: rowButtons, style: {textAlign: 'right' } }
    ];

    return (
        <div>
            <form id="user_search_div" className="form-inline">

            </form>
            <br />

            <Table columns={columns} rows={props.links} />
        </div>
    );
}

export { LinkTable };