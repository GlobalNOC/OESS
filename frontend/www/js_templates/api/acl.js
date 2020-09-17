/**
 * getACL returns the specified ACL.
 *
 * @param {integer} aclID - Identifier of the relevant acl
 */
async function getACL(aclID) {
    let url = `[% path %]services/workgroup_manage.cgi?method=get_acls&interface_acl_id=${aclID}`;

    try {
        const resp = await fetch(url, {method: 'get', credentials: 'include'});
        const data = await resp.json();
        if (data.error_text) throw data.error_text;
        if (data.results.length < 1) return null;

        return data.results[0];
    } catch(error) {
        console.log('Failure occurred in getACL.');
        console.log(error);
        return null;
    }
}

/**
 * getACLs returns a list of all ACLs on interfaceID.
 *
 * @param {integer} interfaceID - Identifier of the relevant interface
 */
async function getACLs(interfaceID) {
    let url = `[% path %]services/workgroup_manage.cgi?method=get_acls&interface_id=${interfaceID}`;

    try {
        const resp = await fetch(url, {method: 'get', credentials: 'include'});
        const data = await resp.json();
        if (data.error_text) throw data.error_text;

        return data.results;
    } catch(error) {
        console.log('Failure occurred in getACLs.');
        console.log(error);
        return [];
    }
}

/**
 * deleteACL deletes the specified ACL returning true upon success.
 *
 * @param {integer} aclID - Identifier of the relevant acl
 */
async function deleteACL(aclID) {
    let url = `[% path %]services/workgroup_manage.cgi?method=remove_acl&interface_acl_id=${aclID}`;

    try {
        const resp = await fetch(url, {method: 'get', credentials: 'include'});
        const data = await resp.json();

        if (data.error_text) throw data.error_text;
        if (data.results.length < 1) return null;

        return data.results[0]['success'] === 1 ? true : false;
    } catch(error) {
        console.log('Failure occurred in deleteACL.');
        console.log(error);
        return false;
    }
}

/**
 * modifyACL modifies the specified ACL returning true upon success.
 *
 * @param {integer} aclID - Identifier of the relevant acl
 */
async function modifyACL(acl) {
    console.log(acl);

  let url = `[% path %]services/workgroup_manage.cgi?method=update_acl&interface_acl_id=${acl.aclID}`;
  url += `&eval_position=${acl.position}`;
  url += `&allow_deny=${acl.allow}`;
  url += `&start=${acl.low}`;
  url += ('interfaceID' in acl ? `&interface_id=${acl.interfaceID}` : '');

  if ('entityID' in acl && acl.entityID && acl.entityID !== -1) {
    url += `&entity_id=${acl.entityID}`;
  }

  if ('selectedWorkgroupID' in acl && acl.selectedWorkgroupID) {
      url += `&workgroup_id=${acl.selectedWorkgroupID}`;
  }

  url += `&end=${acl.high}`;
  url += ('notes' in acl ? `&notes=${acl.notes}` : '');

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();

    if (data.error_text) throw data.error_text;
    if (data.results.length < 1) return null;

    return data.results[0];
  } catch(error) {
    console.log('Failure occurred in modifyACL.');
    console.log(error);
    return false;
  }
}

/**
 * addACL creates a new ACL and returns a hash containing success and
 * interface_acl_id upon success.
 */
async function addACL(acl) {
  let url = `[% path %]services/workgroup_manage.cgi?method=add_acl`;
  url += `&allow_deny=${acl.allow}`;
  url += `&vlan_start=${acl.low}`;
  url += `&interface_id=${acl.interfaceID}`;
  url += `&entity_id=${acl.entityID}`;
  url += (acl.selectedWorkgroupID === -1 ? '' : `&workgroup_id=${acl.selectedWorkgroupID}`);
  url += `&vlan_end=${acl.high}`;
  url += `&notes=${acl.notes}`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    if (data.error_text) throw data.error_text;
    if (data.results.length < 1) return null;

    return data.results[0];
  } catch(error) {
    console.log('Failure occurred in addACL.');
    console.log(error);
    return false;
  }
}
