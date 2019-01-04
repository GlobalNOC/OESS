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
