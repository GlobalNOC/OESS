
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
  $('#delete-vrf-button').click(function(){
    console.log('delete');
  });

  $('#edit-vrf-button').click(function(){
    console.log('edit');
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

function removeFromEndpointSelectionTable(index) {
  let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
  endpoints.splice(index, 1);
  sessionStorage.setItem('endpoints', JSON.stringify(endpoints));

  loadEndpointSelectionTable();
}

/**
 * loadVRF
 */
async function loadVRF() {
  let vrf = await getVRF(37);
  console.log(vrf);

  let description = document.getElementById('description');
  description.innerHTML = `${vrf.description} <small>${vrf.vrf_id}</small>`;

  document.getElementById('provision-time').innerHTML = '';
  document.getElementById('remove-time').innerHTML = '';
  document.getElementById('last-modified').innerHTML = new Date(vrf.last_modified * 1000);
  document.getElementById('created-on').innerHTML = new Date(vrf.created * 1000);
  document.getElementById('created-by').innerHTML = vrf.created_by[0].auth_name;
  document.getElementById('owned-by').innerHTML = vrf.workgroup.name;
  document.getElementById('state').innerHTML = vrf.state;

  let endpoints = document.getElementById('endpoints');
  vrf.endpoints.forEach(function(endpoint) {

    let peeringHTML = '';
    endpoint.peers.forEach(function(peering, peeringIndex) {
      peeringHTML += `
<tr>
  <td></td>
  <td>${peering.peer_asn}</td>
  <td>${peering.peer_ip}</td>
  <td>${peering.md5_key}</td>
  <td>${peering.local_ip}</td>
</tr>`;

    });

    console.log(endpoint);
    let html = `
<div class="panel panel-default">
 <div class="panel-heading">
   <h4 style="margin: 0px">
   ${endpoint.node} <small>${endpoint.name} - ${endpoint.tag}</small>
   </h4>
  </div>

  <table class="table">
    <thead>
      <tr><th></th><th>Your Peer ASN</th><th>Your Peer IP</th><th>Your BGP Key</th><th>OESS Peer IP</th></tr>
    </thead>
    <tbody>
      ${peeringHTML}
    </tbody>
  </table>
</div>`;
    
    endpoints.innerHTML += html;
  });
}
