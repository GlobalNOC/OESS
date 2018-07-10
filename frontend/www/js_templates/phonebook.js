document.addEventListener('DOMContentLoaded', function() {
  let url = new URL(window.location.href);
  let entityID = url.searchParams.get('entity_id');

  loadUserMenu().then(function() {
      loadEntityList(entityID);
  });
});

async function loadEntityList(parentEntity=null) {
    let entity = await getEntities(session.data.workgroup_id, parentEntity);
    let entitiesList = document.querySelector('#entity-list');

    let logoURL = entity.logo_url || 'https://shop.lego.com/static/images/svg/lego-logo.svg';
    let description = entity.description;
    let name = entity.name;
    let entityID = entity.entity_id;

    let parent = null;
    if ('parents' in entity && entity.parents.length > 0) {
        parent = entity.parents[0];
    }

    let logo = document.querySelector('.entity-logo');
    logo.setAttribute('src', logoURL);

    let entityName = document.querySelector('#entity-name');
    if (parent !== null) {
        entityName.innerHTML = `${name} <small>of <a href="#" onclick="loadEntityList(${parent.entity_id})">${parent.name}</a></small>`;
    } else {
        entityName.innerHTML = name;
    }

    let entityConnect = document.querySelector('#entity-connect');
    if (parent !== null) {
        entityConnect.style.display = 'block';
        entityConnect.innerHTML = `Create new connection to ${name}`;
        entityConnect.addEventListener('click', function() {
                window.location.href = `?action=provision_cloud&prepop_vrf_id=${entityID}`;
            }, false);
    } else {
        entityConnect.style.display = 'none';
    }

    let entityDescription = document.querySelector('#entity-description');
    entityDescription.innerHTML = description;

    let entityNav = '';
    if (parent !== null) {
        entityNav += `<li role="presentation" onclick="loadEntityList(${parent.entity_id})"><a href="#">&lt; ${parent.name}</a></li>`;
    }

    entity.children.forEach(function(entity) {
            let childLi  = `<li role="presentation" onclick="loadEntityList(${entity.entity_id})"><a href="#">${entity.name} &gt;</a></li>`;
            entityNav += childLi;
    });
    entitiesList.innerHTML = entityNav;

    if (entity.interfaces.length < 1) {
        document.querySelector('#entity-interfaces-title').style.display = 'none';
    } else {
        document.querySelector('#entity-interfaces-title').style.display = 'block';
    }

    let entityInterfaces = '';
    entity.interfaces.forEach(function(intf) {
            if (intf.operational_state === 'up') {
                entityInterfaces += `<p class="entity-interface"><span class="label label-success">▴</span> <b>${intf.node}</b><br/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;${intf.name}</p>`;
            } else {
                entityInterfaces += `<p class="entity-interface"><span class="label label-danger">▾</span> <b>${intf.node}</b><br/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;${intf.name}</p>`;
            }
    });
    document.querySelector('#entity-interfaces').innerHTML = entityInterfaces;

    if (entity.contacts.length < 1) {
        document.querySelector('#entity-contacts-title').style.display = 'none';
    } else {
        document.querySelector('#entity-contacts-title').style.display = 'block';
    }

    let entityContacts = '';
    entity.contacts.forEach(function(contact) {
            entityContacts += `<p class="entity-contact"><b>${contact.first_name} ${contact.last_name}</b><br/>${contact.email}</p>`;
    });
    document.querySelector('#entity-contacts').innerHTML = entityContacts;
}
