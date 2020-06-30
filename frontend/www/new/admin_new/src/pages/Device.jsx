import React from "react";
import ReactDOM from "react-dom";

import { getDevice } from '../api/devices.jsx';

import { AdminNavBar } from "../components/nav_bar/AdminNavBar.jsx";
import NavBar from "../components/nav_bar/NavBar.jsx";

import { PageContextProvider } from '../contexts/PageContext.jsx';

import "../style.css";

import { BaseModal } from '../components/generic_components/BaseModal.jsx';

class Device extends React.Component {
  constructor(props){
	super(props);
	this.state = {
      device: null
	};
  }

  async componentDidMount() {
    try {
      let device = await getDevice(this.props.match.params["id"]);
      this.setState({ device });
    } catch (error) {
      console.error(error);
    }
  }

  render() {

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

            <div>
              <p className="title"><b>Device</b></p>
              <p className="subtitle">Edit or delete Device.</p>
            </div>
            <br />

            {this.state.device ? JSON.stringify(this.state.device) : ''}

          </div>
        </div>
      </PageContextProvider>
    );
  }
}

export { Device };
