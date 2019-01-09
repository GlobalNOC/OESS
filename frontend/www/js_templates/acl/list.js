class ACLList extends Component {
  constructor(state) {
    super();
    this.state = state;
  }

  async render(props) {
    let acls = await getACLs(props.interfaceID);
    let rows = acls.map((acl) => {
      return `
      <tr>
        <td style="white-space: nowrap; width:1%;">
          <button type="button" class="btn btn-default" onclick="document.components[${this._id}].state.onClickIncreasePriority(${acl.interface_acl_id}, ${acl.eval_position}, '${acl.allow_deny}', ${acl.vlan_start}, ${acl.vlan_end}, ${acl.workgroup_id}, ${acl.entity_id})">
            <span class="glyphicon glyphicon-chevron-up" aria-hidden="true"></span>
          </button>
          <button type="button" class="btn btn-default" onclick="document.components[${this._id}].state.onClickDecreasePriority(${acl.interface_acl_id}, ${acl.eval_position}, '${acl.allow_deny}', ${acl.vlan_start}, ${acl.vlan_end}, ${acl.workgroup_id}, ${acl.entity_id})">
            <span class="glyphicon glyphicon-chevron-down" aria-hidden="true"></span>
          </button>
        </td>
        <td>${acl.allow_deny}</td>
        <td>${acl.workgroup_name ? acl.workgroup_name : 'all'}</td>
        <td>${acl.entity_name}</td>
        <td>${acl.vlan_start}</td>
        <td>${acl.vlan_end}</td>
        <td style="white-space: nowrap; width:1%;">
          <button type="button" class="btn btn-default" onclick="document.components[${this._id}].state.onClickEdit(${acl.interface_acl_id})">
            <span class="glyphicon glyphicon-edit" aria-hidden="true"></span>
          </button>
          <button type="button" class="btn btn-default" onclick="document.components[${this._id}].state.onClickDelete(${acl.interface_acl_id})">
            <span class="glyphicon glyphicon-remove" aria-hidden="true"></span>
          </button>
        </td>
      </tr>
      `;
    }).join('');

    return `
    <button type="button" class="btn btn-success" onclick="document.components[${this._id}].state.onClickAdd(${props.interfaceID})">
      <span class="glyphicon glyphicon-plus" aria-hidden="true"></span> New ACL
    </button>

    <table class="table table-striped">
      <thead>
        <tr>
          <th></th>
          <th>State</th>
          <th>Workgroup</th>
          <th>Entity</th>
          <th>Low</th>
          <th>High</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        ${rows}
      </tbody>
    </table>
    `;
  }
}
