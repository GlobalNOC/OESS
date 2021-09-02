import { config } from '.././config.jsx';

let path = config.base_url;
async function addUser(user_id, first_name, family_name, email_address, type, status, auth_name) {
    let url = `${path}/services/admin/admin.cgi?method=add_user&user_id=${user_id}&first_name=${first_name}&family_name=${family_name}&email_address=${email_address}&type=${type}&status=${status}&auth_name=${auth_name}`;

    try {
        const resp = await fetch(url, { method: 'get', credentials: 'include' });
        const data = await resp.json();
        if (data.error_text) throw data.error_text;
        return data.results;
    } catch (error) {
        console.log('Failure occurred in addUser.');
        console.log(error);
        return [];
    }
}
export default addUser;
