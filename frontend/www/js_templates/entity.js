document.addEventListener('DOMContentLoaded', function() {
  let url = new URL(window.location.href);
  let action = url.searchParams.get('action');
  let entityID = url.searchParams.get('entity_id');
  loadUserMenu().then(function() {
    loadEntityContent(entityID, action);
  });
});

async function loadEntityContent(parentEntity=null, action){
  let entity = await getEntities(session.data.workgroup_id, parentEntity);
  let entityID = entity.entity_id;

  let entity_name = document.querySelector('#entity-name');
  let description = document.querySelector('#description');
  let logo_url = document.querySelector('#logo-url');
  let entity_url =  document.querySelector('#entity-url');

  if (action == "add_entity"){
    document.querySelector('#add-entity-btn').onclick = async function(e) {
      e.preventDefault();
      try {
        let res = await add_entity(entityID, entity_name, description, logo_url, entity_url);
        window.location.href = `[% path %]index.cgi?action=phonebook&entity_id=${entityID}`;
      }
      catch (error) {
        console.error(error);
      }
      return false;
    };
  }

  if (action == "edit_entity"){
    entity_name.value	= entity.name;
    description.value	= entity.description;
    logo_url.value	= entity.logo_url;
    entity_url.value	= entity.url;
    document.querySelector('#edit-entity-btn').onclick = async function(){
      await edit_entity(entityID, entity_name, description, logo_url, entity_url);
      window.location.href = `[% path %]index.cgi?action=phonebook&entity_id=${entityID}`;
    };
  }

  document.querySelector('#cancel').onclick = function(){
    window.location.href = `[% path %]index.cgi?action=phonebook&entity_id=${entityID}`;
  };
}
