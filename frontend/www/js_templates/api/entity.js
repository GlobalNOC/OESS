/**
 *
 */
async function getEntities(workgroupID, parentEntityID=null, options) {
  let url = `[% path %]services/entity.cgi?method=get_entity&workgroup_id=${workgroupID}&entity_id=1`;
  if (parentEntityID !== null) {
    url = `[% path %]services/entity.cgi?method=get_entity&workgroup_id=${workgroupID}&entity_id=${parentEntityID}`;
  }
  if(options !== undefined){
    if(options.vrf != null){
      url += "&vrf_id=" + options.vrf.vrf_id;
    }

    if(options.circuit_id != null){
      url += "&circuit_id=" + options.circuit.circuit_id;
    }
  }

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    return data.results;
  } catch(error) {
    console.log('Failure occurred in getEntities.');
    console.log(error);
    return [];
  }
}

/**
 * getEntitiesAll returns a list of entities filtered by queryString.
 *
 * @param {integer} workgroupID - Identifier of the current workgroup
 * @param {string} queryString - Entity name to filter results by
 */
async function getEntitiesAll(workgroupID, queryString=null) {
  let url = `[% path %]services/entity.cgi?method=get_entities&workgroup_id=${workgroupID}`;
  url += (queryString != null ? `&name=${queryString}` : '');

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    return data.results;
  } catch(error) {
    console.log('Failure occurred in getEntities.');
    console.log(error);
    return [];
  }
}
