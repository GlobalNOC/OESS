let editor;
let modal;

async function update(props) {
  props = {interfaceID: 148};

  let elem = document.querySelector('#acl-editor');
  let elem2 = document.querySelector('#myModal');

  [elem.innerHTML, elem2.innerHTML] = await Promise.all([
    editor.render(props),
    modal.render({aclID: editor.state.selectedACL})
  ]);
}

document.addEventListener('DOMContentLoaded', function() {
  loadUserMenu();

  editor = new ACLEditor({workgroupID: session.data.workgroup_id});
  modal = new ACLModal({workgroupID: session.data.workgroup_id});
  update();
});

class ACLEditor extends Component {
  constructor(state) {
    super();
    this.state = state;
    this.state.selectedACL = -1;

    this.list = new ACLList({
      workgroupID: this.state.workgroupID,
      onClickACL: this.showEditACLModal.bind(this)
    });
  }

  showEditACLModal(aclID) {
    console.log('showing modal for acl:', aclID);
    $('#myModal').modal('show');
    this.state.selectedACL = aclID;
    update();
  }

  hideEditACLModal() {
    console.log('hiding modal for acl');
    $('#myModal').modal('hide');
    this.state.selectedACL = -1;
    update();
  }

  async render(props) {
    let list = await this.list.render({interfaceID: props.interfaceID});

    return `
    <div>
      <p>Interface ${props.interfaceID} ACLs:</p>
      ${list}
    </div>
    `;
  }
}
