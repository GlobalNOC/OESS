document.addEventListener('DOMContentLoaded', function() {
  let url = new URL(window.location.href);
  let entityID = url.searchParams.get('entity_id');

  loadUserMenu().then(function() {
    [% IF network_type == 'evpn-vxlan' %]
    loadL2VPNs();
    [% ELSE %]
    loadEntityList();
    loadL2VPNs();
    [% END %]
  });
});

async function deleteConnection(id, name) {
    let ok = confirm(`Are you sure you want to delete "${name}"?`);
    if (ok) {
        let deleteCircuitModal = $('#delete-circuit-loading');
        deleteCircuitModal.modal('show');

        await deleteVRF(session.data.workgroup_id, id);
        window.location = '?action=welcome';
    }
}

async function deleteL2VPN(id, name) {
  let ok = confirm(`Are you sure you want to delete "${name}"?`);
  if (ok) {
    let deleteCircuitModal = $('#delete-circuit-loading');
    deleteCircuitModal.modal('show');

    await deleteCircuit(session.data.workgroup_id, id);
    window.location = '?action=welcome';
  }
}

async function toggleEntityBody(id) {
   let entityBody = document.querySelector(`#entity-body-${id}`);
   let entityClosed = document.querySelector(`#entity-body-${id}-closed`);
   let entityOpened = document.querySelector(`#entity-body-${id}-opened`);

   if (entityBody.style.display === 'none') {
       entityClosed.style.display = 'none';
       entityOpened.style.display = '';
       entityBody.style.display = 'block';
   } else {
       entityClosed.style.display = '';
       entityOpened.style.display = 'none';
       entityBody.style.display = 'none';
   }
}

async function loadEntityList() {
    let entities = await getVRFs(session.data.workgroup_id);
    let entitiesList = document.querySelector('#entity-list');

    let html = '';
    let ok = true;

    if (entities.length === 0) {
        html = '<p>There are no Layer 3 Connections currently provisioned. Click <a href="[% path %]new/index.cgi?action=provision_cloud">here</a> to create one.</p>';
    }

    entities.forEach(function(entity, index) {
        ok = true;
        let endpointHTML = '';

        entity.endpoints.forEach(function(endpoint) {
            let endpointOK = true;
            if (endpoint.operational_state !== 'up'){
                ok=false;
                endpointOK = false;
            }
            if ('peers' in endpoint) {
                endpoint.peers.forEach(function(peer) {
                    if (peer.operational_state !== 'up') {
                        ok = false;
                        endpointOK = false;
                    }
                });
            }

          let statusIcon = '<span class="glyphicon glyphicon glyphicon-circle-arrow-up" style="color: #5CB85C" aria-hidden="true"></span>';
          if (!endpointOK) {
            statusIcon = '<span class="glyphicon glyphicon glyphicon-circle-arrow-down" style="color: #D9534E" aria-hidden="true"></span>';
          }

          let bandwidth = 'unlimited';
          if (endpoint.bandwidth != 0) {
            bandwidth = `${endpoint.bandwidth} Mbps`;
          }

          endpointHTML += `
                <p class="entity-interface">${statusIcon} <b>${endpoint.node}</b><br/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;${endpoint.interface} - ${endpoint.tag} (${bandwidth})</p>
`;
        });

        let color = ok ? '#E0F0D9' : '#F2DEDE';
        let createdOn = new Date(parseInt(entity.created) * 1000);
        let modifiedOn = new Date(parseInt(entity.last_modified) * 1000);
        let bg_color = '#fff';
        let owner = 1;
        if(entity.workgroup.workgroup_id != session.data.workgroup_id){
            bg_color = '#e5e5e5';
            owner = 0;
        }

        let edit = `<a href='?action=modify_cloud&vrf_id=${entity.vrf_id}'><span class='glyphicon glyphicon-edit' style='padding-right: 9px;'></span></a>`;
        let del = `<a onclick="deleteConnection(${entity.vrf_id}, '${entity.description}')" href='javascript:void(0)'><span class='glyphicon glyphicon-trash' style='padding-right: 9px;'></span></a>`;
        if(owner != 1 && !session.data.isAdmin) {
            edit = "<span class='glyphicon glyphicon-edit' style='padding-right: 9px;'></span>";
            del = "<span class='glyphicon glyphicon-trash' style='padding-right: 9px;'></span>";
        }

        let entityHTML = `
<div class="panel panel-default">
  <div class="panel-heading" style="display: flex; background-color: ${bg_color};">
    <div style="width: 30px; background-color: ${color}; margin: -10px 15px -10px -15px;">
    </div>
    <div style="flex: 1;">
      <h4>${entity.description}</h4>
      <div style="display: flex;">
        <p style="padding-right: 15px; margin-bottom: 0px;"><b>Owner:</b> ${entity.workgroup.name}</p>
        <p style="padding-right: 15px; margin-bottom: 0px;"><b>Created on:</b> ${createdOn.toDateString()}</p>
      </div>
    </div>
    <h4>
      <!-- edit link has here -->
      <a href="?action=modify_cloud&vrf_id=${entity.vrf_id}"><span class="glyphicon glyphicon-eye-open" style="padding-right: 9px;"></span></a>
      ${del}
      <a id="entity-body-${index}-opened" onclick="toggleEntityBody(${index})" href="javascript:void(0)" style="display: none;"><span class="glyphicon glyphicon-chevron-up"></span></a>
      <a id="entity-body-${index}-closed" onclick="toggleEntityBody(${index})" href="javascript:void(0)"><span class="glyphicon glyphicon-chevron-down"></span></a>
    </h4>
  </div>

  <div id="entity-body-${index}" class="panel-body" style="padding-left: 45px; display: none;">
    <div style="display: flex;">
      <div style="padding-right: 15px;">
        <p><b>Description</b></p>
        <p><b>ID</b></p>
        <p><b>Prefix limit</b></p>
      </div>
      <div style="padding-right: 18px;">
        <p>${entity.description}</p>
        <p>${entity.vrf_id}</p>
        <p>${entity.prefix_limit}</p>
      </div>
      <div style="padding-right: 15px;">
        <p><b>Created by</b><p>
        <p><b>Created on</b><p>
        <p><b>Last modified by</b></p>
        <p><b>Last modified on</b></p>
      </div>
      <div style="padding-right: 18px;">
        <p>${entity.created_by.email}</p>
        <p>${createdOn.toDateString()}</p>
        <p>${entity.last_modified_by.email}</p>
        <p>${modifiedOn.toDateString()}</p>
      </div>
      <div style="flex: 1; display: flex; flex-direction: column;">
        ${endpointHTML}
      </div>
    </div>
  </div>
</div>
`;

        html += entityHTML;
    });

    entitiesList.innerHTML = html;
}

