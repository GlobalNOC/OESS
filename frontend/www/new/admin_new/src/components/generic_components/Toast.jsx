import React, { useContext } from "react";
import { PageContext } from "../../contexts/PageContext.jsx";

export const Toast = () => {
    const { status, setStatus } = useContext(PageContext);

    let alertClass = '';
    switch(status.type) {
        case 'success':
            alertClass = 'alert alert-success'
            break;
        case 'info':
            alertClass = 'alert alert-info';
            break;
        case 'warning':
            alertClass = 'alert alert-warning';
            break;
        case 'error':
            alertClass = 'alert alert-danger';
            break;
        default:
            return null;
    }

    return (
        <div className={alertClass} role="alert">
            <button type="button" className="close" aria-label="Close" onClick={() => setStatus({type: null})}><span aria-hidden="true">&times;</span></button>
            <p>{status.message}</p>
        </div>
    );
}
