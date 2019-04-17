class InterfaceForm extends Component {
  constructor(props) {
    super();
    this.props = {
      onCancel:          props.onCancel,
      onSubmit:          props.onSubmit,
      onInterfaceChange: props.onInterfaceChange
    };
  } 

  async render(props) {
    let interfaces = await getInterfacesByWorkgroup(session.data.workgroup_id);
    let interface_id = (interfaces.length === 0) ? -1 : interfaces[0].interface_id;

    let vlans = await getAvailableVLANs(session.data.workgroup_id, props.interface);
    if (vlans === []) {
      props.vlan = -1;
    } else if (!props.vlan) {
      props.vlan = vlans[0];
    } else if (!vlans.includes(props.vlan)) {
      vlans.unshift(props.vlan);
    }

    let sinterfaces = interfaces.map((intf) => {
      let selected = '';
      if (intf.interface_id == props.interface) {
        selected = 'selected';
      }
      return `<option value="${intf.interface_id}"
                      data-node="${intf.node}"
                      data-interface="${intf.name}"
                      data-entity="${intf.entity}"
                      data-entity_id="${intf.entity_id}"
                      ${selected}>
                ${intf.node} - ${intf.name}
              </option>`;
    }).join('');

    let svlans = vlans.map((vlan) => {
      let selected = '';
      if (vlan == props.vlan) {
        selected = 'selected';
      }
      return `<option value="${vlan}" ${selected}>${vlan}</option>`;
    }).join('');

    return `
    <div class="form-group">
      <label class="control-label">Interface</label>
      <select id="endpoint-select-interface"
              class="form-control"
              onchange="document.components[${this._id}].props.onInterfaceChange(this.value)"
              value="${props.interface}">
        ${sinterfaces}
      </select>
    </div>
    <div class="form-group">
      <label class="control-label">VLAN</label>
      <select id="endpoint-vlans"
              class="form-control"
              value="${props.vlan}">
        ${svlans}
      </select>
    </div>
    <div class="form-group">
      <label class="control-label">Max Bandwidth (Mb/s)</label>
      <input id="endpoint-bandwidth"
             class="form-control"
             type="number"
             placeholder="Unlimited"
             min="10"
             max="100000">
    </div>
    <div class="form-group">
      <input id="endpoint-index" class="form-control" type="hidden" value="-1">
    </div>
    <button id="add-endpoint-submit"
            class="btn btn-success"
            type="submit"
            onclick="document.components[${this._id}].props.onSubmit(this)"
            ${(props.interface == -1) ? 'disabled' : ''}>
      Add Endpoint
    </button>
    <button id="add-endpoint-cancel"
            class="btn btn-danger"
            type="button"
            onclick="document.components[${this._id}].props.onCancel(this)">
      Cancel
    </button>
    `;
  }
}
