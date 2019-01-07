class InterfaceList extends Component {
  constructor(state) {
    super();
    this.state = state;
  }

  async render(props) {
    let intfs = await getInterfacesByWorkgroup(this.state.workgroupID);
    let rows = '';

    for (let i = 0; i < intfs.length; i++) {
      let intf = intfs[i];
      if (props.interfaceID == -1) {
        this.state.onSelectInterface(intf.interface_id);
        break;
      }

      let selected = '';
      if (intf.interface_id == props.interfaceID) {
        selected = 'info';
      }

      rows += `
      <tr class="${selected}" onclick="document.components[${this._id}].state.onSelectInterface(${intf.interface_id})">
        <td>${intf.node}</td>
        <td>${intf.name}</td>
      </tr>
      `;
    }

    return `
    <h2>Interface ACLs</h2>
    <table class="table table-striped">
      <thead>
        <tr>
          <th>Node</th>
          <th>Interface</th>
        </tr>
      </thead>
      <tbody>
        ${rows}
      </tbody>
    </table>
    `;
  }
}
