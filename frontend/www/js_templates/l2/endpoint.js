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

    this.state.onDelete = ('onDelete' in this.state) ? this.state.onDelete : () => { console.log('Endpoint.onDelete'); };
    this.state.onModify = ('onModify' in this.state) ? this.state.onModify : () => { console.log('Endpoint.onModify'); };
  }

  onDelete() {
    this.state.onDelete(this.state.index);
  }

  onModify() {
    this.state.onModify(this.state.index, this.state.endpoint);
  }

  render(props) {
    let handleDelete = `document.components[${this._id}].onDelete()`;
    let handleModify = `document.components[${this._id}].onModify()`;

    let displayEdits = (this.state.editable) ? 'block' : 'none';
    let height = '100';

    let title = `
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
`;
    if (props.entity && props.entity.name) {
      height = 130;
      title = `
      <div style="">
        <h3>Entity:&nbsp;</h3>
        <h4>Node:&nbsp;</h4>
        <h4>Port:&nbsp;</h4>
        <h5>VLAN:&nbsp;</h5>
      </div>

      <div style="">
        <h3>${props.entity.name} <small></small></h3>
        <h4>${props.node}</h4>
        <h4>${props.interface} <small>${props.interface_description}</small></h4>
        <h5>${props.tag}</h5>
      </div>
`;
    }

    return `
    <div class="panel panel-default" style="padding: 0 15 0 15;">

      <div style="display:flex; flex-direction: row; flex-wrap: nowrap;">
        ${title}

<iframe src="https://io3.bldc.grnoc.iu.edu/grafana/d-solo/te5oS11mk/oess-interface?refresh=30s&orgId=1&panelId=2&var-node=mx960-1.sdn-test.grnoc.iu.edu&var-interface=em0&from=now-1h&to=now" height="${height}" frameborder="0" style="flex: 1;"></iframe>

        <div style="display: ${displayEdits};">
          <button class="btn btn-link" type="button" onclick="${handleModify}" style="padding: 12 6 12 6;">
            <span class="glyphicon glyphicon-edit"></span>
          </button>
          <button class="btn btn-link" type="button" onclick="${handleDelete}" style="padding: 12 6 12 6;">
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

    this.state.onCreate = ('onCreate' in this.state) ? this.state.onCreate : () => { console.log('EndpointList.onCreate'); };
    this.state.onDelete = ('onDelete' in this.state) ? this.state.onDelete : () => { console.log('EndpointList.onDelete'); };
    this.state.onModify = ('onModify' in this.state) ? this.state.onModify : () => { console.log('EndpointList.onModify'); };
  }

  onCreate() {
    this.state.onCreate(-1);
  }

  async render(props) {
    let handleCreate = `document.components[${this._id}].onCreate()`;
    let displayEdits = (this.state.editable) ? 'block' : 'none';

    let endpoints = props.endpoints.map((e, i) => {
      e.index = i;

      let obj = new Endpoint({
        onDelete: this.state.onDelete,
        onModify: this.state.onModify,
        endpoint: e,
        editable: this.state.editable
      });

      return obj.render(e);
    }).join('');

    return `
    <div class="row">
      <br/>
      <div id="actions" class="col-sm-12" style="display: ${displayEdits};">
        <button class="btn-sm btn-primary" type="button" onclick="${handleCreate}">
          <span class="glyphicon glyphicon-plus"></span> New Endpoint
        </button>
      </div>
    </div>

    <div class="row">
      <br/>
      <div class="col-sm-12">
        ${endpoints}
      </div>
    </div>
`;
  }
}
