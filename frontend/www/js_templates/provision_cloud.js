
document.addEventListener('DOMContentLoaded', function() {
  sessionStorage.setItem('endpoints', '[]');

  loadUserMenu().then(function() {
      setDateTimeVisibility();
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

  let url = new URL(window.location.href);
  let id = url.searchParams.get('prepop_vrf_id');
  if (id) {
      loadEntityList(id);
      let entityVLANs = '';
      for (let i = 1; i < 4095; i++) {
          entityVLANs += `<option>${i}</option>`;
      }
      document.querySelector('#entity-vlans').innerHTML = entityVLANs;

      document.querySelector('#entity-index').value = -1;
      document.querySelector('#entity-bandwidth').value = null;

      let addEndpointModal = $('#add-endpoint-modal');
      addEndpointModal.modal('show');
  }
});

async function loadMyInterfaces() {
    let interfaces = await getInterfacesByWorkgroup(session.data.workgroup_id);

    let options = '';
    interfaces.forEach(function(intf) {
            options += `<option data-node="${intf.node_name}" data-interface="${intf.interface_name}" value="${intf.node_name} - ${intf.interface_name}">${intf.node_name} - ${intf.interface_name}</option>`;
    });
    document.querySelector('#endpoint-select-interface').innerHTML = options;

    let endpointVLANs = '';
    for (let i = 1; i < 4095; i++) {
        endpointVLANs += `<option>${i}</option>`;
    }
    document.querySelector('#endpoint-vlans').innerHTML = endpointVLANs;
}

async function addNetworkEndpointCallback(event) {
    loadMyInterfaces();

    await loadEntityList();

    let entityVLANs = '';
    for (let i = 1; i < 4095; i++) {
        entityVLANs += `<option>${i}</option>`;
    }
    document.querySelector('#entity-vlans').innerHTML = entityVLANs;
    document.querySelector('#endpoint-vlans').innerHTML = entityVLANs;

    document.querySelector('#entity-index').value = -1;
    document.querySelector('#endpoint-index').value = -1;

    document.querySelector('#entity-bandwidth').value = null;
    document.querySelector('#endpoint-bandwidth').value = null;

    document.querySelector('#add-entity-submit').innerHTML = 'Add Endpoint';
    document.querySelector('#add-endpoint-submit').innerHTML = 'Add Endpoint';

    document.querySelector('#entity-interface').value = null;
    document.querySelector('#entity-node').value = null;

    let addEndpointModal = $('#add-endpoint-modal');
    addEndpointModal.modal('show');
}

async function modifyNetworkEndpointCallback(index) {
    let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));

    await loadEntityList();

    let vlans = '';
    for (let i = 1; i < 4095; i++) {
        vlans += `<option>${i}</option>`;
    }
    document.querySelector('#endpoint-vlans').innerHTML = vlans;
    document.querySelector('#entity-vlans').innerHTML = vlans;

    document.querySelector('#entity-node').value = null;
    document.querySelector('#entity-interface').value = null;

    if ('entity_id' in endpoints[index] && endpoints[index].entity_id != -1) {
        await loadEntityList(endpoints[index].entity_id);

        document.querySelector('#entity-index').value = index;
        document.querySelector('#entity-id').value = endpoints[index].entity_id;
        document.querySelector('#entity-name').value = endpoints[index].name;

        document.querySelector('#entity-node').value = endpoints[index].node;
        document.querySelector('#entity-interface').value = endpoints[index].interface;

        $('#basic').tab('show');
    } else {
        document.querySelector('#endpoint-select-interface').value = `${endpoints[index].node} - ${endpoints[index].interface}`;

        document.querySelector('#endpoint-index').value = index;
        $('#advanced').tab('show');
    }

    document.querySelector('#endpoint-vlans').value = endpoints[index].tag;
    document.querySelector('#entity-vlans').value = endpoints[index].tag;

    document.querySelector('#endpoint-bandwidth').value = endpoints[index].bandwidth;
    document.querySelector('#entity-bandwidth').value = endpoints[index].bandwidth;

    document.querySelector('#add-endpoint-submit').innerHTML = 'Modify Endpoint';
    document.querySelector('#add-entity-submit').innerHTML = 'Modify Endpoint';

    let addEntitySubmitButton = document.querySelector('#add-entity-submit');
    if ('entity_id' in endpoints[index]) {
        addEntitySubmitButton.innerHTML = `Modify ${endpoints[index].name}`;
    }
    if ('entity_id' in endpoints[index] && endpoints[index].interface !== '') {
        addEntitySubmitButton.innerHTML = `Modify ${endpoints[index].name} on ${endpoints[index].interface}`;
    }

    let addEndpointModal = $('#add-endpoint-modal');
    addEndpointModal.modal('show');
}

