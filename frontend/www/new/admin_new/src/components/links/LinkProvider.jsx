import React from "react";
import { useEffect } from "react";
import { useContext } from "react";
import { useState } from "react";
import { PageContext } from "../../contexts/PageContext.jsx";
import { getLinks } from '../../api/links.js';

export const LinkProvider = (props) => {
    const page = useContext(PageContext);
    const [linkEntries, setLinkEntries] = useState([]);
    let links = [];
    useEffect(() => {
       getLinks().then(links => {
           console.log(links);
           setLinkEntries(links);
       }).catch(error => {
           console.error(error);
           page.setStatus({type: 'error', message: error.toString()});
       });        
    }, [props.linkId]);

    const reloadLinks = () => {    
        //setLinkEntries(links);        
    };

    return props.render({ links: linkEntries, reloadLinks });
}