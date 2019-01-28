class Endpoint extends Component {
  constructor(state) {
    super();
    this.state = state;
  }

  render(props) {
    return `
    <div class="panel panel-default" style="padding-left: 15px;">
      <h3>${props.node} <small></small></h3>
      <h4>${props.interface} <small>${props.interface_description}</small></h4>
<h5>${props.tag}</h5>
<p></p>
    </div>
`;
  }
}

class EndpointList extends Component {
  constructor(state) {
    super();
    this.state = state;
  }

  async render(props) {
    let [circuit] = await Promise.all([
      getCircuit(props.id),
    ]);

    let endpoints = circuit.endpoints.map((e) => {
      let obj = new Endpoint();
      return obj.render(e);
    }).join('');

    return `
    <div>
      ${endpoints}
    </div>
`;
  }
}
