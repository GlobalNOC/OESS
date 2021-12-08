import { config } from '.././config.jsx';

export const getInterfaces = async (nodeId) => {
  let url = `${config.base_url}services/interface.cgi?method=get_interfaces&node_id=${nodeId}`;

  const resp = await fetch(url, {method: 'get', credentials: 'include'});
  const data = await resp.json();

  if (data.error_text) throw data.error_text;
  return data.results;
}
