import { config } from '../config.jsx';


export const getEntities = async (workgroupId) => {
  let url = `${config.base_url}/services/entity.cgi?method=get_entities`;
  url += `&workgroup_id=${workgroupId}`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    if (data.error_text) throw data.error_text;
    return data.results;
  } catch(error) {
    console.error('getEntities:', error);
    return [];
  }
};
