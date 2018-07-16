document.addEventListener('DOMContentLoaded', function() {
  let addEntitySubmit = document.querySelector('#add-entity-submit');
  addEntitySubmit.addEventListener('click', addEntitySubmitCallback);

  let addEntityCancel = document.querySelector('#add-entity-cancel');
  addEntityCancel.addEventListener('click', addEntityCancelCallback);

  let addInterfaceSubmit = document.querySelector('#add-endpoint-submit');
  addInterfaceSubmit.addEventListener('click', addInterfaceSubmitCallback);

  let addInterfaceCancel = document.querySelector('#add-endpoint-cancel');
  addInterfaceCancel.addEventListener('click', addInterfaceCancelCallback);
});

async function showEndpointSelectionModal(endpoint) {
    if (endpoint) {
        document.querySelector('#endpoint-select-header').innerHTML = 'Modify Network Endpoint';

        if ('entity_id' in endpoint && endpoint.entity_id !== -1) {
            $('#basic').tab('show');

            await loadEntities(endpoint.entity_id);
            await loadInterfaces();

            document.querySelector('#entity-index').value = endpoint.index;
            document.querySelector('#entity-id').value = endpoint.entity_id;
            document.querySelector('#entity-name').value = endpoint.name;

            document.querySelector('#entity-node').value = endpoint.node;
            document.querySelector('#entity-interface').value = endpoint.interface;

            loadEntityVLANs();
        } else {
            $('#advanced').tab('show');

            await loadEntities();
            await loadInterfaces();
            await loadInterfaceVLANs();
            console.log(`${endpoint.node} - ${endpoint.interface}`);
            console.log(`${endpoint.node} - ${endpoint.name}`);
            document.querySelector('#endpoint-select-interface').value = `${endpoint.node} - ${endpoint.interface}`;
            document.querySelector('#entity-index').value = endpoint.index;
            // #entity-index is shared between interfaces and entities
        }

        document.querySelector('#endpoint-vlans').value = endpoint.tag;
        document.querySelector('#entity-vlans').value = endpoint.tag;

        document.querySelector('#endpoint-bandwidth').value = endpoint.bandwidth;
        document.querySelector('#entity-bandwidth').value = endpoint.bandwidth;

        document.querySelector('#add-endpoint-submit').innerHTML = 'Modify Interface';
        document.querySelector('#add-entity-submit').innerHTML = 'Modify Entity';

        let addEntitySubmitButton = document.querySelector('#add-entity-submit');
        if ('entity_id' in endpoint) {
            addEntitySubmitButton.innerHTML = `Modify ${endpoint.name}`;
        }
        if ('entity_id' in endpoint && endpoint.interface !== '') {
            addEntitySubmitButton.innerHTML = `Modify ${endpoint.name} on ${endpoint.interface}`;
        }

    } else {
        document.querySelector('#endpoint-select-header').innerHTML = 'Add Network Endpoint';

        console.log('adding endpoint');

        loadEntities();
        loadEntityVLANs();

        await loadInterfaces();
        loadInterfaceVLANs();

        document.querySelector('#entity-index').value = -1;
    }

    let endpointSelectionModal = $('#add-endpoint-modal');
    endpointSelectionModal.modal('show');
}

async function showAndPrePopulateEndpointSelectionModal(entity_id) {
    await loadEntities(entity_id);
    loadEntityVLANs();

    document.querySelector('#entity-index').value = -1;
    document.querySelector('#entity-bandwidth').value = null;

    let endpointSelectionModal = $('#add-endpoint-modal');
    endpointSelectionModal.modal('show');
}


async function hideEndpointSelectionModal(index) {
    let endpointSelectionModal = $('#add-endpoint-modal');
    endpointSelectionModal.modal('hide');
}

async function loadEntities(parentEntity=null) {
    let entity = await getEntities(session.data.workgroup_id, parentEntity);

    let parent = null;
    if ('parents' in entity && entity.parents.length > 0) {
        parent = entity.parents[0];
    }

    let entities = '';
    let spacer = '';

    if (parent) {
        entities += `<button type="button" class="list-group-item active" onclick="loadEntities(${parent.entity_id})">
                       <span class="glyphicon glyphicon-menu-up"></span>&nbsp;&nbsp;
                       ${entity.name}
                     </button>`;
        spacer = '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;';
    }

    if ('children' in entity && entity.children.length > 0) {
        entity.children.forEach(function(child) {
                entities += `<button type="button" class="list-group-item" onclick="loadEntities(${child.entity_id})">
                               ${spacer}${child.name}
                               <span class="glyphicon glyphicon-menu-right" style="float: right;"></span>
                             </button>`;
        });
    }

    // Once the user has selected a leaf entity it's expected that we
    // Display all its associated ports.
    if ('children' in entity && entity.children.length === 0) {
        entity.interfaces.forEach(function(child) {
                entities += `<button type="button" class="list-group-item"
                                     onclick="setEntityEndpoint(${entity.entity_id}, '${entity.name}', '${child.node}', '${child.name}')">
                               ${spacer}<b>${child.node}</b> ${child.name}
                             </button>`;
        });
    }

    let entityList = document.querySelector('#entity-list');
    entityList.innerHTML = entities;

    setEntity(entity.entity_id, entity.name);
}