async function deleteNetworkEndpointCallback(index) {
    let entity = document.querySelector(`#enity-${index}`);

    let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
    endpoints.splice(index, 1);
    sessionStorage.setItem('endpoints', JSON.stringify(endpoints));

    loadSelectedEndpointList();
}

async function addNetworkSubmitCallback(event) {
    if (!document.querySelector('#description').validity.valid) {
        document.querySelector('#description').reportValidity();
        return null;
    }

    let provisionTime = -1;
    if (document.querySelector('input[name=provision-time]:checked').value === 'later') {
        let date = new Date(document.querySelector('#provision-time-picker').value);
        provisionTime = date.getTime();
    }

    let removeTime = -1;
    if (document.querySelector('input[name=remove-time]:checked').value === 'later') {
        let date = new Date(document.querySelector('#remove-time-picker').value);
        removeTime = date.getTime();
    }

    let addNetworkLoadingModal = $('#add-network-loading');
    addNetworkLoadingModal.modal('show');

    let vrfID = await provisionVRF(
        session.data.workgroup_id,
        document.querySelector('#description').value,
        document.querySelector('#description').value,
        JSON.parse(sessionStorage.getItem('endpoints')),
        provisionTime,
        removeTime,
        -1
    );

    if (vrfID === null) {
        addNetworkLoadingModal.modal('hide');
        alert('Failed to provision VRF. Please try again later.');
    } else {
        window.location.href = `index.cgi?action=view_l3vpn&vrf_id=${vrfID}`;
    }
}

async function addNetworkCancelCallback(event) {
    window.location.href = 'index.cgi?action=index';
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
        entity_id: document.querySelector('#entity-id').value,
        name: document.querySelector('#entity-name').value,
        peerings: [],
        tag: document.querySelector('#entity-vlans').value
    };

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

    let entityAlertOK = document.querySelector('#entity-alert-ok');
    entityAlertOK.style.display = 'none';

    let addEndpointModal = $('#add-endpoint-modal');
    addEndpointModal.modal('hide');
}

async function addEntityCancelCallback(event) {
    let entityAlertOK = document.querySelector('#entity-alert-ok');
    entityAlertOK.style.display = 'none';

    let addEndpointModal = $('#add-endpoint-modal');
    addEndpointModal.modal('hide');
}

