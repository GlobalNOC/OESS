
document.addEventListener('DOMContentLoaded', function() {
  sessionStorage.setItem('endpoints', '[]');

  let map = L.map('map').setView([51.505, -0.09], 6);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png').addTo(map);
  L.marker([51.5, -0.09]).addTo(map);

  // Map size isn't known until after the tab has been selected.
  $('#advanced-tab').on('show.bs.tab', function(){
    setTimeout(function() { map.invalidateSize(); }, 1);
  });

  let addNetworkEndpoint = document.querySelector('#add-network-endpoint');
  addNetworkEndpoint.addEventListener('click', addNetworkEndpointCallback);

  let addNetworkSubmit = document.querySelector('#add-network-submit');
  addNetworkSubmit.addEventListener('click', addNetworkSubmitCallback);

  let addNetworkCancel = document.querySelector('#add-network-cancel');
  addNetworkCancel.addEventListener('click', addNetworkCancelCallback);

  let addEntitySubmit = document.querySelector('#add-entity-submit');
  addEntitySubmit.addEventListener('click', addEntitySubmitCallback);

  let addEntityCancel = document.querySelector('#add-entity-cancel');
  addEntityCancel.addEventListener('click', addEntityCancelCallback);

  let addEndpointSubmit = document.querySelector('#add-endpoint-submit');
  addEndpointSubmit.addEventListener('click', addEndpointSubmitCallback);

  let addEndpointCancel = document.querySelector('#add-endpoint-cancel');
  addEndpointCancel.addEventListener('click', addEndpointCancelCallback);
});

async function addNetworkEndpointCallback(event) {
    await loadEntityList();

    let entityVLANs = '';
    for (let i = 1; i < 4095; i++) {
        entityVLANs += `<option>${i}</option>`;
    }
    document.querySelector('#entity-vlans').innerHTML = entityVLANs;

    document.querySelector('#entity-bandwidth').value = null;

    let addEndpointModal = $('#add-endpoint-modal');
    addEndpointModal.modal('show');
}

async function addNetworkSubmitCallback(event) {
    // TODO
    console.log('addNetworkSubmitCallback not complete.');
}

async function addNetworkCancelCallback(event) {
    window.location.href = 'index.cgi?action=index';
}

async function addEntitySubmitCallback(event) {
    let entity = {
        bandwidth: document.querySelector('#entity-bandwidth').value,
        entity_id: document.querySelector('#entity-id').value,
        name: document.querySelector('#entity-name').value,
        peerings: [],
        tag: document.querySelector('#entity-vlans').value
    };

    let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
    endpoints.push(entity);
    sessionStorage.setItem('endpoints', JSON.stringify(endpoints));

    loadSelectedEndpointList();

    let addEndpointModal = $('#add-endpoint-modal');
    addEndpointModal.modal('hide');
}

async function addEntityCancelCallback(event) {
    let addEndpointModal = $('#add-endpoint-modal');
    addEndpointModal.modal('hide');
}

async function addEndpointSubmitCallback(event) {
    // TODO
    console.log('addEndpointSubmitCallback not complete.');

    loadSelectedEndpointList();

    let addEndpointModal = $('#add-endpoint-modal');
    addEndpointModal.modal('hide');
}

async function addEndpointCancelCallback(event) {
    let addEndpointModal = $('#add-endpoint-modal');
    addEndpointModal.modal('hide');
}

//--- Add Endpoint - Entity Tab ---

async function loadEntityList(parentEntity=null) {
    let entities = await getEntities(session.data.workgroup_id, parentEntity);
    let entitiesList = document.querySelector('#entities-list');

    entitiesList.innerHTML = '';
    if (parentEntity !== null) {
        entitiesList.innerHTML += `<button type="button" class="list-group-item" onclick="loadEntityList()">
                                     <span class="glyphicon glyphicon-menu-left" style="float: right;"></span>
                                   </button>`;
    }

    entities.forEach(function(entity) {
            if (entity.children.length > 0) {
                entitiesList.innerHTML += `<button type="button" class="list-group-item" onclick="loadEntityList(${entity.entity_id})">
                                             ${entity.name}
                                             <span class="glyphicon glyphicon-menu-right" style="float: right;"></span>
                                           </button>`;
            } else {
                entitiesList.innerHTML += `<button type="button" class="list-group-item" onclick="setEntity(${entity.entity_id}, '${entity.name}')">${entity.name}</button>`;
            }
    });
}

