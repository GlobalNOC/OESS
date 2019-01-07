/**
 * getInterfaces returns a list of all interfaces on nodeName that may
 * be used for provisioning by workgroupID.
 *
 * @param {integer} workgroupID - Identifier of the current workgroup
 * @param {string} nodeName - Node used to filter interfaces
 * @param {integer} [trunk=1] - Include trunk interfaces
 */
async function getInterfaces(workgroupID, nodeName, trunk=1) {
  // Encode added to align with original source.
  nodeName = encodeURIComponent(nodeName);

  let url = `[% path %]services/data.cgi?method=get_node_interfaces&node=${nodeName}&workgroup_id=${workgroupID}&show_down=1&show_trunk=${trunk}`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    return data.results;
  } catch(error) {
    console.log('Failure occurred in getInterfaces.');
    console.log(error);
    return [];
  }
}

/**
 * getInterfacesByWorkgroup returns a list of all interfaces on the
 * network that may be used for provisioning by workgroupID.
 *
 * @param {integer} workgroupID - Identifier of the current workgroup
 * @param {integer} [trunk=1] - Include trunk interfaces
 */
async function getInterfacesByWorkgroup(workgroupID, trunk=1) {
    let url = `[% path %]services/interface.cgi?method=get_workgroup_interfaces&workgroup_id=${workgroupID}`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    return data.results;
  } catch(error) {
    console.log('Failure occurred in getInterfacesByWorkgroup.');
    console.log(error);
    return [];
  }
}

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
