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
  let vlans = await getAvailableVLANs(session.data.workgroup_id, interfaces[0].interface_id);

  m = new EndpointSelectionModal({
    interface: interfaces[0].interface_id,
    vlan: vlans[0]
  });
  update();
}

async function update(props) {
  render(m, document.querySelector('#add-endpoint-modal'), props);
}

document.addEventListener('DOMContentLoaded', function() {
  load();
});

async function showEndpointSelectionModal(endpoint, options) {
  if (endpoint) {
    document.querySelector('#endpoint-select-header').innerHTML = 'Modify Network Endpoint';

    m.setIndex(endpoint.index);
    m.setEntity(endpoint.entity_id);
    m.setInterface(endpoint.interface_id);
    m.setVLAN(endpoint.tag);

    update();
  } else {
    document.querySelector('#endpoint-select-header').innerHTML = 'Add Network Endpoint';
    update();
  }

  let endpointSelectionModal = $('#add-endpoint-modal');
  endpointSelectionModal.modal('show');
}


// --- Interfaces ---

async function loadInterfaces() {
    let interfaces = await getInterfacesByWorkgroup(session.data.workgroup_id);

    let options = '';
    interfaces.forEach(function(intf) {
            options += `<option data-entity="${intf.entity}" data-entity="${intf.entity_id}" data-id="${intf.interface_id}" data-cloud-interconnect-id="${intf.cloud_interconnect_id}" data-cloud-interconnect-type="${intf.cloud_interconnect_type}" data-node="${intf.node}" data-interface="${intf.name}" value="${intf.name} - ${intf.name}">
                          ${intf.node} - ${intf.name}
                        </option>`;
    });
    document.querySelector('#endpoint-select-interface').innerHTML = options;

    if (interfaces.length === 0) {
        document.querySelector('#endpoint-select-interface').setAttribute('disabled', true);
        document.querySelector('#endpoint-select-interface').innerHTML = '<option>Interfaces not found for the current workgroup</option>';
    } else {
        document.querySelector('#endpoint-select-interface').removeAttribute('disabled');
    }

    loadInterfaceVLANs();
}

async function loadInterfaceVLANs() {
    console.log('loading interface vlans');

    let select = document.querySelector('#endpoint-select-interface');
    if (!select.value) {
        document.querySelector('#endpoint-vlans').setAttribute('disabled', true);
        document.querySelector('#endpoint-vlans').innerHTML = '<option>VLANs not available for the selected Interface</option>';
        return null;
    }

    let id = select.options[select.selectedIndex].getAttribute('data-id');

    let vlans = await getAvailableVLANs(session.data.workgroup_id, id);
    let options = '';
    for (let i = 0; i < vlans.length; i++) {
        options += `<option>${vlans[i]}</option>`;
    }
    document.querySelector('#endpoint-vlans').innerHTML = options;

    if (vlans.length === 0) {
        document.querySelector('#endpoint-vlans').setAttribute('disabled', true);
        document.querySelector('#endpoint-vlans').innerHTML = '<option>VLANs not available for the selected Interface</option>';
    } else {
        document.querySelector('#endpoint-vlans').removeAttribute('disabled');
    }
}

async function loadInterfaceCloudAccountInput() {
    console.log('loading interface cloud account input');

    let select = document.querySelector('#endpoint-select-interface');
    if (!select.value) {
        return null;
    }

    let id = select.options[select.selectedIndex].getAttribute('data-id');
    let interconnect_id = select.options[select.selectedIndex].getAttribute('data-cloud-interconnect-id');
    let interconnect_type = select.options[select.selectedIndex].getAttribute('data-cloud-interconnect-type');
}
