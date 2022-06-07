import { config } from '.././config.jsx';

export async function getWorkgroups() {
  let url = `${config.base_url}/services/data.cgi?method=get_workgroups`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    if (data.error_text) throw data.error_text;
    return data.results;
  } catch(error) {
    console.error('getWorkgroups:', error);
    return [];
  }
}

export async function getAllWorkgroups() {
  let url = `${config.base_url}/services/workgroup_manage.cgi?method=get_all_workgroups`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    if (data.error_text) throw data.error_text;
    return data.results;
  } catch(error) {
    console.error('getAllWorkgroups:', error);
    return [];
  }
}

/**
 * @param {object} workgroup Workgroup object
 * @param {string} workgroup.name Name of this workgroup
 * @param {string} workgroup.type Type of this workgroup. Valid arguments are 'demo', 'normal', and 'admin'
 * @param {string} workgroup.externalId Id for external tools only
 * 
 * @returns {object} resp
 * @returns {number} resp.success Set to 1 if request was successful
 * @returns {number} resp.workgroup_id WorkgroupId of the created workgroup
 */
export async function createWorkgroup(workgroup) {
  let validTypes = ['demo', 'normal', 'admin'];
  if (!validTypes.includes(workgroup.type)) {
    throw `Invalid type '${workgroup.type}' used in createWorkgroup.`;
  }

  let url = `${config.base_url}/services/workgroup.cgi?method=create_workgroup`;
  url += `&name=${workgroup.name}`;
  url += `&description=${workgroup.description}`;
  url += `&external_id=${workgroup.externalId}`;
  url += `&type=${workgroup.type}`;

  const resp = await fetch(url, {method: 'get', credentials: 'include'});
  const data = await resp.json();
  if (data.error_text) throw data.error_text;
  return data.results[0];
}

/**
 * @param {integer} workgroup_id Id of this workgroup
 * 
 * @returns {object} resp
 * @returns {number} resp.success Set to 1 if request was successful
 */
export async function deleteWorkgroup(workgroup_id) {
  let url = `${config.base_url}/services/workgroup.cgi?method=delete_workgroup`;
  url += `&workgroup_id=${workgroup_id}`;

  const resp = await fetch(url, {method: 'get', credentials: 'include'});
  const data = await resp.json();
  if (data.error_text) throw data.error_text;
  return data.results[0];
}

/**
 * @param {object} workgroup Workgroup object
 * @param {string} workgroup.name Name of this workgroup
 * @param {string} workgroup.type Type of this workgroup. Valid arguments are 'demo', 'normal', and 'admin'
 * @param {string} workgroup.externalId Id for external tools only
 * @param {string} workgroup.workgroupId Id of workgroup to edit
 * 
 * @returns {object} resp
 * @returns {number} resp.success Set to 1 if request was successful
 * @returns {number} resp.workgroup_id WorkgroupId of the created workgroup
 */
export async function editWorkgroup(workgroup) {
  let validTypes = ['demo', 'normal', 'admin'];
  if (!validTypes.includes(workgroup.type)) {
    throw `Invalid type '${workgroup.type}' used in editWorkgroup.`;
  }

  let url = `${config.base_url}/services/workgroup.cgi?method=edit_workgroup`;
  url += `&name=${workgroup.name}`;
  url += `&description=${workgroup.description}`;
  url += `&external_id=${workgroup.externalId}`;
  url += `&type=${workgroup.type}`;
  url += `&workgroup_id=${workgroup.workgroupId}`;

  const resp = await fetch(url, {method: 'get', credentials: 'include'});
  const data = await resp.json();

  if (data.error_text) throw data.error_text;
  return data.results[0];
}

export async function getWorkgroup(workgroup_id) {
  let url = `${config.base_url}/services/workgroup.cgi?method=get_workgroup`;
  url += `&workgroup_id=${workgroup_id}`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    if (data.error_text) throw data.error_text;
    return data;
  } catch(error) {
    console.error('getWorkgroup:', error);
    return [];
  }
}

export async function getWorkgroupUsers(workgroup_id) {
  let url = `${config.base_url}/services/workgroup.cgi?method=get_workgroup_users`;
  url += `&workgroup_id=${workgroup_id}`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    if (data.error_text) throw data.error_text;
    return data;
  } catch(error) {
    console.error('getWorkgroupUsers:', error);
    return [];
  }
}

export async function modifyWorkgroupUser(workgroup_id, user_id, role) {
  let url = `${config.base_url}/services/workgroup.cgi?method=modify_workgroup_user`;
  url += `&workgroup_id=${workgroup_id}`;
  url += `&user_id=${user_id}`;
  url += `&role=${role}`;

  const resp = await fetch(url, {method: 'get', credentials: 'include'});
  const data = await resp.json();

  if (data.error_text) throw data.error_text;
  return data.results[0];
}

export async function removeWorkgroupUser(workgroup_id, user_id) {
  let url = `${config.base_url}/services/workgroup.cgi?method=remove_workgroup_user`;
  url += `&workgroup_id=${workgroup_id}`;
  url += `&user_id=${user_id}`;

  const resp = await fetch(url, {method: 'get', credentials: 'include'});
  const data = await resp.json();

  if (data.error_text) throw data.error_text;
  return data.results[0];
}

export async function addWorkgroupUser(workgroup_id, user_id, role) {
  let url = `${config.base_url}/services/workgroup.cgi?method=add_workgroup_user`;
  url += `&workgroup_id=${workgroup_id}`;
  url += `&user_id=${user_id}`;
  url += `&role=${role}`;

  const resp = await fetch(url, {method: 'get', credentials: 'include'});
  const data = await resp.json();

  if (data.error_text) throw data.error_text;
  return data.results[0];
}
