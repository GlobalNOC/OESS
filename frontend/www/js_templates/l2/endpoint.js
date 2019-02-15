class Endpoint extends Component {
  constructor(state) {
    super();
    this.state = state;
  }


  // modifyNetworkEndpointCallback(${this.props.index})
  render(props) {
    return `
    <div class="panel panel-default" style="padding: 0 15 0 15;">

      <div style="display:flex; flex-direction: row; flex-wrap: nowrap;">
        <div style="flex: 1;">
          <h3>${props.node} <small></small></h3>
          <h4>${props.interface} <small>${props.interface_description}</small></h4>
          <h5>${props.tag}</h5>
        </div>

        <div>
          <button class="btn btn-link" type="button" onclick="" style="padding: 12 6 12 6;">
            <span class="glyphicon glyphicon-edit"></span>
          </button>
          <button class="btn btn-link" type="button" onclick="" style="padding: 12 6 12 6;">
            <span class="glyphicon glyphicon-trash"></span>
          </button>
        </div>
      </div>

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