async function loadL2VPNs() {
  let circuits = await getCircuits(session.data.workgroup_id);
  let circuitsList = document.querySelector('#l2vpn-list');

  let html = '';
  let ok = true;

  if (circuits.length === 0) {
    html = '<p>There are no Layer 2 Connections currently provisioned. Click <a href="[% path %]new/index.cgi?action=provision_l2vpn">here</a> to create one.</p>';
  }

  circuits.forEach(function(circuit, index) {
    ok = true;
    let createdOn = new Date(circuit.created_on);
    let modifiedOn = new Date(circuit.last_modified_on);
    let bg_color = '#fff';
    let owner = 1;
    if(circuit.workgroup_id != session.data.workgroup_id){
      bg_color = '#e5e5e5';
      owner = 0;
    }

    let del = `<a onclick="deleteL2VPN(${circuit.circuit_id}, '${circuit.description}')" href='javascript:void(0)'><span class='glyphicon glyphicon-trash' style='padding-right: 9px;'></span></a>`;
    if(owner != 1 && !session.data.isAdmin){
      del = "<span class='glyphicon glyphicon-trash' style='padding-right: 9px;'></span>";
    }

    let endpointHTML = '';
    circuit.endpoints.forEach(function(endpoint) {
      let endpointOK = true;
      if ( endpoint.operational_state !== "up" ){
        endpointOK = false;
        ok = false;
      }
      let statusIcon = '<span class="glyphicon glyphicon glyphicon-circle-arrow-up" style="color: #5CB85C" aria-hidden="true"></span>';
      if (!endpointOK) {
        statusIcon = '<span class="glyphicon glyphicon glyphicon-circle-arrow-down" style="color: #D9534E" aria-hidden="true"></span>';
      }

      let bandwidth = 'unlimited';
      if (endpoint.bandwidth != 0) {
        bandwidth = `${endpoint.bandwidth} Mbps`;
      }

      endpointHTML += `
        <p class="entity-interface">${statusIcon} <b>${endpoint.node}</b><br/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;${endpoint.interface} - ${endpoint.tag} (${bandwidth})
        </p>
        `;
    });
     let color = ok ? '#E0F0D9' : '#F2DEDE'; 
    html += `
<div class="panel panel-default">
  <div class="panel-heading" style="display: flex; background-color: ${bg_color};">
    <div style="width: 30px; background-color: ${color}; margin: -10px 15px -10px -15px;">
    </div>
    <div style="flex: 1;">
      <h4>${circuit.description}</h4>
      <div style="display: flex;">
        <p style="padding-right: 15px; margin-bottom: 0px;"><b>Owner:</b> ${circuit.workgroup.name}</p>
        <p style="padding-right: 15px; margin-bottom: 0px;"><b>Created on:</b> ${createdOn.toDateString()}</p>
      </div>
    </div>
    <h4>
      <a href="?action=modify_l2vpn&circuit_id=${circuit.circuit_id}"><span class="glyphicon glyphicon-eye-open" style="padding-right: 9px;"></span></a>
      ${del}
      <a id="entity-body-${index+100000}-opened" onclick="toggleEntityBody(${index+100000})" href="javascript:void(0)" style="display: none;"><span class="glyphicon glyphicon-chevron-up"></span></a>
      <a id="entity-body-${index+100000}-closed" onclick="toggleEntityBody(${index+100000})" href="javascript:void(0)"><span class="glyphicon glyphicon-chevron-down"></span></a>
    </h4>
  </div>

  <div id="entity-body-${index+100000}" class="panel-body" style="padding-left: 45px; display: none;">
    <div style="display: flex;">
      <div style="padding-right: 15px;">
        <p><b>Description</b></p>
        <p><b>ID</b></p>
      </div>
      <div style="padding-right: 18px;">
        <p>${circuit.description}</p>
        <p>${circuit.circuit_id}</p>
      </div>
      <div style="padding-right: 15px;">
        <p><b>Created by</b><p>
        <p><b>Created on</b><p>
        <p><b>Last modified by</b></p>
        <p><b>Last modified on</b></p>
      </div>
      <div style="padding-right: 18px;">
        <p>${circuit.created_by.email}</p>
        <p>${createdOn.toDateString()}</p>
        <p>${circuit.last_modified_by.email}</p>
        <p>${modifiedOn.toDateString()}</p>
      </div>
      <div style="flex: 1; display: flex; flex-direction: column;">
        ${endpointHTML}
      </div>
    </div>
  </div>
</div>
`;
  });

  circuitsList.innerHTML = html;
}
