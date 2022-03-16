import { config } from '../config.jsx';

export const getLink = (linkData) => {
    let link;
    
    return link;
}

//linkData is the data required for selection; updateLink is the new linkData.
export const updateLink = async (linkData, updatedLink) => {
 
}

export const deleteLink = async (linkID) => {
    console.log(linkID);
    let url = `${config.base_url}/services/link.cgi?method=edit_link&link_id=${linkID}&status=down`;
    
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();

    if (data.error_text) throw data.error_text;
    return data.results;

}

export const getLinks = async () => {
    let url = `${config.base_url}/services/link.cgi?method=get_links`;
    
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();

    if (data.error_text) throw data.error_text;   
    return data.results;
}
