
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
  loadUserMenu().then(function() {
      $('#delete-vrf-button').click(function(){
          deleteConnection(session.data.workgroup_id);
      });

      $('#edit-vrf-button').click(function(){
          modifyConnection();
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

      loadVRF();
  });
});

async function deleteConnection(id) {
    let vrfID = document.getElementById('vrf-id').innerHTML;
    vrfID = parseInt(vrfID);

    let ok = confirm(`Are you sure you want to delete this connection?`);
    if (ok) {
        await deleteVRF(session.data.workgroup_id, vrfID);
        window.location = '?action=welcome';
    }
}

async function modifyConnection(id) {
    let vrfID = document.getElementById('vrf-id').innerHTML;
    vrfID = parseInt(vrfID);

    window.location = `?action=modify_cloud&vrf_id=${vrfID}`;
}

function removeFromEndpointSelectionTable(index) {
  let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
  endpoints.splice(index, 1);
  sessionStorage.setItem('endpoints', JSON.stringify(endpoints));

  loadEndpointSelectionTable();
}

function formatDate(seconds) {
    let d = new Date(seconds * 1000);
    return d.toLocaleString();
}

/**
 * loadVRF
 */
async function loadVRF() {
  let url = new URL(window.location.href);
  let vrfID = url.searchParams.get('vrf_id');

  let vrf = await getVRF(vrfID);
  console.log(vrf);

  let description = document.getElementById('description');
  description.innerHTML = `${vrf.description} <small>${vrf.vrf_id}</small>`;

  document.getElementById('vrf-id').innerHTML = vrf.vrf_id;
  document.getElementById('provision-time').innerHTML = '';
  document.getElementById('remove-time').innerHTML = '';
  document.getElementById('last-modified').innerHTML = formatDate(vrf.last_modified);
  document.getElementById('last-modified-by').innerHTML = vrf.last_modified_by.email;
  document.getElementById('created-on').innerHTML = formatDate(vrf.created);
  document.getElementById('created-by').innerHTML = vrf.created_by.email;
  document.getElementById('owned-by').innerHTML = vrf.workgroup.name;
  document.getElementById('state').innerHTML = vrf.state;

  let peerSelections = document.getElementById('peering-selection');

  let iframe3 = document.getElementById(`endpoints-statistics-iframe-route`);
  iframe3.dataset.vrf = vrf.vrf_id;
  iframe3.src = `${iframe3.dataset.url}&var-table=OESS-L3VPN-${vrf.vrf_id}.inet.0&from=now-1h&to=now`;

  vrf.endpoints.forEach(function(endpoint, eIndex) {

    let select = document.createElement('select');
    select.setAttribute('class', 'form-control peer-selection');
    select.setAttribute('id', `peering-selection-${eIndex}`);
    select.setAttribute('onchange', 'updateStatisticsIFrame()');

    let peeringHTML = '';
    endpoint.peers.forEach(function(peering, peeringIndex) {
      peeringHTML += `
<tr>
  <td></td>
  <td>${peering.peer_asn}</td>
  <td>${peering.peer_ip}</td>
  <td>${peering.md5_key}</td>
  <td>${peering.local_ip}</td>
  <td><span id="state" class="label label-success">active</span></td>
</tr>`;

      select.innerHTML += `<option value=${peering.peer_ip}>${peering.peer_ip}</option>`;
    });

    peerSelections.appendChild(select);

    let html = `
<div class="panel panel-default">
  <div class="panel-heading" style="height: 40px;">
    <h4 style="margin: 0px; float: left;">
    ${endpoint.node.name} <small>${endpoint.interface.name} - ${endpoint.tag}</small>
    </h4>
  </div>

  <div style="padding-left: 15px; padding-right: 15px">
  </div>

  <table class="table">
    <thead>
      <tr><th></th><th>Your ASN</th><th>Your IP</th><th>Your BGP Key</th><th>OESS IP</th><th>Status</th></tr>
    </thead>
    <tbody>
      ${peeringHTML}
    </tbody>
  </table>
</div>`;

    let endpoints = document.getElementById('endpoints');
    endpoints.innerHTML += html;

    let statGraph = `
<div id="endpoints-statistics-${eIndex}" class="panel panel-default endpoints-statistics" style="display: none;">
  <div class="panel-heading" style="height: 40px;">
    <h4 style="margin: 0px; float: left;">
    ${endpoint.node.name} <small>${endpoint.interface.name} - ${endpoint.tag}</small>
    </h4>
  </div>

  <div style="padding-left: 15px; padding-right: 15px">
    <iframe id="endpoints-statistics-iframe-${eIndex}" data-url="[% g_port %]" data-node="${endpoint.node.name}" data-interface="${endpoint.interface.name}" width="100%" height="300" frameborder="0"></iframe>
    <iframe id="endpoints-statistics-iframe-peer-${eIndex}" data-url="[% g_peer %]" data-node="${endpoint.node.name}" data-vrf="${vrf.vrf_id}" width="100%" height="300" frameborder="0"></iframe>
  </div>
</div>`;

    let stats = document.getElementById('endpoints-statistics');
    stats.innerHTML += statGraph;

    let statOption = `<option value="${eIndex}">${endpoint.node.name} - ${endpoint.interface.name} - ${endpoint.tag}</option>`;

    let dropdown = document.getElementById('endpoints-statistics-selection');
    dropdown.innerHTML += statOption;

    displayStatisticsIFrame();
  });

  document.getElementById('endpoints-statistics-0').style.display = 'block';
}

function displayStatisticsIFrame() {
    let elements = document.getElementsByClassName('endpoints-statistics');
    for (let i = 0; i < elements.length; i++) {
        elements[i].style.display = 'none';
    }

    let selections = document.getElementsByClassName('peer-selection');
    for (let i = 0; i < selections.length; i++) {
        selections[i].style.display = 'none';
    }

    let container = document.getElementById(`endpoints-statistics-selection`);

    let element = document.getElementById(`endpoints-statistics-${container.value}`);
    element.style.display = 'block';

    let peer = document.getElementById(`peering-selection-${container.value}`);
    peer.style.display = 'block';

    updateStatisticsIFrame();
}

function updateStatisticsIFrame() {
    let container = document.getElementById(`endpoints-statistics-selection`);

    let range = document.getElementById(`endpoints-statistics-range`);

    let peer = document.getElementById(`peering-selection-${container.value}`);

    let iframe = document.getElementById(`endpoints-statistics-iframe-${container.value}`);
    iframe.src = `${iframe.dataset.url}&var-node=${iframe.dataset.node}&var-interface=${iframe.dataset.interface}` + range.value;

    let iframe2 = document.getElementById(`endpoints-statistics-iframe-peer-${container.value}`);
    iframe2.src = `${iframe2.dataset.url}&var-node=${iframe2.dataset.node}&var-vrf=OESS-L3VPN-${iframe2.dataset.vrf}&var-peer=${peer.value}` + range.value;

    let iframe3 = document.getElementById(`endpoints-statistics-iframe-route`);
    iframe3.src = `${iframe3.dataset.url}&var-table=OESS-L3VPN-${iframe3.dataset.vrf}.inet.0` + range.value;
}