async function addEndpointSubmitCallback(event) {
    let intf = document.querySelector('#endpoint-select-interface');
    let node = intf.options[intf.selectedIndex].getAttribute('data-node');
    let intfName = intf.options[intf.selectedIndex].getAttribute('data-interface');

    let endpoint = {
        bandwidth: document.querySelector('#endpoint-bandwidth').value,
        interface: intfName,
        node: node,
        peerings: [],
        tag: document.querySelector('#endpoint-vlans').value
    };

    let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
    let endpointIndex = document.querySelector('#endpoint-index').value;
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

async function addEndpointCancelCallback(event) {
    let addEndpointModal = $('#add-endpoint-modal');
    addEndpointModal.modal('hide');
}

//--- Add Endpoint Modal

async function loadEntityList(parentEntity=null) {
    let entity = await getEntities(session.data.workgroup_id, parentEntity);
    let entityList = document.querySelector('#entity-list');
    entityList.innerHTML = '';

    let logoURL = entity.logo_url || 'https://shop.lego.com/static/images/svg/lego-logo.svg';
    let description = entity.description;
    let name = entity.name;
    let entityID = entity.entity_id;

    let parent = null;
    if ('parents' in entity && entity.parents.length > 0) {
        parent = entity.parents[0];
    }

    let entities = '';
    let childSpacer = '';

    if (parent !== null) {
        entities += `<button type="button" class="list-group-item active" onclick="loadEntityList(${parent.entity_id})">
                       <span class="glyphicon glyphicon-menu-up"></span>&nbsp;&nbsp;
                       ${name}
                     </button>`;
        childSpacer = '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;';
    }

    if ('children' in entity && entity.children.length > 0) {
        entity.children.forEach(function(child) {
                entities += `<button type="button" class="list-group-item" onclick="loadEntityList(${child.entity_id})">
                               ${childSpacer}${child.name}
                               <span class="glyphicon glyphicon-menu-right" style="float: right;"></span>
                             </button>`;
        });
        entityList.innerHTML += entities;
    }

    if ('children' in entity && entity.children.length === 0 && entity.interfaces.length > 0) {
        entity.interfaces.forEach(function(child) {
                entities += `<button type="button" class="list-group-item"
                                     onclick="setEntityEndpoint(${entityID}, '${name}', '${child.node}', '${child.name}')">
                               ${childSpacer}<b>${child.node}</b> ${child.name}
                             </button>`;
        });
        entityList.innerHTML += entities;
    }

    setEntity(entityID, name);
}

async function setEntity(id, name) {
    console.log(id);
   let entityID = document.querySelector('#entity-id');
   entityID.value = id;

   let entityName = document.querySelector('#entity-name');
   entityName.value = name;

   let addEntitySubmitButton = document.querySelector('#add-entity-submit');
   addEntitySubmitButton.innerHTML = `Add ${name}`;
}

async function setEntityEndpoint(id, name, node, intf) {
    document.querySelector('#entity-id').value = id;
    document.querySelector('#entity-name').value = name;
    document.querySelector('#entity-node').value = node;
    document.querySelector('#entity-interface').value = intf;

   let addEntitySubmitButton = document.querySelector('#add-entity-submit');
   addEntitySubmitButton.innerHTML = `Add ${name} on ${intf}`;

}

//--- Main - Schedule ---

function setDateTimeVisibility() {
  let type = document.querySelector('input[name=provision-time]:checked').value;
  let pick = document.getElementById('provision-time-picker');

  if (type === 'later') {
    pick.style.display = 'block';
  } else {
    pick.style.display = 'none';
  }

  type = document.querySelector('input[name=remove-time]:checked').value;
  pick = document.getElementById('remove-time-picker');

  if (type === 'later') {
    pick.style.display = 'block';
  } else {
    pick.style.display = 'none';
  }
}

//--- Main - Endpoint ---

function setIPv4ValidationMessage(input) {
    input.addEventListener('input', function(e) {
        if (input.validity.valueMissing) {
            input.setCustomValidity('Please fill out this field.');
        } else if (input.validity.patternMismatch) {
            input.setCustomValidity('Please input a valid IPv4 subnet in CIDR notation.');
        } else {
            input.setCustomValidity('');
        }
    }, false);
}

function newPeering(index) {
    let asn = document.querySelector(`#new-peering-form-${index} .bgp-asn`);
    if (!asn.validity.valid) {
        asn.reportValidity();
        return null;
    }
    let yourPeerIP = document.querySelector(`#new-peering-form-${index} .your-peer-ip`);
    if (!yourPeerIP.validity.valid) {
        yourPeerIP.reportValidity();
        return null;
    }
    let key = document.querySelector(`#new-peering-form-${index} .bgp-key`);
    if (!key.validity.valid) {
        key.reportValidity();
        return null;
    }
    let oessPeerIP = document.querySelector(`#new-peering-form-${index} .oess-peer-ip`);
    if (!oessPeerIP.validity.valid) {
        oessPeerIP.reportValidity();
        return null;
    }

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
          if ('entity_id' in endpoint) {
              if (endpoint.interface === '') {
                  endpointName = `${endpoint.name} <small>${endpoint.tag}</small>`;
              } else {
                  endpointName = `${endpoint.name} <small>${endpoint.interface} ${endpoint.tag}</small>`;
              }
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
<div id="entity-${index}" class="panel panel-default">
  <div class="panel-heading">
    <h4 style="margin: 0px">
      ${endpointName}
      <span style="float: right; margin-top: -5px;">
        <button class="btn btn-link" type="button" onclick="modifyNetworkEndpointCallback(${index})"><span class="glyphicon glyphicon-edit"></span></button>
        <button class="btn btn-link" type="button" onclick="deleteNetworkEndpointCallback(${index})"><span class="glyphicon glyphicon-trash"></span></button>
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
            <td><input class="form-control bgp-asn" type="number" required /></td>
            <td><input class="form-control your-peer-ip" type="text" required /></td>
            <td><input class="form-control bgp-key" type="text" /></td>
            <td><input class="form-control oess-peer-ip" type="text" required /></td>
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

  endpoints.forEach(function(endpoint, index) {
          let yourPeerIP = document.querySelector(`#new-peering-form-${index} .your-peer-ip`);
          asIPv4CIDRorIPv6CIDR(yourPeerIP);

          let oessPeerIP = document.querySelector(`#new-peering-form-${index} .oess-peer-ip`);
          asIPv4CIDRorIPv6CIDR(oessPeerIP);
  });
}
