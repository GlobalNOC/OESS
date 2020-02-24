import { testConfig } from '.././test.jsx';

let path = testConfig.user;
async function getCurrentUser() {
    let url = `${path}services/user.cgi?method=get_current`;

    try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    return data.results[0];
  } catch(error) {
    console.log('Failure occurred in getVRF.');
    console.log(error);
    return null;
  }
}
export default getCurrentUser;
