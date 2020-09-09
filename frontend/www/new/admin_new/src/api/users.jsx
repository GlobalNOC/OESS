import { testConfig } from '.././test.jsx';

//const config = require('./test.json');


let path = testConfig.user;

export async function getUser(user_id) {
  let url = `${testConfig.user}services/user.cgi?method=get_user`;
  url += `&user_id=${user_id}`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    if (data.error_text) throw data.error_text;
    return data;
  } catch(error) {
    console.error(`Failure occurred in getUser: ${error}`);
    return null;
  }
}

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

export async function editUser(user) {
  let url = `${path}services/user.cgi?method=edit_user`;
  url += `&user_id=${user.userId}`;
  url += `&first_name=${user.firstName}`;
  url += `&last_name=${user.lastName}`;
  url += `&email=${user.email}`;
  url += `&username=${user.username}`;

  const resp = await fetch(url, { method: 'get', credentials: 'include' });
  const data = await resp.json();

  if (data.error_text) throw data.error_text;
  return data.results;
}

export default getUsers;
