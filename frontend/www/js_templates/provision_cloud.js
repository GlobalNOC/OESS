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


let schedule = new Schedule('#schedule-picker');


document.addEventListener('DOMContentLoaded', function() {
  sessionStorage.setItem('endpoints', '[]');

  load();

  loadUserMenu().then(function() {
    // TODO remove?
    // setDateTimeVisibility();
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

async function addNetworkEndpointCallback(event) {
  m.setIndex(-1);
  m.setEntity(null);
  m.setJumbo(null);
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
  m.setJumbo(endpoints[index].jumbo);
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

    let addNetworkLoadingModal = $('#add-network-loading');
    addNetworkLoadingModal.modal('show');

    try{
        let vrfID = await provisionVRF(
          session.data.workgroup_id,
          document.querySelector('#description').value,
          document.querySelector('#description').value,
          JSON.parse(sessionStorage.getItem('endpoints')),
          schedule.createTime(),
          schedule.removeTime(),
          -1
        );

        if (vrfID === null) {
            addNetworkLoadingModal.modal('hide');
        } else {
            window.location.href = `index.cgi?action=view_l3vpn&vrf_id=${vrfID}`;
        }
    } catch (error){
        addNetworkLoadingModal.modal('hide');
        alert('Failed to provision L3VPN: ' + error);
        return;
    }
}

async function addNetworkCancelCallback(event) {
    window.location.href = 'index.cgi?action=welcome';
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
