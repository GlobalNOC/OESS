async function getWorkgroups() {
  let url = `[% path %]services/data.cgi?method=get_workgroups`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    return data.results;
  } catch(error) {
    console.log('Failure occurred in getVRF.');
    console.log(error);
    return null;
  }
}

async function getAllWorkgroups() {
  let url = `[% path %]services/workgroup_manage.cgi?method=get_all_workgroups`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    if (data.error_text) throw data.error_text;
    return data.results;
  } catch(error) {
    console.log('Failure occurred in getAllWorkgroups.');
    console.log(error);
    return [];
  }
}
