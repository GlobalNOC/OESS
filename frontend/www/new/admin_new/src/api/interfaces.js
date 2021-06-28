import { config } from '.././config.jsx';

export const getInterfaces = async (nodeName) => {
  let url = `${config.base_url}services/data.cgi?method=get_node_interfaces&node=${nodeName}&show_down=1&show_trunk=1`;

  const resp = await fetch(url, {method: 'get', credentials: 'include'});
  const data = await resp.json();

  if (data.error_text) throw data.error_text;
  return data.results;
}
