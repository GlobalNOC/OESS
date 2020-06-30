import React from "react";
import ReactDOM from "react-dom";

import getCurrentUser from '../api/user_menu.jsx';

import { AdminNavBar } from "../components/nav_bar/AdminNavBar.jsx";
import NavBar from "../components/nav_bar/NavBar.jsx";

import { PageContextProvider } from '../contexts/PageContext.jsx';

import "../style.css";


import { getWorkgroups, getAllWorkgroups } from '../api/workgroup.js';

// import { WorkgroupTable } from '../components/workgroups/WorkgroupTable.jsx';
// import { WorkgroupModal } from '../components/workgroups/WorkgroupModal.jsx';
import { PageSelector } from '../components/generic_components/PageSelector.jsx';
import { BaseModal } from '../components/generic_components/BaseModal.jsx';

class Devices extends React.Component {
  constructor(props){
	super(props);
	this.state = {
      pageNumber: 0,
      pageSize:   2,
      filter:     '',
      devices: [],
      visible:    false
	};

    this.filterDevices = this.filterDevices.bind(this);
  }

  // async componentDidMount() {
  //   try {
  //     let devices = await getAllDevices();
  //     this.setState({ devices });
  //   } catch (error) {
  //     console.error(error);
  //   }
  // }

  filterDevices(e) {
    // Reset back the first table page when the filter is changed
    this.setState({
      filter:     e.target.value,
      pageNumber: 0
    });
  }

  render() {
    var currComponent = this;

    // https://developer.mozilla.org/en-US/docs/Web/API/URL_API
    // let url = new URL(document.location.href);
    // let device_id = url.searchParams.get('device_id');
    // console.log(url.pathname);

    let pageStart = this.state.pageSize * this.state.pageNumber;
    let pageEnd = pageStart + this.state.pageSize;
    let filteredItemCount = 0;

    let devices = this.state.devices.filter((d) => {
      if (!this.state.filter) {
        return true;
      }

      if ( (new RegExp(this.state.filter, 'i').test(d.name)) ) {
        return true;
      } else if ( (new RegExp(this.state.filter, 'i').test(d.external_id)) ) {
        return true;
      } else if ( this.state.filter == d.device_id ) {
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

    let modalID = "modal-addDevice";

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

            <BaseModal visible={this.state.visible} header="Create Device" modalID={modalID} onClose={() => this.setState({visible: false})}>
              <p>TODO</p>
              {/*<DeviceModal device={null} />*/}
            </BaseModal>


            <div>
              <p className="title"><b>Devices</b></p>
              <p className="subtitle">Create, edit, or delete Devices.</p>
            </div>
            <br />

            <form id="user_search_div" className="form-inline">
              <div className="form-group">
                <input type="text" className="form-control" id="device_search" placeholder="Device" onChange={(e) => this.filterDevices(e)}/>
              </div>
              <button type="button" className="btn btn-primary">Search</button>
              <button type="button" className="btn btn-default" onClick={() => this.setState({visible: true})}>Create Device</button>
            </form>
            <br />

            {/*<DeviceTable data={devices} filter={this.state.filter} pageNumber={this.state.pageNumber} pageSize={this.state.pageSize}/>*/}
            <center>
              <PageSelector pageNumber={this.state.pageNumber} pageSize={this.state.pageSize} itemCount={filteredItemCount} onChange={(i) => this.setState({pageNumber: i})} />
            </center>

          </div>
        </div>
      </PageContextProvider>
    );
  }
}

export { Devices };
