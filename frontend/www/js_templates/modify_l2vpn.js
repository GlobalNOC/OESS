class GlobalState extends Component {
  constructor(state) {
    super();
    this.id = -1;
    this.selectedEndpoint = -1;
  }

  async selectCircuit(id) {
    this.id = id;

    [this.circuit, this.history, this.events, this.raw] = await Promise.all([
      getCircuit(id),
      getCircuitHistory(id),
      getCircuitEvents(id),
      getRawCircuit(id)
    ]);

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
    console.log('saveCircuit:', this.circuit);
    provisionCircuit(
      session.data.workgroup_id,
      this.circuit.description,
      this.circuit.endpoints,
      this.circuit.static_mac,
      this.circuit.provision_time,
      this.circuit.remove_time,
      this.circuit.circuit_id
    ).then(function(result) {
      if (result !== null && result.success == 1) {
        window.location.href = `index.cgi?action=modify_l2vpn&circuit_id=${result.circuit_id}`;
      }
    });
  }

  deleteCircuit() {
    if (!window.confirm('Are you sure you wish to remove this circuit?')) {
      return null;
    }

    deleteCircuit(
      session.data.workgroup_id,
      this.circuit.circuit_id
    ).then(function(result) {
      if (result !== null) {
        window.location.href = 'index.cgi';
      }
    });
  }
}

let state = new GlobalState();


let circuitHeader = null;
let endpointList = null;
let details = null;
let history = null;
let events = null;
let raw = null;
let endpointModal = null;

async function update(props) {
  let headerElem = document.querySelector('#circuit-header');
  let epointListElem = document.querySelector('#endpoints');
  let detailsElem = document.querySelector('#circuit-details');
  let historyElem = document.querySelector('#profile2');
  let eventsElem = document.querySelector('#messages2');
  let rawElem = document.querySelector('#settings2');
  let endpointModalElem = document.querySelector('#add-endpoint-modal');

  [detailsElem.innerHTML, historyElem.innerHTML, eventsElem.innerHTML, rawElem.innerHTML, headerElem.innerHTML, epointListElem.innerHTML, endpointModalElem.innerHTML] = await Promise.all([
    details.render(state.circuit),
    history.render(state),
    events.render(state),
    raw.render(state),
    circuitHeader.render(state.circuit),
    endpointList.render(state.circuit),
    endpointModal.render(state.circuit.endpoints[state.selectedEndpoint] || {})
  ]);
}

document.addEventListener('DOMContentLoaded', function() {
  loadUserMenu();

  let url = new URL(window.location.href);
  let id = url.searchParams.get('circuit_id');

  let editable = (session.data.isAdmin || !session.data.isReadOnly);

  state = new GlobalState();
  console.log('GlobalState:', state);

  details = new CircuitDetails({workgroupID: session.data.workgroup_id});
  history = new CircuitHistory({workgroupID: session.data.workgroup_id});
  events = new CircuitEvents({workgroupID: session.data.workgroup_id});
  raw = new CircuitRaw({workgroupID: session.data.workgroup_id});

  circuitHeader = new CircuitHeader({
    workgroupID: session.data.workgroiup_id,
    editable: editable
  });
  endpointList = new EndpointList({
    workgroupID: session.data.workgroiup_id,
    editable: editable,
    onCreate: state.selectEndpoint.bind(state),
    onDelete: state.deleteEndpoint.bind(state),
    onModify: state.selectEndpoint.bind(state)
  });

  endpointModal = new EndpointSelectionModal({
    workgroupID: session.data.workgroiup_id,
    interface: -1,
    vlan: 1,
    onEndpointSubmit: state.updateEndpoint.bind(state)
  });

  state.selectCircuit(id);

  let map = new NDDIMap('map');
  map.on("loaded", function(){
    this.updateMapFromSession(session);
  });
});
