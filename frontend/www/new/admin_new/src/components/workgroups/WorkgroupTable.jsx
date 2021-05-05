import React from 'react';

import { WorkgroupModal } from './WorkgroupModal.jsx';
import { BaseModal } from '../generic_components/BaseModal.jsx';

class WorkgroupTable extends React.Component {
  constructor(props) {
    super(props);
    this.state = {
      visible: false,
      workgroup: null
    };
    // this.addUser = this.addUser.bind(this);
    // this.deleteWorkgroup = this.deleteWorkgroup.bind(this);
    // this.editWorkgroup = this.editWorkgroup.bind(this);
    // this.manageInterfaces = this.manageInterfaces.bind(this);
    // this.manageUsers = this.manageUsers.bind(this);
  }

  addUser(workgroup) {
    console.log('addUser', workgroup);
  }

  deleteWorkgroup(workgroup) {
    console.log('deleteWorkgroup', workgroup);
  }

  editWorkgroup(workgroup) {
    console.log('editWorkgroup', workgroup);
    this.setState({workgroup: workgroup, visible: true});
  }

  manageInterfaces(workgroup) {
    console.log('manageInterfaces', workgroup);
  }

  manageUsers(workgroup) {
    console.log('manageUsers', workgroup);
  }

  render() {
    // textAlign: right => move buttons to far right of table
    // fontSize: 12px => set text size to be in sync with button text size
    // margin: 4px 0 => set divider size to look more natural with 12px text

    let modalID = "modal-editWorkgroup";

    let rows = this.props.data.map((d, i) => {
      return (
        <tr key={i}>
          <td>{d.workgroup_id}</td>
          <td>{d.name}</td>
          <td>{d.type}</td>
          <td>{d.external_id}</td>
          <td style={{textAlign: 'right'}}>
            <button type="button" className="btn btn-default btn-xs" onClick={() => this.addUser(d)}>Add User</button>&nbsp;

            <div className="btn-group">
              <button type="button" className="btn btn-default btn-xs" onClick={() => this.editWorkgroup(d)}>
                Edit Workgroup
              </button>
              <button type="button" className="btn btn-default btn-xs dropdown-toggle" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false">
                <span>▾</span>{/* className="caret" doesn't work idk why */}
                <span className="sr-only">Toggle Dropdown</span>
              </button>
              <ul className="dropdown-menu" style={{fontSize: '12px'}}>
                <li><a href="#" onClick={() => this.deleteWorkgroup(d)}>Delete Workgroup</a></li>
                <li role="separator" className="divider" style={{margin: '4px 0'}}></li>
                <li><a href="#" onClick={() => this.manageInterfaces(d)}>Manage Interfaces</a></li>
                <li><a href="#" onClick={() => this.manageUsers(d)}>Manage Users</a></li>
              </ul>
            </div>
          </td>
        </tr>
      );
    });

    return (
      <div>
        <BaseModal visible={this.state.visible} header="Edit Workgroup" modalID={modalID} onClose={() => {this.setState({visible: false}); console.log(this.state); } }>
          <WorkgroupModal workgroup={this.state.workgroup} />
        </BaseModal>

        <table className="table table-striped">
          <thead>
            <tr>
              <th>ID</th>
              <th>Name</th>
              <th>Type</th>
              <th>External ID</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {rows}
          </tbody>
        </table>
      </div>
    );
  }
}

export { WorkgroupTable };
