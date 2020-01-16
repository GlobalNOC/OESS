
import React from 'react';

import { testConfig } from '../.././test.jsx';

import NavBrand from './NavBrand';
import NavDropdown from './NavDropdown';
import NavLink from './NavLink';
import NavSeparator from './NavSeparator';

import "./navbar.css";

export default class NavBar extends React.Component{
  render() {
    let path = testConfig.user;
    let adminLink = null;
    if (this.props.data.is_admin == "1") {
      adminLink = <NavLink linkTo={`${path}/new/admin`} text="Admin" />;
    }

	return(
      <nav className="navbar navbar-inverse oess-navbar">
        <div className="container-fluid">

          <div className="navbar-header">
            <button type="button" className="navbar-toggle collapsed" data-toggle="collapse" data-target="#navbar-collapse" aria-expanded="false">
              <span className="sr-only">Toggle navigation</span>
              <span className="icon-bar"></span>
              <span className="icon-bar"></span>
              <span className="icon-bar"></span>
            </button>
            <NavBrand linkTo={`${path}/new/admin`} src={`${path}/media/internet2-logo.png`} text={"Cloud Connect"} />
          </div>

          <div className="collapse navbar-collapse" id="navbar-collapse">
            <ul className="nav navbar-nav">
              <NavDropdown text="New Connection" user={this.props.data}>
                <NavLink linkTo={`${path}/new/index.cgi?action=provision_l2vpn`} text="Layer 2" />
                <NavLink linkTo={`${path}/new/index.cgi?action=provision_cloud`} text="Layer 3" />
              </NavDropdown>
              <NavLink linkTo={`${path}/new/index.cgi?action=phonebook`} text="Explore" />
              <NavLink linkTo={`${path}/new/index.cgi?action=acl`} text="Workgroup" />
            </ul>
            <ul className="nav navbar-nav navbar-right">
              {adminLink}
              <NavDropdown text={`${this.props.data.username} / ${'workgroup'}`} user={this.props.data}>
                <NavLink linkTo={"#"}>
                  <b>{this.props.data.first_name} {this.props.data.last_name}</b><br/>
                  {this.props.data.username}<br/>
                  {this.props.data.email}
                </NavLink>
                <NavSeparator />
                <NavLink linkTo={`#`} text="Test" />
              </NavDropdown>
            </ul>
          </div>

        </div>
      </nav>
    );
  }
}
