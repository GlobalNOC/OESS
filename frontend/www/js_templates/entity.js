document.addEventListener('DOMContentLoaded', function() {
    let url = new URL(window.location.href);
    let entityID = url.searchParams.get('entity_id');
    console.log("Debug 2");
    console.log(entityID);
    loadUserMenu().then(function() {
        loadEntityContent(entityID);
        }
    );
});

async function loadEntityContent(parentEntity=null){
   
    let entity = await getEntities(session.data.workgroup_id, parentEntity);
    console.log("entity");
    console.log(entity);

    let entity_name	= document.querySelector('#entity-name');
    let description	= document.querySelector('#description');
    let logo_url	= document.querySelector('#logo-url');
    let entity_url	= document.querySelector('#entity-url');
    entity_name.value	= entity.name;
    description.value	= entity.description;
    logo_url.value	= entity.logo_url;
    entity_url.value	= entity.url;

    document.querySelector('#edit-entity-btn').onclick = function(){
	edit_entity(entity.entity_id);
    };

    document.querySelector('#cancel-edit-entity').onclick = function(){
        window.location.href = `[% path %]new/index.cgi?action=phonebook&entity_id=${entity.entity_id}`;
    } 

}

async function edit_entity(entityID){
    let entity_name     = document.querySelector('#entity-name');
    let description     = document.querySelector('#description');
    let logo_url        = document.querySelector('#logo-url');
    let entity_url      = document.querySelector('#entity-url');

    let url = `[% path %]services/entity.cgi?action=update_entity&entity_id=${entityID}`;
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
    
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    console.log(resp);
    window.location.href = `[% path %]new/index.cgi?action=phonebook&entity_id=${entityID}`;

}
