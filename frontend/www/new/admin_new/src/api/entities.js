import { config } from '../config.jsx';


export const getEntities = async () => {
  let url = `${config.base_url}/services/entities.cgi?method=get_entities`;

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
