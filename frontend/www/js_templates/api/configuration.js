async function getConfiguration(workgroupId, vrfEpId, make, model, version) {
console.log(vrfEpId);

  let url = `[% path %]services/configuration.cgi?method=get&workgroup_id=${workgroupId}`;
  url += `&vrf_ep_id=${vrfEpId}&make=${make}&model=${model}&version=${version}`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    if ('error_text' in data) throw(data.error_text);
    return data.results[0];
  } catch(error) {
    console.log('Failure occurred in getConfiguration:', error);
    return '';
  }
}
