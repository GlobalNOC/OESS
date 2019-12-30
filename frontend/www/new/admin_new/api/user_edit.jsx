import { testConfig } from '.././test.jsx';

let path = testConfig.user;
async function editUser(user_id, family_name, email_address, type, status, auth_name) {
    let url = `${path}services/admin/admin.cgi?method=edit_user&user_id={user_id}&family_name={family_name}&email_address={email_address}&type={type}&status={status}&auth_name={auth_name}`;

    try {
        const resp = await fetch(url, { method: 'get', credentials: 'include' });
        const data = await resp.json();
        if (data.error_text) throw data.error_text;
        return data.results;
    } catch (error) {
        console.log('Failure occurred in editUser.');
        console.log(error);
        return [];
    }
}
export default editUser;
