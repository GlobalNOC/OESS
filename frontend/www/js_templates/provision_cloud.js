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

  let url = new URL(window.location.href);
  let id = url.searchParams.get('prepop_vrf_id');
  if (id) {
      showAndPrePopulateEndpointSelectionModal(id);
  }
});

async function addNetworkEndpointCallback(event) {
    showEndpointSelectionModal(null);
}

async function modifyNetworkEndpointCallback(index) {
    let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
    endpoints[index].index = index;

    showEndpointSelectionModal(endpoints[index]);
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

    try{
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

  console.log(endpoints);
  endpoints.forEach(function(endpoint, index) {
          let endpointName = '';
          if ('entity_id' in endpoint) {
              endpointName = `${endpoint.entity} ${endpoint.node} <small>${endpoint.name} ${endpoint.tag}</small>`;
          } else {
              endpointName = `${endpoint.node} <small>${endpoint.name} - ${endpoint.tag}</small>`;
          }

          let peerings = '';
          endpoint.peerings.forEach(function(peering, peeringIndex) {
                  peerings += `
<tr>
  <td>${peering.ipVersion === 4 ? 'ipv4' : 'ipv6'}</td>
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
        <thead><tr><th></th><th>Your ASN</th><th>Your IP</th><th>Your BGP Key</th><th>OESS IP</th><th></th></tr></thead>
        <tbody>
          ${peerings}
          <tr id="new-peering-form-${index}">
            <td><div class="checkbox"><label><input class="ip-version" type="checkbox" onchange="loadPeerFormValidator(${index})"> ipv6</input></label></div></td>
            <td><input class="form-control bgp-asn" type="number" ${ endpoint.cloud_account_type ? 'disabled' : 'required' } /></td>
            <td><input class="form-control your-peer-ip" type="text" ${ endpoint.cloud_account_type ? 'disabled' : 'required' } /></td>
            <td><input class="form-control bgp-key" type="text" ${ endpoint.cloud_account_type ? 'disabled' : '' } /></td>
            <td><input class="form-control oess-peer-ip" type="text" ${ endpoint.cloud_account_type ? 'disabled' : 'required' } /></td>
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
    loadPeerFormValidator(index);
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
