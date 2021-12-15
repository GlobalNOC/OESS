import React, { useEffect, useState } from "react";

import { config } from "../../../config";
import { getDiff } from "../../../api/nodes";
import { Diff } from "./Diff.jsx";


// nodeId, onApproval, onCancel
export const DiffApprovalForm = (props) => {
    const [text, setText] = useState('');
    const [error, setError] = useState(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        setLoading(true);

        getDiff(props.nodeId).then(text => {
            setText(text);
            setLoading(false);
        }).catch(error => {
            setError(error);
            setLoading(false);
        });
    }, [props.nodeId]);

    let onSubmit = (e) => {
        e.preventDefault();
    
        if (props.onApproval) {
          props.onApproval(node);
        }
      };
    
    let onCancel = (e) => {
        if (props.onCancel) {
            props.onCancel(e);
        }
    };

    let content = <Diff text={text} />;
    let disabled = false;

    if (loading) {
        content = (
            <div className="panel panel-default" style={{textAlign: 'center'}}>
                <img src={`${config.base_url}/media/loading.gif`} width="200px;"/>
            </div>
        );
        disabled = true;
    }

    if (error) {
        content = (
            <div style={{padding: '1em 1em'}} className="panel panel-danger">
                <span className="text-danger">{error}</span>
            </div>
        );
        disabled = true;
    }

    if (text === '') {
        content = (
            <div style={{padding: '1em 1em'}} className="panel panel-success">
                <span className="text-success">There are no pending changes.</span>
            </div>
        );
        disabled = true;
    }

    return (
        <div>
            {content}
            <form onSubmit={onSubmit}>
                <button type="submit" className="btn btn-primary" style={{margin: '0 2px'}} disabled={disabled}>Approve Changes</button>
                <button type="button" className="btn btn-default" style={{margin: '0 2px'}} data-dismiss="modal" onClick={onCancel}>Cancel</button>
            </form>
        </div>
    );
};
