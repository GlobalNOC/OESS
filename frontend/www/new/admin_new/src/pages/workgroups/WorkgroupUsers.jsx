import React, { useContext, useState } from "react";
import { withRouter } from "react-router-dom";

import { getWorkgroupUsers } from '../../api/workgroup.js';
import { Table } from '../../components/generic_components/Table.jsx';

import "../../style.css";

export class WorkgroupUsers extends React.Component {
  constructor(props){
    super(props);
    this.state = {
        pageNumber: 0,
        pageSize:   4,
        filter:     '',
        users: []
    };

    this.filterUsers = this.filterUsers.bind(this);
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

    let columns = [
      { name: 'ID', key: 'user_id' },
      { name: 'First Name', key: 'first_name' },
      { name: 'Last Name', key: 'last_name' },
      { name: 'Email', key: 'email' },
      { name: 'Role', key: 'role' }
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
            <div class="input-group">
              <span class="input-group-addon" id="icon"><span class="glyphicon glyphicon-search" aria-hidden="true"></span></span>
              <input type="text" className="form-control" id="user_search" placeholder="Search by name or email" aria-describedby="icon" onChange={(e) => this.filterUsers(e)}/>
            </div>
          </div>
        </form>
        <br />

        <Table columns={columns} rows={users} />
      </div>
    );
  }
}
