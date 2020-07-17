import React from "react";
import ReactDOM from "react-dom";

import { Link } from "react-router-dom";

import "../../style.css";


import { getAllWorkgroups } from '../../api/workgroup.js';

import { WorkgroupForm } from '../../components/workgroups/WorkgroupForm.jsx';
import { PageSelector } from '../../components/generic_components/PageSelector.jsx';
import { BaseModal } from '../../components/generic_components/BaseModal.jsx';


import { Table } from '../../components/generic_components/Table.jsx';

class Workgroups extends React.Component {
  constructor(props){
	super(props);
	this.state = {
      pageNumber: 0,
      pageSize:   4,
      filter:     '',
      workgroup:  null,
      workgroups: [],
      visible:    false,
      editModalVisible: false
	};

    this.filterWorkgroups = this.filterWorkgroups.bind(this);
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

    let modalID = "modal-addWorkgroup";


    const rowButtons = (data) => {
      return (
        <div>
          <button type="button" className="btn btn-default btn-xs" onClick={() => console.log('add',data)}>Add User</button>&nbsp;
          <div className="btn-group">
            <button type="button" className="btn btn-default btn-xs" onClick={() => this.setState({editModalVisible: true, workgroup: data})}>
              Edit Workgroup
            </button>
              <button type="button" className="btn btn-default btn-xs dropdown-toggle" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false">
                <span>▾</span>{/* className="caret" doesn't work idk why */}
                <span className="sr-only">Toggle Dropdown</span>
              </button>
              <ul className="dropdown-menu" style={{fontSize: '12px'}}>
                <li><a href="#" onClick={() => console.log('delWg', data)}>Delete Workgroup</a></li>
                <li role="separator" className="divider" style={{margin: '4px 0'}}></li>
                <li><a href="#" onClick={() => console.log('manIntf', data)}>Manage Interfaces</a></li>
                <li><a href="#" onClick={() => console.log('manUsers', data)}>Manage Users</a></li>
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
        {/* <BaseModal visible={this.state.visible} header="Create Workgroup" modalID={modalID} onClose={() => this.setState({visible: false})}>
          <WorkgroupForm workgroup={null} />
        </BaseModal> */}

        {/*<BaseModal visible={this.state.editModalVisible} header="Edit Workgroup" modalID="modal-edit-workgroup" onClose={() => this.setState({editModalVisible: false})} >
          <WorkgroupModal workgroup={this.state.workgroup} />
        </BaseModal>*/}

        <div>
          <p className="title"><b>Workgroups</b></p>
          <p className="subtitle">Create, edit, or delete Workgroups.</p>
        </div>
        <br />

        <form id="user_search_div" className="form-inline">
          <div className="form-group">
            <input type="text" className="form-control" id="user_search" placeholder="Workgroup" onChange={(e) => this.filterWorkgroups(e)}/>
          </div>
          <button type="button" className="btn btn-primary">Search</button>
          <Link to="/workgroups/new" className="btn btn-default">Create Workgroup</Link>
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

export { Workgroups };
