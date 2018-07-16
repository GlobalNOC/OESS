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
