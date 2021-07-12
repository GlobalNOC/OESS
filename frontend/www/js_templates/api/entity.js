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

/**
 * edit_entity changes the given parameters of an entity in the database 
 *
 * @param {integer} entityID - Identifier of the current entity
 * @param {string} entity_name - Entity name to change
 * @param {string} description - Description of the given entity that needs to be edited
 * @param {string} logo_url - URL for the logo that needs to be edited
 * @param {string} entity_url - URL for the given entity that needs to be edited
 */
async function edit_entity(entityID, entity_name, description, logo_url, entity_url){

    let url = `[% path %]services/entity.cgi?method=update_entity&entity_id=${entityID}`;
    if (entity_name.value)
    {
        url += `&name=${entity_name.value}`;
    }
    if (description.value)
    {
        url += `&description=${description.value}`;
    }
    if (logo_url.value)
    {
        url += `&logo_url=${logo_url.value}`;
    }
    if (entity_url.value)
    {
        url += `&url=${entity_url.value}` ;
    }
    
    try {
      const resp = await fetch(url, {method: 'get', credentials: 'include'});
      const data = await resp.json();
      console.log(data);
      return data.results[0];
    }catch(error) {
      console.log('Failure occurred in deleteVRF.');
      console.log(error);
      return null;
    }
}

/**
 * add_entity makes a new entity using given parameters and adds it as a child entity to database. Returns entity-id for child on success.
 *
 * @param {integer} entityID - Identifier of the parent current entity
 * @param {string} entity_name - Name of the new child entity
 * @param {string} description - Description for the new child entity
 * @param {string} logo_url - Logo URL for the new child entity
 * @param {string} entity_url - URL for the new child entity
 */
async function add_entity(entityID, entity_name, desctiption, logo_url, entity_url){

    let user = await getCurrentUser();
    let url = `[% path %]services/entity.cgi?method=add_child_entity&current_entity_id=${entityID}&user_id=${user.user_id}`;
    if (entity_name.value)
    {
        url += `&name=${entity_name.value}`;
    }
    if (description.value)
    {
        url += `&description=${description.value}`;
    }
    if (logo_url.value)
    {
        url += `&logo_url=${logo_url.value}`;
    }
    if (entity_url.value)
    {
        url += `&url=${entity_url.value}` ;
    }

    try {
      const resp = await fetch(url, {method: 'get', credentials: 'include'});
      const data = await resp.json();
      if ('error' in data) throw data.error_text;
      return data.results[0];
    } catch(error) {
      console.error('Failure occurred in add_entity:', error);
      return null;
    }    
}

/**
 * add_user will add user to the current entity. Returns success on success.
 *
 * @params {integer} user_id - Identifier of the user to add
 * @params {integer} entityID - Identifier of the currnt entity
 */
async function add_user(user_id, entityID){
    const url = `[% path %]services/entity.cgi?method=add_user&entity_id=${entityID}&user_id=${user_id}`;
    try {
      const resp = await fetch(url, {method: 'get', credentials: 'include'});
      const data = await resp.json();
      if ('error' in data) throw data.error_text;
      return data.results[0];
    } catch(error) {
      console.error('Failure occurred in add_user:', error);
      return null;
    }
 }

/**
 * remove_user removes an existing user that has access to entity
 *
 * @params {integer} user_id - Identifier of the user to remove
 * @params {integer} entityID - Identifier of the currnt entity
 */
async function remove_user(user_id, entityID){
    console.log("remove user");
    const url = `[% path %]services/entity.cgi?method=remove_user&entity_id=${entityID}&user_id=${user_id}`;
    try {
      const resp = await fetch(url, {method: 'get', credentials: 'include'});
      const data = await resp.json();
      if ('error' in data) throw data.error_text;
      return data.results[0];
    } catch(error) {
      console.error('Failure occurred in remove_user:', error);
      return null;
    }
}