async function loadEntityVLANs() {
    let vlans = '';
    for (let i = 1; i < 4095; i++) {
        vlans += `<option>${i}</option>`;
    }
    document.querySelector('#entity-vlans').innerHTML = vlans;
}

async function addEntitySubmitCallback(event) {
    let name = document.querySelector('#entity-name').value;
    if (name === '') {
        document.querySelector('#entity-alert').style.display = 'block';
        return null;
    }

    if (!document.querySelector('#entity-bandwidth').validity.valid) {
        document.querySelector('#entity-bandwidth').reportValidity();
        return null;
    }

    let entity = {
        bandwidth: document.querySelector('#entity-bandwidth').value,
        interface: document.querySelector('#entity-interface').value,
        node: document.querySelector('#entity-node').value,
        peerings: [],
        tag: document.querySelector('#entity-vlans').value,
        entity_id: document.querySelector('#entity-id').value,
        name: document.querySelector('#entity-name').value
    };
    console.log(entity);

    let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
    let endpointIndex = document.querySelector('#entity-index').value;
    if (endpointIndex >= 0) {
        entity.peerings = endpoints[endpointIndex].peerings;
        endpoints[endpointIndex] = entity;
    } else {
        endpoints.push(entity);
    }

    sessionStorage.setItem('endpoints', JSON.stringify(endpoints));
    loadSelectedEndpointList();

    let entityAlert = document.querySelector('#entity-alert');
    entityAlert.innerHTML = '';
    entityAlert.style.display = 'none';
    let entityAlertOK = document.querySelector('#entity-alert-ok');
    entityAlertOK.innerHTML = '';
    entityAlertOK.style.display = 'none';

    let addEndpointModal = $('#add-endpoint-modal');
    addEndpointModal.modal('hide');
}

async function addEntityCancelCallback(event) {
    let entityAlert = document.querySelector('#entity-alert');
    entityAlert.innerHTML = '';
    entityAlert.style.display = 'none';
    let entityAlertOK = document.querySelector('#entity-alert-ok');
    entityAlertOK.innerHTML = '';
    entityAlertOK.style.display = 'none';

    let addEndpointModal = $('#add-endpoint-modal');
    addEndpointModal.modal('hide');
}



async function setEntity(id, name) {
   let entityID = document.querySelector('#entity-id');
   entityID.value = id;

   let entityName = document.querySelector('#entity-name');
   entityName.value = name;
}

async function setEntityEndpoint(id, name, node, intf) {
    document.querySelector('#entity-id').value = id;
    document.querySelector('#entity-name').value = name;
    document.querySelector('#entity-node').value = node;
    document.querySelector('#entity-interface').value = intf;
}



// --- Interfaces ---



async function loadInterfaces() {
    let interfaces = await getInterfacesByWorkgroup(session.data.workgroup_id);

    let options = '';
    interfaces.forEach(function(intf) {
            options += `<option data-id="${intf.interface_id}" data-node="${intf.node_name}" data-interface="${intf.interface_name}" value="${intf.node_name} - ${intf.interface_name}">
                          ${intf.node_name} - ${intf.interface_name}
                        </option>`;
    });
    document.querySelector('#endpoint-select-interface').innerHTML = options;

    loadInterfaceVLANs();
}

async function loadInterfaceVLANs() {
    let select = document.querySelector('#endpoint-select-interface');
    let node = select.options[select.selectedIndex].getAttribute('data-node');
    let intf = select.options[select.selectedIndex].getAttribute('data-interface');

    let vlans = '';
    for (let i = 1; i < 4095; i++) {
        vlans += `<option>${i}</option>`;
    }
    document.querySelector('#endpoint-vlans').innerHTML = vlans;
}

async function addInterfaceSubmitCallback(event) {
    let select = document.querySelector('#endpoint-select-interface');
    let node = select.options[select.selectedIndex].getAttribute('data-node');
    let intf = select.options[select.selectedIndex].getAttribute('data-interface');

    let endpoint = {
        bandwidth: document.querySelector('#endpoint-bandwidth').value,
        interface: intf,
        node: node,
        peerings: [],
        tag: document.querySelector('#endpoint-vlans').value
    };
    console.log(endpoint);

    let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
    let endpointIndex = document.querySelector('#entity-index').value;
    if (endpointIndex >= 0) {
        endpoint.peerings = endpoints[endpointIndex].peerings;
        endpoints[endpointIndex] = endpoint;
    } else {
        endpoints.push(endpoint);
    }

    sessionStorage.setItem('endpoints', JSON.stringify(endpoints));
    loadSelectedEndpointList();

    let addEndpointModal = $('#add-endpoint-modal');
    addEndpointModal.modal('hide');
}

async function addInterfaceCancelCallback(event) {
    let addEndpointModal = $('#add-endpoint-modal');
    addEndpointModal.modal('hide');
}
