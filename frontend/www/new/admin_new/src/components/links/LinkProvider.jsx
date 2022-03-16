import React, { useContext, useEffect, useState } from "react";

import { getLinks } from '../../api/links.js';
import { PageContext } from "../../contexts/PageContext.jsx";

export const LinkProvider = (props) => {
    const page = useContext(PageContext);
    const [linkEntries, setLinkEntries] = useState([]);

    useEffect(() => {
       getLinks().then(links => {
           setLinkEntries(links);
       }).catch(error => {
           console.error(error);
           page.setStatus({type: 'error', message: error.toString()});
       });
    }, []);

    const reloadLinks = () => {    
        getLinks().then(links => {
            setLinkEntries(links);
        }).catch(error => {
            console.error(error);
            page.setStatus({type: 'error', message: error.toString()});
        });
    };

    return props.render({ links: linkEntries, reloadLinks });
}
