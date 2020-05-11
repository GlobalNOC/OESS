import { testConfig } from '.././test.jsx';

export async function getWorkgroups() {
  let url = `${testConfig.user}services/data.cgi?method=get_workgroups`;

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
  let url = `${testConfig.user}services/workgroup_manage.cgi?method=get_all_workgroups`;

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
