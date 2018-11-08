
function setDateTimeVisibility() {
  let form = document.getElementById('private-network-form');
  let type = form.elements['provision-time'].value;
  let pick = document.getElementById('provision-time-picker');

  if (type === 'later') {
    pick.style.display = 'block';
  } else {
    pick.style.display = 'none';
  }

  type = form.elements['remove-time'].value;
  pick = document.getElementById('remove-time-picker');

  if (type === 'later') {
    pick.style.display = 'block';
  } else {
    pick.style.display = 'none';
  }
}

  async function loadEndpointSelectionInterfaces(nodeName) {
    const interfaces = await getInterfaces(session.data.workgroup_id, nodeName);

    let form   = document.getElementById('endpoint-select-form')
    let select = form.elements['endpoint-select-interface'];
    select.innerHTML = '';
    select.onchange = loadEndpointSelectionVLANs;
    
    interfaces.forEach(function(intf) {
      let option = document.createElement('option');
      option.innerHTML = intf.name;
      option.setAttribute('data-vlan-range', intf.mpls_vlan_tag_range);
      option.setAttribute('value', intf.name);
      select.appendChild(option);
    });

    select.selectedIndex = 0;
    loadEndpointSelectionVLANs({target: select});
  };

  async function loadEndpointSelectionVLANs(event) {
    let form   = document.getElementById('endpoint-select-form')
    let select = form.elements['endpoint-select-vlan'];
    select.innerHTML = '';

    let index  = event.target.options.selectedIndex;
    let ranges = event.target.options[index].getAttribute('data-vlan-range');

    ranges.split(',').forEach(function(range) {
      let low   = 1;
      let high  = 0;

      let parts = range.split("-");
      low   = parseInt(parts[0]);
      high  = parseInt(parts[0]);

      if (parts.length > 1) {
        high = parts[1];
      }

      for (let i = low; i <= high; i++) {
        let option = document.createElement('option');
        option.innerHTML = i;
        option.setAttribute('value', i);
        select.appendChild(option);
      }
    });
  }

document.addEventListener('DOMContentLoaded', function() {
  sessionStorage.setItem('endpoints', '[]');

  // Hides datetime selectors by default
  setDateTimeVisibility();

  $('#endpoint-select-form').submit(function(event){
    event.preventDefault();
    submitEndpointSelectionModal(event.target);
  });

  $('#endpoint-select-cancel').click(function(){
    $('#modal1').modal('hide');
  });

  $('#private-network-form').submit(function(event){
    event.preventDefault();
    submitPrivateNetworkForm(event.target);
  });

  let map = new NDDIMap('map');
  map.on("loaded", function(){
    this.updateMapFromSession(session);
  });

  map.on("clickNode", function(e, args) {
    let node = args[0].name;
    loadEndpointSelectionModal(node);
    loadEndpointSelectionInterfaces(node);
  });

  loadEndpointSelectionInterfaces('vmx-r0.testlab.grnoc.iu.edu');
});

function removeFromEndpointSelectionTable(index) {
  let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
  endpoints.splice(index, 1);
  sessionStorage.setItem('endpoints', JSON.stringify(endpoints));

  loadEndpointSelectionTable();
}

/** loadEndpointSelectionModal
 *
 * loadEndpointSelectionModal populates endpoint-select-form based on
 * 'endpoints' in sessionStorage indexed at index. If index is -1 or
 * not provided, endpoint-select-form is loaded with the assumption a
 * new endpoint will be added.
 */
async function loadEndpointSelectionModal(node, index=-1) {
  $('#modal1').modal('show');

  let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
  let endpoint  = {};
  if (index > -1) {
    endpoint = endpoints[index];
    await loadEndpointSelectionInterfaces(node);
  }

  let header   = document.getElementById('endpoint-select-header');
  header.innerHTML = endpoint.node || node;

  let elements = document.getElementById('endpoint-select-form').elements;
  elements['endpoint-select-bandwidth'].value = endpoint.bandwidth || null;
  elements['endpoint-select-interface'].value = endpoint.interface || null;
  elements['endpoint-select-node'].value      = endpoint.node      || node;
  elements['endpoint-select-vlan'].value      = endpoint.tag       || null;
  elements['endpoint-select-id'].value        = index; // Index of endpoint in sessionStorage
}

