class GlobalState extends Component {
  constructor(state) {
    super();
    this.id = -1;
  }

  selectCircuit(id) {
    this.id = id;
    update();
  }
}

let state = new GlobalState();

let circuit = null;
let circuitHeader = null;
let endpointList = null;

async function update(props) {
  let elem = document.querySelector('#circuit');
  let headerElem = document.querySelector('#circuit-header');
  let epointListElem = document.querySelector('#endpoints');

  [elem.innerHTML, headerElem.innerHTML, epointListElem.innerHTML] = await Promise.all([
    circuit.render({id: state.id}),
    circuitHeader.render({id: state.id}),
    endpointList.render({id: state.id})
  ]);
}

document.addEventListener('DOMContentLoaded', function() {
  loadUserMenu();

  let url = new URL(window.location.href);
  let id = url.searchParams.get('vrf_id');

  circuit = new Circuit({workgroupID: session.data.workgroup_id});
  circuitHeader = new CircuitHeader({workgroupID: session.data.workgroiup_id});
  endpointList = new EndpointList({workgroupID: session.data.workgroiup_id});

  state = new GlobalState();
  state.selectCircuit(id);

  let map = new NDDIMap('map');
  map.on("loaded", function(){
    this.updateMapFromSession(session);
  });
});
