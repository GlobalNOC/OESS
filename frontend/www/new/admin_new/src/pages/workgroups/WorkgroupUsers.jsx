import React, { useContext, useState } from "react";

import { Link } from "react-router-dom";

import { config } from '../../config.jsx';

import { getWorkgroupUsers, modifyWorkgroupUser, removeWorkgroupUser } from '../../api/workgroup.js';
import { PageContext } from "../../contexts/PageContext.jsx";
import { Table } from '../../components/generic_components/Table.jsx';

import "../../style.css";

class WorkgroupUsers extends React.Component {
  constructor(props){
    super(props);
    this.state = {
        pageNumber: 0,
        pageSize:   4,
        filter:     '',
        users: []
    };

    this.filterUsers = this.filterUsers.bind(this);
    this.modifyWorkgroupUserHandler = this.modifyWorkgroupUserHandler.bind(this);
  }

  async componentDidMount() {
    try {
      let users = await getWorkgroupUsers(this.props.match.params["id"]);
      this.setState({ users });
    } catch (error) {
      console.error(error);
    }
  }

  filterUsers(e) {
    // Reset back the first table page when the filter is changed
    this.setState({
      filter:     e.target.value,
      pageNumber: 0
    });
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
    let ok = confirm(`Remove '${user.username}' from workgroup?`);
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
    let pageStart = this.state.pageSize * this.state.pageNumber;
    let pageEnd = pageStart + this.state.pageSize;
    let filteredItemCount = 0;

    let users = this.state.users.filter((d) => {
      if (!this.state.filter) {
        return true;
      }

      if ( (new RegExp(this.state.filter, 'i').test(d.first_name)) ) {
        return true;
      } else if ( (new RegExp(this.state.filter, 'i').test(d.last_name)) ) {
        return true;
      } else if ( (new RegExp(this.state.filter, 'i').test(d.email)) ) {
        return true;
      } else if ( this.state.filter == d.user_id ) {
        return true;
      } else {
        return false;
      }
    }).filter((d, i) => {
      // Any items not filtered by search are displayed and the count
      // of these are used to determine the number of table pages to
      // show.
      filteredItemCount += 1;

      if (i >= pageStart && i < pageEnd) {
        return true;
      } else {
        return false;
      }
    });

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

    return (
      <div>
        <div>
          <p className="title"><b>Workgroup Users</b></p>
          <p className="subtitle">Add, modify, or remove Workgroup Users.</p>
        </div>
        <br />

        <form id="user_search_div" className="form-inline">
          <div className="form-group">
            <div className="input-group">
              <span className="input-group-addon" id="icon"><span className="glyphicon glyphicon-search" aria-hidden="true"></span></span>
              <input type="text" className="form-control" id="user_search" placeholder="Filter Users" aria-describedby="icon" onChange={(e) => this.filterUsers(e)}/>
            </div>
          </div>
          { config.third_party_mgmt == 1 ? null : <Link to={`/workgroups/${this.props.match.params["id"]}/users/add`} className="btn btn-default">Add User</Link> }
        </form>
        <br />

        <Table columns={columns} rows={users} />
      </div>
    );
  }
}
WorkgroupUsers.contextType = PageContext;

export { WorkgroupUsers };
