import { config } from '../config.jsx';


export const getInterfaces = async (nodeId) => {
  let url = `${config.base_url}/services/interface.cgi?method=get_interfaces&node_id=${nodeId}`;

  const resp = await fetch(url, {method: 'get', credentials: 'include'});
  const data = await resp.json();

  if (data.error_text) throw data.error_text;
  return data.results;
}

export const getInterface = async (interfaceId) => {
  let url = `${config.base_url}/services/interface.cgi?method=get_interface&interface_id=${interfaceId}`;

  const resp = await fetch(url, {method: 'get', credentials: 'include'});
  const data = await resp.json();

  if (data.error_text) throw data.error_text;
  return data.results[0];
}

export const editInterface = async (intf) => {
  let url = `${config.base_url}/services/interface.cgi?method=edit_interface`;
  url += `&interface_id=${intf.interfaceId}`;
  url += `&description=${intf.description}`;
  url += `&cloud_interconnect_type=${intf.cloudInterconnectType}`;
  url += `&cloud_interconnect_id=${intf.cloudInterconnectId}`;
  url += `&workgroup_id=${intf.workgroupId}`;

  const resp = await fetch(url, { method: 'get', credentials: 'include' });
  const data = await resp.json();

  if (data.error_text) throw data.error_text;
  return data.results;
}

export const migrateInterface = async (srcInterfaceId, dstInterfaceId) => {
  let url = `${config.base_url}/services/interface.cgi?method=migrate_interface`;
  url += `&src_interface_id=${srcInterfaceId}`;
  url += `&dst_interface_id=${dstInterfaceId}`;

  const resp = await fetch(url, { method: 'get', credentials: 'include' });
  const data = await resp.json();

  if (data.error_text) throw data.error_text;
  return data.results;
};
