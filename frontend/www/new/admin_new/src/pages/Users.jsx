import React from "react";
import ReactDOM from "react-dom";

import { Link } from "react-router-dom";

import getUsers from '../api/users.jsx';
import { PageSelector } from '../components/generic_components/PageSelector.jsx';
import { Table } from '../components/generic_components/Table.jsx';

import "../style.css";


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
      return (
        <div>
          <div className="btn-group">
            <Link to={`/users/${data.user_id}`} className="btn btn-default btn-xs">Edit User</Link>
            <button type="button" className="btn btn-default btn-xs dropdown-toggle" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false">
              <span>▾</span>{/* className="caret" doesn't work idk why */}
              <span className="sr-only">Toggle Dropdown</span>
            </button>
            <ul className="dropdown-menu" style={{fontSize: '12px'}}>
              <li><a href="#" onClick={() => console.log('delUser', data)}>Delete User</a></li>
            </ul>
          </div>
        </div>
      );
    };

    let columns = [
      { name: 'ID', key: 'user_id' },
      { name: 'First Name', key: 'first_name' },
      { name: 'Last Name', key: 'family_name' },
      { name: 'Email', key: 'email_address' },
      { name: 'Status', key: 'status' },
      { name: '', render: rowButtons, style: {textAlign: 'right'} }
    ];

    return (
      <div>
        <div>
          <p className="title"><b>Users</b></p>
          <p className="subtitle">Add, remove, or update users.</p>
        </div>
        <br />

        <form id="user_search_div" className="form-inline">
          <div className="form-group">
            <input type="text" className="form-control" id="user_search" placeholder="Username" onChange={(e) => this.filterUsers(e)} />
          </div>
          <button type="button" className="btn btn-primary">Search</button>
          <Link to="/users/new" className="btn btn-default">Create User</Link>
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

export { Users };
