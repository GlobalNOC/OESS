document.addEventListener('DOMContentLoaded', function() {
    let url = new URL(window.location.href);
    let action = url.searchParams.get('action');
    let entityID = url.searchParams.get('entity_id');
    loadUserMenu().then(function() {
        loadEntityContent(entityID, action);
        }
    );
});

async function loadEntityContent(parentEntity=null, action){
   
    let entity = await getEntities(session.data.workgroup_id, parentEntity);

    let entity_name	= document.querySelector('#entity-name');
    let description	= document.querySelector('#description');
    let logo_url	= document.querySelector('#logo-url');
    let entity_url	= document.querySelector('#entity-url');

    if (action == "add_entity"){
      document.querySelector('#add-entity-btn').onclick = function(){
      add_entity(entity.entity_id);
      };
    }

   if (action == "edit_entity"){
      entity_name.value	= entity.name;
      description.value	= entity.description;
      logo_url.value	= entity.logo_url;
      entity_url.value	= entity.url;
      document.querySelector('#edit-entity-btn').onclick = function(){
        edit_entity(entity.entity_id);
           };
    }
    document.querySelector('#cancel').onclick = function(){
        window.location.href = `[% path %]new/index.cgi?action=phonebook&entity_id=${entity.entity_id}`;
    } 

}

async function edit_entity(entityID){
    let url = `[% path %]services/entity.cgi?action=update_entity&entity_id=${entityID}`;

    await call_url(url);
    window.location.href = `[% path %]new/index.cgi?action=phonebook&entity_id=${entityID}`;

}

async function add_entity(entityID){
    let user = await getCurrentUser();
    let url = `[% path %]services/entity.cgi?action=add_child_entity&current_entity_id=${entityID}&user_id=${user.user_id}`;

    await call_url(url);
    window.location.href = `[% path %]new/index.cgi?action=phonebook&entity_id=${entityID}`;

}

async function call_url(url) {
    let entity_name     = document.querySelector('#entity-name');
    let description     = document.querySelector('#description');
    let logo_url        = document.querySelector('#logo-url');
    let entity_url      = document.querySelector('#entity-url');

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
