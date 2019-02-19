class EndpointModal extends Component {
  constructor(state) {
    super();
    this.state = state;
  }

  async render(props) {
    return `
EndpointModal
`;
  }
}

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

        <div style="">
          <h3>Node:&nbsp;</h3>
          <h4>Port:&nbsp;</h4>
          <h5>VLAN:&nbsp;</h5>
        </div>

        <div style="">
          <h3>${props.node} <small></small></h3>
          <h4>${props.interface} <small>${props.interface_description}</small></h4>
          <h5>${props.tag}</h5>
        </div>

<iframe src="https://io3.bldc.grnoc.iu.edu/grafana/d-solo/te5oS11mk/oess-interface?refresh=30s&orgId=1&panelId=2&var-node=mx960-1.sdn-test.grnoc.iu.edu&var-interface=em0&from=now-1h&to=now" height="100" frameborder="0" style="flex: 1;"></iframe>

        <div>
          <button class="btn btn-link" type="button" onclick="state.selectEndpoint(${props.index});" style="padding: 12 6 12 6;">
            <span class="glyphicon glyphicon-edit"></span>
          </button>
          <button class="btn btn-link" type="button" onclick="state.deleteEndpoint(${props.index});" style="padding: 12 6 12 6;">
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
    let endpoints = props.endpoints.map((e, i) => {
      let obj = new Endpoint();
      e.index = i;
      return obj.render(e);
    }).join('');

    return `
    <div>
      ${endpoints}
    </div>
`;
  }
}
