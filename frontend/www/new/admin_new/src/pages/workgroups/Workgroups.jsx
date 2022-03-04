import React from "react";
import ReactDOM from "react-dom";

import { Link } from "react-router-dom";

import { config } from '../../config.jsx';

import { deleteWorkgroup, getAllWorkgroups } from '../../api/workgroup.js';
import { PageContext } from "../../contexts/PageContext.jsx";
import { PageSelector } from '../../components/generic_components/PageSelector.jsx';
import { Table } from '../../components/generic_components/Table.jsx';

import "../../style.css";


class Workgroups extends React.Component {
  constructor(props){
    super(props);
    this.state = {
        pageNumber: 0,
        pageSize:   4,
        filter:     '',
        workgroups: []
    };

    this.filterWorkgroups = this.filterWorkgroups.bind(this);
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

  filterWorkgroups(e) {
    // Reset back the first table page when the filter is changed
    this.setState({
      filter:     e.target.value,
      pageNumber: 0
    });
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
    let pageStart = this.state.pageSize * this.state.pageNumber;
    let pageEnd = pageStart + this.state.pageSize;
    let filteredItemCount = 0;

    let workgroups = this.state.workgroups.filter((d) => {
      if (!this.state.filter) {
        return true;
      }

      if ( (new RegExp(this.state.filter, 'i').test(d.name)) ) {
        return true;
      } else if ( (new RegExp(this.state.filter, 'i').test(d.external_id)) ) {
        return true;
      } else if ( this.state.filter == d.workgroup_id ) {
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
                <li><a href="#" onClick={() => this.deleteWorkgroup(data)}>Delete Workgroup</a></li>
                <li role="separator" className="divider" style={{margin: '4px 0'}}></li>
                {/* <li><Link to={`/workgroups/${data.workgroup_id}/interfaces`}>Manage Interfaces</Link></li> */}
                <li><Link to={`/workgroups/${data.workgroup_id}/users`}>Manage Users</Link></li>
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
          <p className="subtitle">Create, edit, or delete Workgroups.</p>
        </div>
        <br />

        <form id="user_search_div" className="form-inline">
          <div className="form-group">
            <div className="input-group">
              <span className="input-group-addon" id="icon"><span className="glyphicon glyphicon-search" aria-hidden="true"></span></span>
              <input type="text" className="form-control" id="user_search" placeholder="Filter Workgroups" aria-describedby="icon" onChange={(e) => this.filterWorkgroups(e)}/>
            </div>
          </div>
          { config.third_party_mgmt == 1 ? null : <Link to="/workgroups/new" className="btn btn-default">Create Workgroup</Link> }
        </form>
        <br />

        <Table columns={columns} rows={workgroups} />

        <center>
          <PageSelector pageNumber={this.state.pageNumber} pageSize={this.state.pageSize} itemCount={filteredItemCount} onChange={(i) => this.setState({pageNumber: i})} />
        </center>
      </div>
    );
  }
}
Workgroups.contextType = PageContext;

export { Workgroups };
