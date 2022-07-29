function formatDate(seconds) {
    let d = new Date(seconds * 1000);
    return d.toLocaleString();
}

class GlobalState extends Component {
  constructor(state) {
    super();
    this.connection = {
      id:        -1,
      endpoints: []
    };
    this.history = [];
  }

  async selectConnection(id) {
    if (id != -1) {
      this.connection = await getVRF(session.data.workgroup_id, id);

      // Hack to display vrf_id using Object build for Layer2 Conns
      this.connection.circuit_id = this.connection.vrf_id;

      loadCommands(this.connection);

      this.history = await getVRFHistory(session.data.workgroup_id, id);

      document.getElementById('provision-time').innerHTML = '';
      document.getElementById('remove-time').innerHTML = '';
      document.getElementById('last-modified').innerHTML = formatDate(this.connection.last_modified);
      document.getElementById('last-modified-by').innerHTML = this.connection.last_modified_by.email;
      document.getElementById('created-on').innerHTML = formatDate(this.connection.created);
      document.getElementById('created-by').innerHTML = this.connection.created_by.email;
      document.getElementById('owned-by').innerHTML = this.connection.workgroup.name;
      document.getElementById('state').innerHTML = this.connection.state;
      document.getElementById('local_asn').innerHTML = this.connection.local_asn;
      
      let iframe3 = document.getElementById(`endpoints-statistics-iframe-route`);
      iframe3.dataset.vrf = this.connection.vrf_id;

      if (this.connection.endpoints.length == 0 || this.connection.endpoints[0].controller === "nso") {
        iframe3.src = `${iframe3.dataset.url}&var-table=OESS-VRF-${this.connection.vrf_id}&from=now-1h&to=now`;
      } else {
        iframe3.src = `${iframe3.dataset.url}&var-table=OESS-L3VPN-${this.connection.vrf_id}.inet.0&from=now-1h&to=now`;
      }

      this.connection.endpoints.forEach(function(endpoint, eIndex) {

        let select = document.createElement('select');
        select.setAttribute('class', 'form-control peer-selection');
        select.setAttribute('id', `peering-selection-${eIndex}`);
        select.setAttribute('onchange', 'updateStatisticsIFrame()');

        let peeringHTML = '';
        if (!'peers' in endpoint) {
          endpoint.peers = [];
        }

        endpoint.peers.forEach(function(peering, peeringIndex) {
          select.innerHTML += `<option value=${peering.peer_ip}>${peering.peer_ip}</option>`;
        });

        let peerSelections = document.getElementById('peering-selection');
        peerSelections.appendChild(select);
        
        let statGraph = `
<div id="endpoints-statistics-${eIndex}" class="panel panel-default endpoints-statistics" style="display: none;">
  <div class="panel-heading" style="height: 40px;">
    <h4 style="margin: 0px; float: left;">
    ${endpoint.node} <small>${endpoint.interface} - ${endpoint.tag}</small>
    </h4>
  </div>

  <div style="padding-left: 15px; padding-right: 15px">
    <iframe id="endpoints-statistics-iframe-${eIndex}" data-url="[% g_port %]" data-node="${endpoint.node}" data-interface="${endpoint.interface}" data-unit="${endpoint.unit}" width="100%" height="300" frameborder="0"></iframe>
    <iframe id="endpoints-statistics-iframe-peer-${eIndex}" data-url="[% g_peer %]" data-controller="${endpoint.controller}" data-node="${endpoint.node}" data-vrf="${this.connection.vrf_id}" width="100%" height="300" frameborder="0"></iframe>
  </div>
</div>`;

        let stats = document.getElementById('endpoints-statistics');
        stats.innerHTML += statGraph;

        let statOption = `<option value="${eIndex}">${endpoint.node} - ${endpoint.interface} - ${endpoint.tag}</option>`;

        let dropdown = document.getElementById('endpoints-statistics-selection');
        dropdown.innerHTML += statOption;
        displayStatisticsIFrame();
      }.bind(this));

      document.getElementById('endpoints-statistics-0').style.display = 'block';
    }

    update();
  }

  updateEndpoint(e) {
    if (e.index < 0) {
      this.connection.endpoints.push(e);
    } else {
      this.connection.endpoints[e.index] = e;
    }
    update();
  }

  deleteEndpoint(i) {
    this.connection.endpoints.splice(i, 1);
    update();
  }

  deletePeering(endpointIndex, peeringIndex) {
    this.connection.endpoints[endpointIndex].peers.splice(peeringIndex, 1);
  }

  // Named deleteCircuit to work with Object built from Layer2 Conns
  async deleteCircuit() {
    let vrfID = parseInt(this.connection.vrf_id);

    let ok = confirm(`Are you sure you want to delete "${this.connection.description}"?`);
    if (ok) {
      let deleteModal = $('#delete-connection-loading');
      deleteModal.modal('show');

      try {
        let result = await deleteVRF(session.data.workgroup_id, vrfID);
        if (result == null) throw('Unknown');
        window.location = '?action=welcome';
      } catch (error) {
        deleteModal.modal('hide');
        alert(`Failed to delete connection: ${error}`);
      }
    }
  }

