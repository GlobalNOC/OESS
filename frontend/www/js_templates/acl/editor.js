class ACLEditor extends Component {
  constructor(state) {
    super();
    this.state = state;

    this.list = new ACLList({
      workgroupID:   this.state.workgroupID,
      onClickAdd:    this.showAddACLModal.bind(this),
      onClickEdit:   this.showEditACLModal.bind(this),
      onClickDelete: this.confirmAndDeleteACL.bind(this),
      onClickIncreasePriority: this.increaseACLPriority.bind(this),
      onClickDecreasePriority: this.decreaseACLPriority.bind(this)
    });
  }

  showAddACLModal(interfaceID) {
    $('#myModal').modal('show');
    this.state.onSelectACL(-1);
  }

  showEditACLModal(aclID) {
    $('#myModal').modal('show');
    this.state.onSelectACL(aclID);
  }

  hideEditACLModal() {
    $('#myModal').modal('hide');
    this.state.onSelectACL(-1);
  }

  confirmAndDeleteACL(id) {
    let ok = confirm("You are about to remove an acl. This CANNOT be undone! Are you sure you want to proceed?");
    if (!ok) {
      return false;
    }

    deleteACL(id).then((ok) => {
      this.state.onSelectACL(-1);
    });
    return true;
  }

  increaseACLPriority(id, position, allow_deny, low, high, workgroupID, entityID) {
    modifyACL({
      aclID: id,
      position: position - 10,
      low: low,
      high: high,
      allow: allow_deny,
      selectedWorkgroupID: workgroupID,
      entityID: entityID
    }).then((ok) => {
      this.state.onSelectACL(-1);
    });
  }

  decreaseACLPriority(id, position, allow_deny, low, high, workgroupID, entityID) {
    console.log('down', position);
    modifyACL({
      aclID: id,
      position: position + 10,
      low: low,
      high: high,
      allow: allow_deny,
      selectedWorkgroupID: workgroupID,
      entityID: entityID
    }).then((ok) => {
      this.state.onSelectACL(-1);
    });
  }

  async render(props) {
    let list = await this.list.render({interfaceID: props.interfaceID});

    return `
    <div>
      ${list}
    </div>
    `;
  }
}
