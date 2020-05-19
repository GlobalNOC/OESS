import React from "react";
import ReactDOM from "react-dom";

import getCurrentUser from '../api/user_menu.jsx';

import { AdminNavBar } from "../components/nav_bar/AdminNavBar.jsx";
import ModalTemplate2 from '../components/generic_components/ModalTemplate2.jsx';
import NavBar from "../components/nav_bar/NavBar.jsx";
import UsersTable from "../components/user_table/UserTable.jsx";

import { PageContextProvider } from '../contexts/PageContext.jsx';

import "../style.css";


import { getWorkgroups, getAllWorkgroups } from '../api/workgroup.js';
import TableTemplate from '../components/generic_components/TableTemplate.jsx';

import { WorkgroupTable } from '../components/workgroups/WorkgroupTable.jsx';
import { WorkgroupModal } from '../components/workgroups/WorkgroupModal.jsx';
import { PageSelector } from '../components/generic_components/PageSelector.jsx';
import { BaseModal } from '../components/generic_components/BaseModal.jsx';

class Workgroups extends React.Component {
  constructor(props){
	super(props);
	this.state = {
      pageNumber: 0,
      pageSize:   2,
      filter:     '',
      workgroups: [],
      visible:    false
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
    var currComponent = this;

    // https://developer.mozilla.org/en-US/docs/Web/API/URL_API
    let url = new URL(document.location.href);
    let workgroup_id = url.searchParams.get('workgroup_id');
    console.log(url.pathname);

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

    return (
      <PageContextProvider>




        <div className="oess-page-container">
          <div className="oess-page-navigation">
            <NavBar />
          </div>

          <div className="oess-side-navigation">
            <AdminNavBar />
          </div>

          <div className="oess-page-content">


            <BaseModal visible={this.state.visible} header="Create Workgroup" modalID={modalID} onClose={() => this.setState({visible: false})}>
              <WorkgroupModal workgroup={null} />
            </BaseModal>


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
              <button type="button" className="btn btn-default" onClick={() => this.setState({visible: true})}>Create Workgroup</button>
            </form>
            <br />

            <WorkgroupTable data={workgroups} filter={this.state.filter} pageNumber={this.state.pageNumber} pageSize={this.state.pageSize}/>
            <center>
              <PageSelector pageNumber={this.state.pageNumber} pageSize={this.state.pageSize} itemCount={filteredItemCount} onChange={(i) => this.setState({pageNumber: i})} />
            </center>

          </div>
        </div>
      </PageContextProvider>
    );
  }
}

let mountNode = document.getElementById("app");
ReactDOM.render(<Workgroups />, mountNode);
