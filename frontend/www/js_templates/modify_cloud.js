/**
 * render calls obj.render(props) to generate an HTML string. Once
 * generated, the HTML string is assigned to elem.innerHTML.
 */
async function render(obj, elem, props) {
  elem.innerHTML = await obj.render(props);
}


let m = undefined;


async function load() {
  let interfaces = await getInterfacesByWorkgroup(session.data.workgroup_id);
  let interface = null;

  let vlans = [];
  if (interfaces.length > 0) {
    interface = interfaces[0];
    vlans = await getAvailableVLANs(session.data.workgroup_id, interface.interface_id);
  }
  let vlan = (vlans.length > 0) ? vlans[0] : null;

  m = new EndpointSelectionModal({
    interface: interface,
    vlan: vlan
  });
  update();
}

async function update(props) {
  render(m, document.querySelector('#add-endpoint-modal'), props);
}

document.addEventListener('DOMContentLoaded', function() {
  sessionStorage.setItem('endpoints', '[]');

  load();

  loadUserMenu().then(function() {
    loadVRF();
    setDateTimeVisibility();
  });

  let addNetworkEndpoint = document.querySelector('#add-network-endpoint');
  addNetworkEndpoint.addEventListener('click', addNetworkEndpointCallback);

  let addNetworkSubmit = document.querySelector('#add-network-submit');
  addNetworkSubmit.addEventListener('click', addNetworkSubmitCallback);

  let addNetworkCancel = document.querySelector('#add-network-cancel');
  addNetworkCancel.addEventListener('click', addNetworkCancelCallback);

  let url = new URL(window.location.href);
  let id = url.searchParams.get('prepop_vrf_id');
  if (id) {
      showAndPrePopulateEndpointSelectionModal(id);
  }
});

async function loadVRF() {
  let url = new URL(window.location.href);
  let id = url.searchParams.get('vrf_id');
  let vrf = await getVRF(id);
  console.log(vrf);

  let description = document.querySelector('#description');
  description.value = vrf.description;

  let endpoints = [];

  vrf.endpoints.forEach(function(e) {
    let entity_id = null;
    let entity_name = null;
    if (e.hasOwnProperty('entity')) {
      entity_id = e.entity.entity_id;
      entity_name = e.entity.name;
    }

    let endpoint = {
        cloud_account_id: e.cloud_account_id,
        cloud_account_type: e.interface.cloud_interconnect_type,
        bandwidth: e.bandwidth,
        entity_id: entity_id,
        entity: entity_name,
        interface_id: e.interface.interface_id,
        name: e.interface.name,
        node: e.node.name,
        peerings: [],
        tag: e.tag,
        interface: e.interface.name
    };

    e.peers.forEach(function(p) {
      let peering = {
          ipVersion: p.ip_version,
          asn: p.peer_asn,
          key: p.md5_key || '',
          oessPeerIP: p.local_ip,
          yourPeerIP: p.peer_ip
      };
      endpoint.peerings.push(peering);
    });

    endpoints.push(endpoint);
  });

  sessionStorage.setItem('endpoints', JSON.stringify(endpoints));
  sessionStorage.setItem('vrf',JSON.stringify(vrf));
  loadSelectedEndpointList();
}

async function addNetworkEndpointCallback(event) {
  m.setIndex(-1);
  update();

  let endpointSelectionModal = $('#add-endpoint-modal');
  endpointSelectionModal.modal('show');
}

async function modifyNetworkEndpointCallback(index) {
  let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
  endpoints[index].index = index;

  m.setIndex(index);
  m.setEntity(endpoints[index].entity_id);
  m.setInterface(endpoints[index].interface_id);
  m.setVLAN(endpoints[index].tag);
  update();

  let endpointSelectionModal = $('#add-endpoint-modal');
  endpointSelectionModal.modal('show');
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

    let url = new URL(window.location.href);
    let id = url.searchParams.get('vrf_id');

    try {
        let vrfID = await provisionVRF(
            session.data.workgroup_id,
            document.querySelector('#description').value,
            document.querySelector('#description').value,
            JSON.parse(sessionStorage.getItem('endpoints')),
            provisionTime,
            removeTime,
            id
        );

        if (vrfID === null) {
            addNetworkLoadingModal.modal('hide');
        } else {
            window.location.href = `index.cgi?action=view_l3vpn&vrf_id=${vrfID}`;
        }
    } catch (error){
        addNetworkLoadingModal.modal('hide');
        alert('Failed to modify L3VPN: ' + error);
        return;
    }
}

async function addNetworkCancelCallback(event) {
    window.location.href = 'index.cgi?action=welcome';
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
    let ipVersion = document.querySelector(`#new-peering-form-${index} .ip-version`);
    if (!ipVersion.validity.valid) {
        ipVersion.reportValidity();
        return null;
    }
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

    let ipVersionNo = ipVersion.checked ? 6 : 4;

    let peering = {
        ipVersion: ipVersionNo,
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

  let e = new EndpointList({endpoints: endpoints});
  render(e, document.querySelector('#selected-endpoint-list'));

  endpoints.forEach(function(endpoint, index) {
    //loadPeerFormValidator(index);
  });
}

function loadPeerFormValidator(index) {
  let ipVersion =  document.querySelector(`#new-peering-form-${index} .ip-version`);
  if (ipVersion.checked) {
    let yourPeerIP = document.querySelector(`#new-peering-form-${index} .your-peer-ip`);
    asIPv6CIDR(yourPeerIP);

    let oessPeerIP = document.querySelector(`#new-peering-form-${index} .oess-peer-ip`);
    asIPv6CIDR(oessPeerIP);
  } else {
    let yourPeerIP = document.querySelector(`#new-peering-form-${index} .your-peer-ip`);
    asIPv4CIDR(yourPeerIP);

    let oessPeerIP = document.querySelector(`#new-peering-form-${index} .oess-peer-ip`);
    asIPv4CIDR(oessPeerIP);
  }
}
