document.addEventListener('DOMContentLoaded', function() {
  let url = new URL(window.location.href);
  let entityID = url.searchParams.get('entity_id');

  loadUserMenu().then(function() {
      loadEntityList();
  });
});

async function deleteConnection(id, name) {
    let ok = confirm(`Are you sure you want to delete ${name}?`);
    if (ok) {
        await deleteVRF(session.data.workgroup_id, id);
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

    entities.forEach(function(entity, index) {

        let endpointHTML = '';

        entity.endpoints.forEach(function(endpoint) {
            let endpointOK = true;
            endpoint.peers.forEach(function(peer) {
                    if (peer.state !== 'active') {
                        ok = false;
                        endpointOK = false;
                    }
            });

            if (endpointOK) {
                endpointHTML += `
                <p class="entity-interface"><span class="label label-success">▴</span> <b>${endpoint.interface.node}</b><br/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;${endpoint.interface.name} - ${endpoint.tag}</p>
`;
            } else {
                endpointHTML += `
                <p class="entity-interface"><span class="label label-danger">▾</span> <b>${endpoint.interface.node}</b><br/>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;${endpoint.interface.name} - ${endpoint.tag}</p>
`;
            }
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
        let del = `<a onclick="deleteConnection(${entity.vrf_id}, '${entity.name}')" href='javascript:void(0)'><span class='glyphicon glyphicon-trash' style='padding-right: 9px;'></span></a>`;
        if(owner != 1){
            edit = "<span class='glyphicon glyphicon-edit' style='padding-right: 9px;'></span>";
            del = "<span class='glyphicon glyphicon-trash' style='padding-right: 9px;'></span>";
        }

        let entityHTML = `
<div class="panel panel-default">
  <div class="panel-heading" style="display: flex; background-color: ${bg_color};">
    <div style="width: 30px; background-color: ${color}; margin: -10px 15px -10px -15px;">
    </div>
    <div style="flex: 1;">
      <h4>${entity.name}</h4>
      <div style="display: flex;">
        <p style="padding-right: 15px; margin-bottom: 0px;"><b>Owner:</b> ${entity.workgroup.name}</p>
        <p style="padding-right: 15px; margin-bottom: 0px;"><b>Created on:</b> ${createdOn.toDateString()}</p>
      </div>
    </div>
    <h4>
      ${edit}
      <a href="?action=view_l3vpn&vrf_id=${entity.vrf_id}"><span class="glyphicon glyphicon-stats" style="padding-right: 9px;"></span></a>
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
