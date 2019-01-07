class ACLModal extends Component {
  constructor(state) {
    super();
    this.state = state;

    this.state.aclID = -1;
    this.state.selectedWorkgroupID = -1;
    this.state.entityID = -1;
    this.state.allow = 'allow';
    this.state.high = 4095;
    this.state.low = 2;
    this.state.notes = '';
    this.state.position = 10;
  }

  saveACL(e) {
    if (this.state.aclID === -1) {
      console.log(this.state);

      addACL(this.state).then(() => {
        update();
        $('#myModal').modal('hide');        
      });
    } else {
      modifyACL(this.state).then(() => {
        update();
        $('#myModal').modal('hide');
      });
    }
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
    let acl = null;
    let entities = [];
    let workgroups = [];

    if (props.aclID === -1) {
      [workgroups, entities] = await Promise.all([
        getAllWorkgroups(),
        getEntitiesAll(this.state.workgroupID)
      ]);

      this.state.aclID = -1;
      this.state.selectedWorkgroupID = -1;
      this.state.entityID = -1;
      this.state.allow = 'allow';
      this.state.high = 4095;
      this.state.low = 2;
      this.state.notes = '';
      this.state.position = 10;

      this.state.interfaceID = props.interfaceID;
    } else {
      [acl, workgroups, entities] = await Promise.all([
        getACL(props.aclID),
        getAllWorkgroups(),
        getEntitiesAll(this.state.workgroupID)
      ]);
      console.log(acl);

      this.state.aclID = acl.interface_acl_id;
      this.state.selectedWorkgroupID = acl.workgroup_id || -1;
      this.state.entityID = acl.entity_id;
      this.state.allow = acl.allow_deny;
      this.state.high = acl.vlan_end;
      this.state.low = acl.vlan_start;
      this.state.notes = acl.notes || '';
      this.state.position = acl.eval_position;
      this.state.interfaceID = acl.interface_id;
    }
    workgroups.unshift({workgroup_id: -1, name: 'all'});

    let workgroupOptions = workgroups.map((w) => {
      let selected = w.workgroup_id == this.state.selectedWorkgroupID ? 'selected' : '';
      return `<option value="${w.workgroup_id}" ${selected}>${w.name}</option>`;
    }).join('');

    let entityOptions = entities.map((e) => {
      if (this.state.entityID === -1) {
        this.state.entityID = e.entity_id;
      }
      let selected = e.entity_id == this.state.entityID ? 'selected' : '';
      return `<option value="${e.entity_id}" ${selected}>${e.name}</option>`;
    }).join('');

    return `
      <div class="modal-dialog" role="document">
        <div class="modal-content">
          <div class="modal-header">
            <button type="button" class="close" data-dismiss="modal" aria-label="Close">
              <span aria-hidden="true">&times;</span>
            </button>
            <h4 class="modal-title">Edit ACL <small>${props.aclID}</small></h4>
          </div>
          <div class="modal-body">
            <form>
              <div class="form-group">
                <label for="allowdeny">Allow / Deny</label><br/>
                <select id="allowdeny" class="form-control" onchange="document.components[${this._id}].setAllow(this)">
                  <option>allow</option>
                  <option>deny</option>
                </select>
              </div>
              <div class="form-group">
                <label for="workgroup">Workgroup</label><br/>
                <select id="workgroup" class="form-control" onchange="document.components[${this._id}].setSelectedWorkgroupID(this)">
                  ${workgroupOptions}
                </select>
              </div>
              <div class="form-group">
                <label for="entity">Entity</label><br/>
                <select id="entity" class="form-control" onchange="document.components[${this._id}].setEntityID(this)">
                  ${entityOptions}
                </select>
              </div>
              <div class="form-group">
                <label for="low">Low</label><br/>
                <input id="low" class="form-control" type="number" value="${this.state.low}" oninput="document.components[${this._id}].setLow(this)"/>
              </div>
              <div class="form-group">
                <label for="high">High</label><br/>
                <input id="high" class="form-control" type="number" value="${this.state.high}" oninput="document.components[${this._id}].setHigh(this)"/>
              </div>
              <div class="form-group">
                <label for="notes">Notes</label><br/>
                <textarea id="notes" class="form-control" rows="3" value="${this.state.notes}" oninput="document.components[${this._id}].setNotes(this)"></textarea>
              </div>
            </form>
          </div>
          <div class="modal-footer">
            <button type="button" class="btn btn-default" data-dismiss="modal">Close</button>
            <button onclick="document.components[${this._id}].saveACL(this)" type="button" class="btn btn-primary">
              ${acl === null ? 'Create ACL' : 'Save changes'}
            </button>
          </div>
        </div><!-- /.modal-content -->
      </div><!-- /.modal-dialog -->
    `;
  }
}