async function setEntity(id, name) {
    console.log(id);
   let entityID = document.querySelector('#entity-id');
   entityID.value = id;

   let entityName = document.querySelector('#entity-name');
   entityName.value = name;
}

//--- Add Endpoint - Endpoint Tab ---

//--- Main - Endpoint ---

function newPeering(index) {
    let asn = document.querySelector(`#new-peering-form-${index} .bgp-asn`);
    let key = document.querySelector(`#new-peering-form-${index} .bgp-key`);
    let oessPeerIP = document.querySelector(`#new-peering-form-${index} .oess-peer-ip`);
    let yourPeerIP = document.querySelector(`#new-peering-form-${index} .your-peer-ip`);

    let peering = {
        asn: asn.value,
        key: key.value,
        oessPeerIP: oessPeerIP.value,
        yourPeerIP: yourPeerIP.value
    };

    let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
    endpoints[index].peerings.push(peering);
    sessionStorage.setItem('endpoints', JSON.stringify(endpoints));

    // Redraw endpoints
    loadSelectedEndpointList();
}

function deletePeering(endpointIndex, peeringIndex) {
    let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
    endpoints[endpointIndex].peerings.splice(peeringIndex, 1);
    sessionStorage.setItem('endpoints', JSON.stringify(endpoints));

    // Redraw endpoints
    loadSelectedEndpointList();
}

//--- Main ---

function loadSelectedEndpointList() {
  let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
  let selectedEndpointList = '';

  console.log(endpoints);
  endpoints.forEach(function(endpoint, index) {
          let endpointName = '';
          if (typeof endpoint.entity_id !== undefined) {
              endpointName = `${endpoint.name} <small>${endpoint.tag}</small>`;
          } else {
              endpointName = `${endpoint.node} <small>${endpoint.interface} - ${endpoint.tag}</small>`;
          }

          let peerings = '';
          endpoint.peerings.forEach(function(peering, peeringIndex) {
                  peerings += `
<tr>
  <td>${peering.asn}</td>
  <td>${peering.yourPeerIP}</td>
  <td>${peering.key}</td>
  <td>${peering.oessPeerIP}</td>
  <td><button class="btn btn-danger btn-sm" class="form-control" type="button" onclick="deletePeering(${index}, ${peeringIndex})">&nbsp;<span class="glyphicon glyphicon-trash"></span>&nbsp;</button></td>
</tr>
`;
          });

          let html = `
<div class="panel panel-default">
  <div class="panel-heading">
    <h4 style="margin: 0px">
      ${endpointName}
      <span style="float: right;">
        <span class="glyphicon glyphicon-edit"   onclick=""></span>
        <span class="glyphicon glyphicon-remove" onclick=""></span>
      </span>
    </h4>
  </div>

  <div class="table-responsive">
    <div id="endpoints">
      <table class="table">
        <thead><tr><th>Your ASN</th><th>Your IP</th><th>Your BGP Key</th><th>OESS IP</th><th></th></tr></thead>
        <tbody>
          ${peerings}
          <tr id="new-peering-form-${index}">
            <td><input class="form-control bgp-asn" type="text" /></td>
            <td><input class="form-control your-peer-ip" type="text" /></td>
            <td><input class="form-control bgp-key" type="text" /></td>
            <td><input class="form-control oess-peer-ip" type="text" /></td>
            <td><button class="btn btn-success btn-sm" class="form-control" type="button" onclick="newPeering(${index})">&nbsp;<span class="glyphicon glyphicon-plus"></span>&nbsp;</button></td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</div>
`;

          selectedEndpointList += html;
  });

  document.getElementById('selected-endpoint-list').innerHTML = selectedEndpointList;
}
