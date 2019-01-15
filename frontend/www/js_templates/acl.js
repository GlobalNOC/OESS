class GlobalState extends Component {
  constructor(state) {
    super();
    this.selectedInterface = -1;
    this.selectedACL = -1;

    this.selectInterface = this.selectInterface.bind(this);
    this.selectACL = this.selectACL.bind(this);
  }

  selectInterface(id) {
    this.selectedInterface = id;
    update();
  }

  selectACL(id) {
    this.selectedACL = id;
    update();
  }
}

let state = new GlobalState();

let editor;
let modal;
let intfList;

async function update(props) {
  let elem = document.querySelector('#acl-editor');
  let elem2 = document.querySelector('#myModal');
  let elem3 = document.querySelector('#interface-list');

  [elem.innerHTML, elem2.innerHTML, elem3.innerHTML] = await Promise.all([
    editor.render({interfaceID: state.selectedInterface}),
    modal.render({aclID: state.selectedACL, interfaceID: state.selectedInterface}),
    intfList.render({interfaceID: state.selectedInterface})
  ]);
}

document.addEventListener('DOMContentLoaded', function() {
  loadUserMenu();

  intfList = new InterfaceList({
    onSelectInterface: state.selectInterface,
    workgroupID:       session.data.workgroup_id
  });
  editor = new ACLEditor({
    onSelectACL: state.selectACL,
    workgroupID: session.data.workgroup_id
  });
  modal = new ACLModal({
    workgroupID: session.data.workgroup_id
  });

  update();
});
