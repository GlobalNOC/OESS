import { testConfig } from '.././test.jsx';

//const config = require('./test.json');


let path = testConfig.user;
async function getUsers() {
    let url = `${path}services/admin/admin.cgi?method=get_users`;

    try {
        const resp = await fetch(url, { method: 'get', credentials: 'include' });
        const data = await resp.json();
        if (data.error_text) throw data.error_text;
        return data.results;
    } catch (error) {
        console.log('Failure occurred in get_users.');
        console.log(error);
        return [];
    }
}
export default getUsers;