  // Named saveCircuit to work with Object built from Layer2 Conns
  async saveCircuit() {

    let addNetworkLoadingModal = $('#add-connection-loading');
    addNetworkLoadingModal.modal('show');
    try {
      let vrfID = await provisionVRF(
        session.data.workgroup_id,
        this.connection.name,
        document.querySelector('#header-description').textContent,
        this.connection.endpoints,
        -1,
        -1,
        this.connection.vrf_id
      );

      if (vrfID === null) {
        addNetworkLoadingModal.modal('hide');
      } else {
        window.location.href = `index.cgi?action=modify_cloud&vrf_id=${vrfID}`;
      }
    } catch (error){
      addNetworkLoadingModal.modal('hide');
      alert('Failed to provision L3VPN: ' + error);
      return;
    }
  }

  cancel() {
    if (!window.confirm('Are you sure you wish to cancel? All your changes will be lost.')) {
      return;
    }
    window.location.href = 'index.cgi';
  }
}

$(function () {
  $('[data-toggle="popover"]').popover();
});

let state = new GlobalState();
let modal = new EndpointSelectionModal2('#endpoint-selection-modal');
let history = new ResourceHistoryTable();

document.addEventListener('DOMContentLoaded', async function() {
  await loadUserMenu();

  let url = new URL(window.location.href);
  let id = url.searchParams.get('vrf_id');

  state.selectConnection(id)
    .then(async () => {
      let userMayEdit = session.data.isAdmin || (session.data.workgroup_id == state.connection.workgroup.workgroup_id && !session.data.isReadOnly);
      let connActive = state.connection.state !== 'decom';
      let editable = connActive && userMayEdit;

      let newEndpointButton = document.querySelector('#new-endpoint-button');
      newEndpointButton.style.display = (editable) ? 'block' : 'none';

      let header = new CircuitHeader();
      document.querySelector('#circuit-header').innerHTML = await header.render({
        connectionId: state.connection.vrf_id,
        description: state.connection.description,
        editable: editable
      });
      addEditNameEvents(state.connection.description);

      let historyElem = document.querySelector('#history');
      historyElem.innerHTML = await history.render(state);
    })
    .catch( error => {
      if (state.connection == null) {
        document.getElementById("connection_error").style.display = "block";
        document.getElementById("circuit").style.display = "none";
      }
    });

  let addNetworkEndpoint = document.querySelector('#new-endpoint-button');
  addNetworkEndpoint.addEventListener('click', function(event) {
    modal.display(null);
  });

  let map = new NDDIMap('map');
  map.on("loaded", function(){
    this.updateMapFromSession(session);
  });
});

async function update() {
  let userMayEdit = session.data.isAdmin || (session.data.workgroup_id == state.connection.workgroup.workgroup_id && !session.data.isReadOnly);
  let connActive = state.connection.state !== 'decom';
  let editable = connActive && userMayEdit;

  let list = document.getElementById('endpoints2-list');
  list.innerHTML = '';

  state.connection.endpoints.map(function(e, i) {
    e.index = i;
    e.peers = ('peers' in e) ? e.peers : [];
    e.editable = editable;
    e.isPeeringAutoGenerated = (e.cloud_interconnect_type !== null && e.cloud_interconnect_type !== 'aws-hosted-connection' && e.cloud_interconnect_type !== 'oracle-fast-connect');

    let endpoint = new Endpoint2('#endpoints2-list', e);
    e.peers.map(function(p, j) {
      p.index = j;
      p.endpointIndex = i;
      p.editable = editable;
      p.isPeeringAutoGenerated = (e.cloud_interconnect_type !== null && e.cloud_interconnect_type !== 'aws-hosted-connection' && e.cloud_interconnect_type !== 'oracle-fast-connect');

      let peeringElem = endpoint.peerings();
      let peering = new Peering2(peeringElem, p);
      peering.onDelete(function(peering) {
        state.deletePeering(i, j);
        update();
      });
    });
  });
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
    iframe.src = `${iframe.dataset.url}&var-node=${iframe.dataset.node}&var-interface=${iframe.dataset.interface}.${iframe.dataset.unit}` + range.value;

    let iframe2 = document.getElementById(`endpoints-statistics-iframe-peer-${container.value}`);
    if (iframe2.dataset.controller === "nso") {
      iframe2.src = `${iframe2.dataset.url}&var-node=${iframe2.dataset.node}&var-vrf=OESS-VRF-${iframe2.dataset.vrf}&var-peer=${peer.value.split('/')[0]}` + range.value;
    } else {
      iframe2.src = `${iframe2.dataset.url}&var-node=${iframe2.dataset.node}&var-vrf=OESS-L3VPN-${iframe2.dataset.vrf}&var-peer=${peer.value}` + range.value;
    }
}
