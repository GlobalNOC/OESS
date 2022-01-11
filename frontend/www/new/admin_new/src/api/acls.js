import { config } from '../config.jsx';


export const getAcl = async (interfaceAclId) => {
  let url = `${config.base_url}/services/acl.cgi?method=get_acl&interface_acl_id=${interfaceAclId}`;
  
  const resp = await fetch(url, {method: 'get', credentials: 'include'});
  const data = await resp.json();
  
  if (data.error_text) throw data.error_text;
  return data.results[0];
}

export const getAcls = async (interfaceId) => {
  let url = `${config.base_url}/services/acl.cgi?method=get_acls&interface_id=${interfaceId}`;

  const resp = await fetch(url, {method: 'get', credentials: 'include'});
  const data = await resp.json();

  if (data.error_text) throw data.error_text;
  return data.results;
}

/**
 * createAcl creates a new ACL and returns a hash containing success and
 * interface_acl_id upon success.
 */
export const createAcl = async (acl) => {
  let url = `${config.base_url}/services/acl.cgi?method=create_acl`;
  url += `&allow_deny=${acl.allowDeny}`;
  url += `&start=${acl.start}`;
  url += `&end=${acl.end}`;
  url += `&interface_id=${acl.interfaceId}`;
  url += `&notes=${acl.notes}`;

  if (acl.workgroupId !== null && acl.workgroupId !== -1) url += `&workgroup_id=${acl.workgroupId}`;
  if (acl.entityId !== null && acl.entityId !== -1) url += `&entity_id=${acl.entityId}`;

  const resp = await fetch(url, {method: 'get', credentials: 'include'});
  const data = await resp.json();
  
  if (data.error_text) throw data.error_text;
  return data.results[0];  
};

/**
 * deleteAcl deletes the specified ACL entry.
 *
 * @param {integer} interfaceAclId - Identifier of the acl entry
 */
export const deleteAcl = async (interfaceAclId) => {
  let url = `${config.base_url}/services/acl.cgi?method=delete_acl&interface_acl_id=${interfaceAclId}`;

  const resp = await fetch(url, {method: 'get', credentials: 'include'});
  const data = await resp.json();
  
  if (data.error_text) throw data.error_text;
  return data.results[0];
};

/**
 * editAcl edits the specified ACL.
 */
export const editAcl = async (acl) => {
  let url = `${config.base_url}/services/acl.cgi?method=edit_acl&interface_acl_id=${acl.interfaceAclId}`;
  url += `&allow_deny=${acl.allowDeny}`;
  url += `&start=${acl.start}`;
  url += `&end=${acl.end}`;
  url += `&interface_id=${acl.interfaceId}`;
  url += `&notes=${acl.notes}`;
  url += `&eval_position=${acl.evalPosition}`;

  url += ('interfaceId' in acl) ? `&interface_id=${acl.interfaceId}` : '';
  url += ('notes' in acl) ? `&notes=${acl.notes}` : '';

  if (acl.workgroupId !== null && acl.workgroupId !== -1) url += `&workgroup_id=${acl.workgroupId}`;
  if (acl.entityId !== null && acl.entityId !== -1) url += `&entity_id=${acl.entityId}`;

  const resp = await fetch(url, {method: 'get', credentials: 'include'});
  const data = await resp.json();

  if (data.error_text) throw data.error_text;
  return data.results[0];
};

export const increaseAclPriority = async (acl) => {
    acl.evalPosition = parseInt(acl.evalPosition) - 10;
    return editAcl(acl);
};

export const decreaseAclPriority = async (acl) => {
  acl.evalPosition = parseInt(acl.evalPosition) + 10;
  return editAcl(acl);
};
