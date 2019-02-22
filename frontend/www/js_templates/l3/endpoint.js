class Endpoint extends Component {
  constructor(props) {
    super();
    this.props = props;
  }

  render() {
    console.log(this.props);

    let name = '';
    if (this.props.entity && this.props.entity !== 'NA') {
      name = `${this.props.entity} - <small>${this.props.node} ${this.props.name}.${this.props.tag}</small>`;
    } else {
      name = `${this.props.node} - <small>${this.props.name}.${this.props.tag}</small>`;
    }

    let peerings = this.props.peerings.map((peering, index) => {
      peering.index = index;
      peering.endpointIndex = this.props.index;
      peering.cloudAccountType = this.props.cloud_account_type;
      let p = new Peering(peering);
      return p.render();
    }).join('');

    console.log('endpoint:', this.props);

    let requiresRoutingInfo = this.props.cloud_account_type ? 'disabled' : 'required';
    let acceptsBGPKey = this.props.cloud_account_type ? 'disabled' : '';

    return `
    <div id="entity-${this.props.index}" class="panel panel-default">
      <div class="panel-heading">
        <h4 style="margin: 0px">
          ${name}
          <span style="float: right; margin-top: -5px;">
            <button class="btn btn-link" type="button" onclick="modifyNetworkEndpointCallback(${this.props.index})">
              <span class="glyphicon glyphicon-edit"></span>
            </button>
            <button class="btn btn-link" type="button" onclick="deleteNetworkEndpointCallback(${this.props.index})">
              <span class="glyphicon glyphicon-trash"></span>
            </button>
          </span>
        </h4>
      </div>
      <div class="table-responsive">
        <div id="endpoints">
          <table class="table">
            <thead>
              <tr><th></th><th>Your ASN</th><th>Your IP</th><th>Your BGP Key</th><th>OESS IP</th><th></th></tr>
            </thead>
            <tbody>
              ${peerings}
              <tr id="new-peering-form-${this.props.index}">
                <td>
                  <div class="checkbox"><label>
                    <input class="ip-version" type="checkbox" onchange="loadPeerFormValidator(${this.props.index})"> ipv6</input>
                  </label></div>
                </td>
                <td><input class="form-control bgp-asn"      type="number" ${requiresRoutingInfo} /></td>
                <td><input class="form-control your-peer-ip" type="text"   ${requiresRoutingInfo} /></td>
                <td><input class="form-control bgp-key"      type="text"   ${acceptsBGPKey      } /></td>
                <td><input class="form-control oess-peer-ip" type="text"   ${requiresRoutingInfo} /></td>
                <td>
                  <button class="btn btn-success btn-sm"
                          type="button"
                          onclick="newPeering(${this.props.index})">
                    &nbsp;<span class="glyphicon glyphicon-plus"></span>&nbsp;
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    `;
  }
}

class EndpointList {
  constructor(props) {
    this.props = props;
  }

  render() {
    let endpoints = this.props.endpoints.map((endpoint, index) => {
      endpoint.index = index;
      let e = new Endpoint(endpoint);
      return e.render();
    }).join('');

    return `<div>${endpoints}</div>`;
  }
}