async function loadPeeringSelectionModal(endpointIndex, peeringIndex) {

    $('#peering-select-cancel').click(function(){
            $('#modal2').modal('hide');
        });

    $('#peering-select-form').click(function(){
            event.preventDefault();
            $('#modal2').modal('hide');
        });

    $('#modal2').modal('show');
}

/** loadEndpointSelectionTable
 * 
 * loadEndpointSelectionTable re-populates endpoint-selection-table
 * from scratch based on 'endpoints' in sessionStorage; Direct
 * modification of session storage followed by a call to this function
 * will update the UI.
 */

function loadEndpointSelectionTable() {
  let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
  let table = document.getElementById('endpoint-selection-table');


  table.innerHTML = '';
  endpoints.forEach(function(endpoint, index) {

    let html = `
<div class="panel panel-default">
  <div class="panel-heading">
    <h4 style="margin: 0px">
      ${endpoint.node} <small>${endpoint.interface} - ${endpoint.tag}</small>
      <span style="float: right;">
        <span class="glyphicon glyphicon-edit"   onclick="loadEndpointSelectionModal('${endpoint.node}', ${index})"></span>
        <span class="glyphicon glyphicon-trash" onclick="removeFromEndpointSelectionTable(${index})"></span>
      </span>
    </h4>
  </div>
`;

    let peeringHTML = '';
    endpoint.peerings.forEach(function(peering, peeringIndex) {
      peeringHTML += `<tr>
        <td>${peering.asn}</td>
<td>${peering.yourPeerIP}</td>
<td>${peering.key}</td>
<td>${peering.oessPeerIP}</td>
<td><button class="btn btn-danger btn-sm" class="form-control" type="button" onclick="deletePeering(${index}, ${peeringIndex})">&nbsp;<span class="glyphicon glyphicon-trash"></span>&nbsp;</button></td>
</tr>`;
    });

    let bodyHTML = `
<table class="table">
  <thead>
    <tr><th>Your Peer ASN</th><th>Your Peer IP</th><th>Your BGP Key</th><th>OESS Peer IP</th><th></th></tr>
  </thead>
  <tbody>
    ${peeringHTML}
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
`;


    table.innerHTML += html + bodyHTML;
  });
}

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
    loadEndpointSelectionTable();
}

function deletePeering(endpointIndex, peeringIndex) {
    let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
    endpoints[endpointIndex].peerings.splice(peeringIndex, 1);
    console.log(endpoints);
    sessionStorage.setItem('endpoints', JSON.stringify(endpoints));

    // Redraw endpoints
    loadEndpointSelectionTable();
}

function submitEndpointSelectionModal(form) {
  let elements = form.elements;
  let endpoint = {
    bandwidth: elements['endpoint-select-bandwidth'].value,
    interface: elements['endpoint-select-interface'].value,
    node:      elements['endpoint-select-node'].value,
    tag:       elements['endpoint-select-vlan'].value,
    id:        elements['endpoint-select-id'].value
  };

  let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
  if (endpoint.id < 0) {
    // Endpoints with an id of -1 are new.
    endpoint['peerings'] = [];
    endpoints.push(endpoint);
  } else {
    endpoints.splice(endpoint.id, 1, endpoint);
  }

  console.log(endpoints);
  sessionStorage.setItem('endpoints', JSON.stringify(endpoints));
  loadEndpointSelectionTable();

  $('#modal1').modal('hide');
}

async function submitPrivateNetworkForm(form) {
  let elements = form.elements;

  let provisionTime = -1;
  if (elements['provision-time'].value === 'later') {
    let date = new Date(elements['provision-time-picker'].value);
    provisionTime = date.getTime();
  }

  let removeTime = -1;
  if (elements['remove-time'].value === 'later') {
    let date = new Date(elements['remove-time-picker'].value);
    removeTime = date.getTime();
  }

  let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
  
  try {
      let vrfID = await provisionVRF(
          session.data.workgroup_id,
          elements['description'].value,
          elements['description'].value,
          endpoints,
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
      alert('Failed to modify L3VPN: ' + error);
      return;
  }
}
