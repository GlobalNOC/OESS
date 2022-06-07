import React, { useContext, useState } from "react";

import { Link } from "react-router-dom";

import { config } from '../../config.jsx';

import { getWorkgroupUsers, modifyWorkgroupUser, removeWorkgroupUser } from '../../api/workgroup.js';
import { PageContext } from "../../contexts/PageContext.jsx";
import { CustomTable } from '../../components/generic_components/CustomTable.jsx';

import "../../style.css";

class WorkgroupUsers extends React.Component {
  constructor(props) {
    super(props);
    this.state = {
        users: []
    };

    this.modifyWorkgroupUserHandler = this.modifyWorkgroupUserHandler.bind(this);
    this.removeWorkgroupUserHandler = this.removeWorkgroupUserHandler.bind(this);
  }

  async componentDidMount() {
    try {
      let users = await getWorkgroupUsers(this.props.match.params["id"]);
      this.setState({ users });
    } catch (error) {
      console.error(error);
    }
  }

  async modifyWorkgroupUserHandler(user, role) {
    try {
      await modifyWorkgroupUser(this.props.match.params["id"], user.user_id, role);
      this.context.setStatus({type:'success', message:`${user.usernames[0]}'s role was successfully set to '${role}'.`});
    } catch (error) {
      this.context.setStatus({type:'error', message:error.toString()});
    }
  };

  async removeWorkgroupUserHandler(user) {
    let ok = confirm(`Remove '${user.usernames[0]}' from workgroup?`);
    if (!ok) return;

    try {
      await removeWorkgroupUser(this.props.match.params["id"], user.user_id);
      this.context.setStatus({type:'success', message:`${user.usernames[0]} successfully removed from workgroup.`});
      this.setState((state) => {
        return { users: state.users.filter(u => u.user_id != user.user_id) };
      });
    } catch (error) {
      this.context.setStatus({type:'error', message:error.toString()});
    }
  }

  render() {
    const roleSelect = (data) => {
      return (
        <select className="form-control input-sm" style={{height: '22px', padding: '1px 5px'}} defaultValue={data.role} disabled={config.third_party_mgmt == 1} onChange={(e) => this.modifyWorkgroupUserHandler(data, e.target.value)}>
          <option value="read-only">Read-Only</option>
          <option value="normal">Normal</option>
          <option value="admin">Admin</option>
        </select>
      )
    };

    const rowButtons = (data) => {
      if (config.third_party_mgmt == 1) {
        return <div></div>;
      }
      return <button type="button" className="btn btn-default btn-xs" onClick={(e) => this.removeWorkgroupUserHandler(data)}>Remove User</button>;
    }

    let columns = [
      { name: 'ID', key: 'user_id' },
      { name: 'First Name', key: 'first_name' },
      { name: 'Last Name', key: 'last_name' },
      { name: 'Email', key: 'email' },
      { name: 'Role', render: roleSelect, style: {width: '9em'} },
      { name: '', render: rowButtons, style: {textAlign: 'right'} }
    ];

    let addUserButton = (
      <CustomTable.MenuItem>
        <Link to={`/workgroups/${this.props.match.params["id"]}/users/add`} className="btn btn-default">Add User</Link>
      </CustomTable.MenuItem>
    );
    if (config.third_party_mgmt == 1) {
      addUserButton = null;
    }

    return (
      <div>
        <div>
          <p className="title"><b>Workgroup Users</b></p>
          <p className="subtitle">Add, modify, or remove Workgroup Users.</p>
        </div>
        <br />

        <CustomTable columns={columns} rows={this.state.users} filter={['first_name', 'last_name', 'email']}>
          {addUserButton}
        </CustomTable>
      </div>
    );
  }
}
WorkgroupUsers.contextType = PageContext;

export { WorkgroupUsers };
