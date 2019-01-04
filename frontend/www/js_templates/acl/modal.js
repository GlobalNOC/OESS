class ACLModal extends Component {
  constructor(state) {
    super();
    this.state = state;

    this.state.aclID = -1;
    this.state.selectedWorkgroupID = -1;
    this.state.entityID = -1;
    this.state.allow = 'allow';
    this.state.high = -1;
    this.state.low = -1;
    this.state.notes = '';
  }

  saveACL(e) {
    console.log(this.state);
    $('#myModal').modal('hide');
  }

  setSelectedWorkgroupID(e) {
    this.state.selectedWorkgroupID = e.value;
  }

  setEntityID(e) {
    this.state.entityID = e.value;
  }

  setAllow(e) {
    this.state.allow = e.value;
  }

  setLow(e) {
    this.state.low = e.value;
  }

  setHigh(e) {
    this.state.high = e.value;
  }

  setNotes(e) {
    this.state.notes = e.value;
  }

  async render(props) {
    if (props.aclID < 0) {
      return `<div></div>`;
    }
    let acl = await getACL(props.aclID);
    this.state.aclID = acl.interface_acl_id;
    this.state.selectedWorkgroupID = acl.workgroup_id;
    this.state.entityID = acl.entity_id;
    this.state.allow = acl.allow_deny;
    this.state.high = acl.vlan_end;
    this.state.low = acl.vlan_start;
    this.state.notes = acl.notes || '';

    let workgroups = await getAllWorkgroups();
    let workgroupOptions = workgroups.map((w) => {
      if (this.state.selectedWorkgroupID === -1) {
        this.state.selectedWorkgroupID = w.workgroup_id;
      }
      let selected = w.workgroup_id == this.state.selectedWorkgroupID ? 'selected' : '';
      return `<option value="${w.workgroup_id}" ${selected}>${w.name}</option>`;
    }).join('');

    let entities = await getEntities(this.state.workgroupID);
    let entityOptions = entities.map((e) => {
      return `<option value="${e.entity_id}">${e.name}</option>`;
    }).join('');

    return `
      <div class="modal-dialog" role="document">
        <div class="modal-content">
          <div class="modal-header">
            <button type="button" class="close" data-dismiss="modal" aria-label="Close">
              <span aria-hidden="true">&times;</span>
            </button>
            <h4 class="modal-title">Modal title</h4>
          </div>
          <div class="modal-body">
            <p>Editing acl ${props.aclID}</p>
<form>
            <select onchange="document.components[${this._id}].setAllow(this)">
              <option>allow</option>
              <option>deny</option>
            </select>
            <select onchange="document.components[${this._id}].setSelectedWorkgroupID(this)">
              ${workgroupOptions}
            </select>
            <select onchange="document.components[${this._id}].setEntityID(this)">
              ${entityOptions}
            </select>
            <input type="number" value="${this.state.low}" oninput="document.components[${this._id}].setLow(this)"/>
            <input type="number" value="${this.state.high}" oninput="document.components[${this._id}].setHigh(this)"/>
            <input type="text" value="${this.state.notes}" oninput="document.components[${this._id}].setNotes(this)"/>
</form>
          </div>
          <div class="modal-footer">
            <button type="button" class="btn btn-default" data-dismiss="modal">Close</button>
            <button onclick="document.components[${this._id}].saveACL(this)" type="button" class="btn btn-primary">Save changes</button>
          </div>
        </div><!-- /.modal-content -->
      </div><!-- /.modal-dialog -->
    `;
  }
}
