import React from "react";
import ReactDOM from "react-dom";

import { Link } from "react-router-dom";

import { config } from '../../config.jsx';

import getUsers, { deleteUser } from '../../api/users.jsx';
import { PageContext } from "../../contexts/PageContext.jsx";
import { PageSelector } from '../../components/generic_components/PageSelector.jsx';
import { Table } from '../../components/generic_components/Table.jsx';

import "../../style.css";


class Users extends React.Component {
  constructor(props){
    super(props);
    this.state={
      pageNumber: 0,
      pageSize:   4,
      filter:     '',
      users:      []
    };

    this.filterUsers = this.filterUsers.bind(this);
    this.deleteUser = this.deleteUser.bind(this);
  }

  async componentDidMount() {
    try {
      let users = await getUsers();
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

  async deleteUser(user) {
    let ok = confirm(`Delete user '${user.usernames[0]}'?`);
    if (!ok) return;

    try {
      await deleteUser(user.user_id);
      this.context.setStatus({type:'success', message:`User '${user.usernames[0]}' was successfully deleted.`});
      this.setState((state) => {
        return {users: state.users.filter((u) => (u.user_id == user.user_id) ? false : true)};
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

      if ( (new RegExp(this.state.filter, 'i').test(d.last_name)) ) {
        return true;
      } else if ( (new RegExp(this.state.filter, 'i').test(d.first_name)) ) {
        return true;
      } else if ( (new RegExp(this.state.filter, 'i').test(d.email_address)) ) {
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

    const rowButtons = (data) => {
      if (config.third_party_mgmt == 1) {
        return <div></div>;
      }

      return (
        <div>
          <div className="btn-group">
            <Link to={`/users/${data.user_id}`} className="btn btn-default btn-xs">Edit User</Link>
            <button type="button" className="btn btn-default btn-xs dropdown-toggle" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false">
              <span>▾</span>{/* className="caret" doesn't work idk why */}
              <span className="sr-only">Toggle Dropdown</span>
            </button>
            <ul className="dropdown-menu" style={{fontSize: '12px'}}>
              <li><a href="#" onClick={() => this.deleteUser(data)}>Delete User</a></li>
            </ul>
          </div>
        </div>
      );
    };

    let columns = [
      { name: 'ID', key: 'user_id' },
      { name: 'First Name', key: 'first_name' },
      { name: 'Last Name', key: 'last_name' },
      { name: 'Email', key: 'email' },
      { name: 'Status', key: 'status' },
      { name: '', render: rowButtons, style: {textAlign: 'right'} }
    ];

    return (
      <div>
        <div>
          <p className="title"><b>Users</b></p>
          <p className="subtitle">Create, edit, or delete Users</p>
          <p>Third party mgmt {config.third_party_mgmt}</p>
        </div>
        <br />

        <form id="user_search_div" className="form-inline">
          <div className="form-group">
            <div className="input-group">
              <span className="input-group-addon" id="icon"><span className="glyphicon glyphicon-search" aria-hidden="true"></span></span>
              <input type="text" className="form-control" id="user_search" placeholder="Filter Users" aria-describedby="icon" onChange={(e) => this.filterUsers(e)} />
            </div>
          </div>
          { config.third_party_mgmt == 1 ? null : <Link to="/users/new" className="btn btn-default">Create User</Link> }
        </form>
        <br />

        <Table columns={columns} rows={users} />

        <center>
          <PageSelector pageNumber={this.state.pageNumber} pageSize={this.state.pageSize} itemCount={filteredItemCount} onChange={(i) => this.setState({pageNumber: i})} />
        </center>
      </div>
    );
  }
}
Users.contextType = PageContext;

export { Users };
