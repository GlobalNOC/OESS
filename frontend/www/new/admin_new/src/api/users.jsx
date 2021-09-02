import { config } from '.././config.jsx';

//const config = require('./test.json');


let path = config.base_url;

export async function getUser(user_id) {
  let url = `${config.base_url}/services/user.cgi?method=get_user`;
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

export async function getUsers() {
    let url = `${path}/services/user.cgi?method=get_users`;

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

export async function createUser(user) {
  let url = `${config.base_url}services/user.cgi?method=create_user`;
  url += `&email=${user.email}`;
  url += `&first_name=${user.firstName}`;
  url += `&last_name=${user.lastName}`;
  for (let i = 0; i < user.usernames.length; i++) {
    url += `&username=${user.usernames[i]}`;
  }

  const resp = await fetch(url, {method: 'get', credentials: 'include'});
  const data = await resp.json();
  if (data.error_text) throw data.error_text;
  return data.results[0];
}

/**
 * @param {integer} user_id Id of this user
 * 
 * @returns {object} resp
 * @returns {number} resp.success Set to 1 if request was successful
 */
export async function deleteUser(user_id) {
  let url = `${config.base_url}services/user.cgi?method=delete_user`;
  url += `&user_id=${user_id}`;

  const resp = await fetch(url, {method: 'get', credentials: 'include'});
  const data = await resp.json();
  if (data.error_text) throw data.error_text;
  return data.results[0];
}

export async function editUser(user) {
  let url = `${path}services/user.cgi?method=edit_user`;
  url += `&user_id=${user.userId}`;
  url += `&first_name=${user.firstName}`;
  url += `&last_name=${user.lastName}`;
  url += `&email=${user.email}`;
  for (let i = 0; i < user.usernames.length; i++) {
    url += `&username=${user.usernames[i]}`;
  }

  const resp = await fetch(url, { method: 'get', credentials: 'include' });
  const data = await resp.json();

  if (data.error_text) throw data.error_text;
  return data.results;
}

export default getUsers;
