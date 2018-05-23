
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
    console.log('yo');
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

/* loadEndpointSelectionModal
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
  console.log(endpoint);

  let header   = document.getElementById('endpoint-select-header');
  header.innerHTML = endpoint.node || node;

  let elements = document.getElementById('endpoint-select-form').elements;
  elements['endpoint-select-bandwidth'].value    = endpoint.bandwidth || null;
  elements['endpoint-select-bgp-asn'].value      = endpoint.bgpASN    || null;
  elements['endpoint-select-bgp-key'].value      = endpoint.bgpKey    || null;
  elements['endpoint-select-interface'].value    = endpoint.interface || null;
  elements['endpoint-select-node'].value         = endpoint.node      || node;
  elements['endpoint-select-your-peer-ip'].value = endpoint.peerIP    || null;
  elements['endpoint-select-vlan'].value         = endpoint.tag       || null;
  elements['endpoint-select-id'].value           = index; // Index of endpoint in sessionStorage
}

/* loadEndpointSelectionTable
 * 
 * loadEndpointSelectionTable re-populates endpoint-selection-table
 * from scratch based on 'endpoints' in sessionStorage; Direct
 * modification of session storage followed by a call to this function
 * will update the UI.
 */

function loadEndpointSelectionTable() {
  let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
  let table = document.getElementById('endpoint-selection-table');

  for (let i = table.rows.length - 1; i > -1; i--) {
    table.deleteRow(i);
  }
  
  endpoints.forEach(function(endpoint, index) {
    let row   = table.insertRow(-1);

    let node = row.insertCell(0);
    node.innerHTML = endpoint.node;

    let intf = row.insertCell(1);
    intf.innerHTML = endpoint.interface;

    let vlan = row.insertCell(2);
    vlan.innerHTML = endpoint.tag;

    let asn = row.insertCell(3);
    asn.innerHTML = endpoint.bgpASN;

    let peerIP = row.insertCell(4);
    peerIP.innerHTML = endpoint.peerIP;

    let options = row.insertCell(5);
    options.innerHTML = `
<span class="glyphicon glyphicon-edit"   onclick="loadEndpointSelectionModal('${endpoint.node}', ${index})"></span>
<span class="glyphicon glyphicon-remove" onclick="removeFromEndpointSelectionTable(${index})"></span>
`;
  });
}

function submitEndpointSelectionModal(form) {
  let elements = form.elements;
  let endpoint = {
    bandwidth: elements['endpoint-select-bandwidth'].value,
    bgpASN:    elements['endpoint-select-bgp-asn'].value,
    bgpKey:    elements['endpoint-select-bgp-key'].value,
    interface: elements['endpoint-select-interface'].value,
    node:      elements['endpoint-select-node'].value,
    peerIP:    elements['endpoint-select-your-peer-ip'].value,
    tag:       elements['endpoint-select-vlan'].value,
    id:        elements['endpoint-select-id'].value
  };

  let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
  if (endpoint.id < 0) {
    // Endpoints with an id of -1 are new.
    endpoints.push(endpoint);
  } else {
    endpoints.splice(endpoint.id, 1, endpoint);
  }

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
  console.log(endpoints);

  let epoints   = [];
  endpoints.forEach(function(e) {
          e.peerings = [{
              asn: e.bgpASN,
              key: e.bgpKey,
              oessPeerIP: elements['oess-peer-ip'].value,
              yourPeerIP: e.peerIP
          }];
          epoints.push(e);
      });
  
  let resp = await provisionVRF(
    session.data.workgroup_id,
    elements['description'].value,
    elements['description'].value,
    epoints,
    provisionTime,
    removeTime,
    -1
  );

  if (typeof resp.success !=== undefined && resp.success === 1) {
      return true;
  }

  return false;
}
