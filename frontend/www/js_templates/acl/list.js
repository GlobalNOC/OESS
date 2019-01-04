class ACLList extends Component {
  constructor(state) {
    super();
    this.state = state;
  }

  async render(props) {
    let acls = await getACLs(props.interfaceID);
    let rows = acls.map((acl) => {
      return `
      <tr onClick="document.components[${this._id}].state.onClickACL(${acl.interface_acl_id})">
        <td>${acl.allow_deny}</td>
        <td>${acl.workgroup_name ? acl.workgroup_name : 'all'}</td>
        <td>${acl.entity_name}</td>
        <td>${acl.vlan_start}</td>
        <td>${acl.vlan_end}</td>
      </tr>
      `;
    }).join('');

    return `
    <table class="table table-striped">
      <thead>
        <tr>
          <th>State</th>
          <th>Workgroup</th>
          <th>Entity</th>
          <th>Low</th>
          <th>High</th>
        </tr>
      </thead>
      <tbody>
        ${rows}
      </tbody>
    </table>
    `;
  }
}
