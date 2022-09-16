class GlobalState extends Component {
  constructor(state) {
    super();
    this.id = -1;
    this.selectedEndpoint = -1;
  }

  async selectCircuit(id) {
    this.id = id;

    [this.circuit, this.history, this.events, this.raw] = await Promise.all([
      getCircuit(id, session.data.workgroup_id),
      getCircuitHistory(id),
      getCircuitEvents(id),
      getRawCircuit(id)
    ]);

    if (this.circuit == null){
      document.getElementById("connection_error").style.display = "block";
      document.getElementById("circuit2").style.display = "none";
    }


    update();
  }

  selectEndpoint(index) {
    $('#add-endpoint-modal').modal('show');
    this.selectedEndpoint = index;

    // Ensure index field is properly set. Could change after an
    // endpoint removal.
    if (this.selectedEndpoint > -1) {
      this.circuit.endpoints[this.selectedEndpoint].index = this.selectedEndpoint;
    }
    update();
  }

  updateEndpoint(e) {
    e['interface'] = e.name;
    e['interface_description'] = 'NA';

    if (e.index < 0) {
      this.circuit.endpoints.push(e);
    } else {
      this.circuit.endpoints[e.index] = e;
    }

    update();
  }

  deleteEndpoint(i) {
    this.circuit.endpoints.splice(i, 1);
    update();
  }

  saveCircuit() {
    console.log('provisionCircuit:', this.circuit);

    let provisionModal = $('#modify-loading');
    provisionModal.find('p').text("Give us a few seconds. We're provisioning your connection now.");
    provisionModal.modal('show');

    provisionCircuit(
      session.data.workgroup_id,
      document.querySelector('#header-description').textContent,
      this.circuit.endpoints,
      this.circuit.provision_time,
      this.circuit.remove_time,
      this.circuit.circuit_id
    ).then(function(result) {
      if (result !== null && result.success == 1) {
        window.location.href = `index.cgi?action=modify_l2vpn&circuit_id=${result.circuit_id}`;
      } else {
        provisionModal.modal('hide');
        console.error('There was an unexpected error provisioning the connection:', result);
        window.alert('There was an unexpected error provisioning the connection.');
      }
    }).catch(error => {
      provisionModal.modal('hide');
      console.error(`There was an error provisioning the connection: ${error}`);
      window.alert(`There was an error provisioning the connection: ${error}`);
    });
  }

  deleteCircuit() {
    if (!window.confirm(`Are you sure you want to delete "${this.circuit.description}"?`)) {
      return null;
    }

    let provisionModal = $('#modify-loading');
    provisionModal.find('p').text("Give us a few seconds. We're deleting your connection now.");
    provisionModal.modal('show');

    deleteCircuit(
      session.data.workgroup_id,
      this.circuit.circuit_id
    ).then(function(result) {
      if (result !== null) {
        window.location.href = 'index.cgi';
      }
      else {
        provisionModal.modal('hide');
        window.alert('There was an error deleting the connection.');
      }
    });
    return 1;
  }
}

$(function () {
  $('[data-toggle="popover"]').popover();
});

let state = new GlobalState();

let modal = new EndpointSelectionModal2('#add-endpoint-modal');

document.querySelector('.l2vpn-new-endpoint-button').addEventListener('click', function(e) {
  modal.display();
});

let circuitHeader = null;
let details = null;
let history = null;
let interfaceOptions = [];
let events = null;
let raw = null;

async function update(props) {
  let headerElem = document.querySelector('#circuit-header');
  let detailsElem = document.querySelector('#circuit-details');
  let historyElem = document.querySelector('#profile2');
  let eventsElem = document.querySelector('#messages2');
  let rawElem = document.querySelector('#settings2');

  let userMayEdit = session.data.isAdmin || (session.data.workgroup_id == state.circuit.workgroup_id && !session.data.isReadOnly);
  let connActive = state.circuit.state !== 'decom';
  let editable = connActive && userMayEdit;

  let newEndpointButton = document.querySelector('.l2vpn-new-endpoint-button-container');
  newEndpointButton.style.display = (editable) ? 'block' : 'none';

  [detailsElem.innerHTML, historyElem.innerHTML, eventsElem.innerHTML, rawElem.innerHTML, headerElem.innerHTML] = await Promise.all([
    details.render(state.circuit),
    history.render(state),
    events.render(state),
    raw.render(state),
    circuitHeader.render({connectionId: state.circuit.circuit_id, description: state.circuit.description, editable: editable, name: state.circuit.name})
  ]);

  let list = document.getElementById('endpoints');
  list.innerHTML = '';
  state.circuit.endpoints.map(function(e, i) {
    e.index = i;
    e.editable = editable;

    let elem = NewEndpoint(e);
    list.appendChild(elem);
  });

  addEditNameEvents(state.circuit.description);
}

document.addEventListener('DOMContentLoaded', async function() {
  await loadUserMenu();

  let url = new URL(window.location.href);
  let id = url.searchParams.get('circuit_id');

  state = new GlobalState();
  state.selectCircuit(id);

  if (id == ""){
    document.getElementById("connection_error").style.display = "block";
    document.getElementById("circuit2").style.display = "none";
  }

  console.log('GlobalState:', state);

  details = new CircuitDetails({workgroupID: session.data.workgroup_id});
  history = new CircuitHistory({workgroupID: session.data.workgroup_id});
  events = new CircuitEvents({workgroupID: session.data.workgroup_id});
  raw = new CircuitRaw({workgroupID: session.data.workgroup_id});
  circuitHeader = new CircuitHeader();

  getInterfaceOptions().then(options => {
    interfaceOptions = options;
  }).catch(error => {
    console.error(error);
  });

  let map = new NDDIMap('map');
  map.on("loaded", function(){
    this.updateMapFromSession(session);
  });
});
