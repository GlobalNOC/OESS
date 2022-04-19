import React from "react";

import { Link } from "react-router-dom";

import { config } from '../../config.jsx';

import { deleteWorkgroup, getAllWorkgroups } from '../../api/workgroup.js';
import { PageContext } from "../../contexts/PageContext.jsx";
import { CustomTable } from "../../components/generic_components/CustomTable.jsx";

import "../../style.css";


class Workgroups extends React.Component {
  constructor(props){
    super(props);
    this.state = {
        workgroups: []
    };

    this.deleteWorkgroup = this.deleteWorkgroup.bind(this);
  }

  async componentDidMount() {
    try {
      let workgroups = await getAllWorkgroups();
      this.setState({ workgroups });
    } catch (error) {
      console.error(error);
    }
  }

  async deleteWorkgroup(workgroup) {
    let ok = confirm(`Delete workgroup '${workgroup.name}'?`);
    if (!ok) return;

    try {
      await deleteWorkgroup(workgroup.workgroup_id);
      this.context.setStatus({type:'success', message:`Workgroup '${workgroup.name}' was successfully deleted.`});
      this.setState((state) => {
        return {workgroups: state.workgroups.filter((w) => (w.workgroup_id == workgroup.workgroup_id) ? false : true)};
      });
    } catch (error) {
      this.context.setStatus({type:'error', message:error.toString()});
    }
  }

  render() {
    const rowButtons = (data) => {
      if (config.third_party_mgmt == 1) {
        return (
          <div>
            <Link to={`/workgroups/${data.workgroup_id}/users`} className="btn btn-default btn-xs">Manage Users</Link>
          </div>
        );
      }

      return (
        <div>
          <Link to={`/workgroups/${data.workgroup_id}/users/add`} className="btn btn-default btn-xs">Add User</Link>&nbsp;
          <div className="btn-group">
              <Link to={`/workgroups/${data.workgroup_id}`} className="btn btn-default btn-xs">Edit Workgroup</Link>
              <button type="button" className="btn btn-default btn-xs dropdown-toggle" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false">
                <span>▾</span>{/* className="caret" doesn't work idk why */}
                <span className="sr-only">Toggle Dropdown</span>
              </button>
              <ul className="dropdown-menu" style={{fontSize: '12px'}}>
                {/* <li><Link to={`/workgroups/${data.workgroup_id}/interfaces`}>Manage Interfaces</Link></li> */}
                <li><Link to={`/workgroups/${data.workgroup_id}/users`}>Manage Users</Link></li>
                <li role="separator" className="divider" style={{margin: '4px 0'}}></li>
                <li><a href="#" onClick={() => this.deleteWorkgroup(data)}>Delete Workgroup</a></li>
              </ul>
            </div>
        </div>
      );
    };

    let columns = [
      { name: 'ID', key: 'workgroup_id' },
      { name: 'Name', key: 'name' },
      { name: 'Type', key: 'type' },
      { name: 'External ID', key: 'external_id' },
      { name: '', render: rowButtons, style: {textAlign: 'right'} }
    ];

    return (
      <div>
        <div>
          <p className="title"><b>Workgroups</b></p>
          <p className="subtitle">Create, edit, or delete Workgroups</p>
        </div>
        <br />

        <CustomTable columns={columns} rows={this.state.workgroups} size={15} filter={['workgroup_id', 'name', 'external_id']}>
          { config.third_party_mgmt == 1 ? null : <CustomTable.MenuItem><Link to="/workgroups/new" className="btn btn-default">Create Workgroup</Link></CustomTable.MenuItem> }
        </CustomTable>
      </div>
    );
  }
}
Workgroups.contextType = PageContext;

export { Workgroups };
