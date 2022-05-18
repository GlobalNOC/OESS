
import React from 'react';

import { config } from '../.././config.jsx';

import NavBrand from './NavBrand';
import NavDropdown from './NavDropdown';
import NavLink from './NavLink';
import NavSeparator from './NavSeparator';

import { PageContext } from '../../contexts/PageContext';

import "./navbar.css";

export default class NavBar extends React.Component{
  constructor(props) {
    super(props);
  }

  render() {
    let user = this.context.user;
    let workgroup = this.context.workgroup;

    let path = config.base_url;

    let adminLink = null;
    if (user.is_admin == "1") {
      adminLink = <NavLink linkTo={`${path}/new/admin`} text="Admin" />;
    }

    let workgroupLinks = user.workgroups.map((workgroup, i) => {
      return <NavLink linkTo={'#'} key={i} text={workgroup.name} onClick={() => this.context.setWorkgroup(workgroup)} />;
    });

    console.log('pagecontext:', this.context);


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
            <NavBrand linkTo={path} src={`${path}/media/internet2-logo.png`} text={"Cloud Connect"} />
          </div>

          <div className="collapse navbar-collapse" id="navbar-collapse">
            <ul className="nav navbar-nav">
              <NavDropdown text="New Connection" user={user}>
                <NavLink linkTo={`${path}/index.cgi?action=provision_l2vpn`} text="Layer 2" />
                <NavLink linkTo={`${path}/index.cgi?action=provision_cloud`} text="Layer 3" />
              </NavDropdown>
              <NavLink linkTo={`${path}/index.cgi?action=phonebook`} text="Explore" />
              <NavLink linkTo={`${path}/index.cgi?action=acl`} text="Workgroup" />
            </ul>
            <ul className="nav navbar-nav navbar-right">
              {adminLink}
              <NavDropdown text={`${user.usernames[0]} / ${workgroup.name}`} user={user}>
                <NavLink linkTo={"#"}>
                  <b>{user.first_name} {user.last_name}</b><br/>
                  {user.username}<br/>
                  {user.email}
                </NavLink>
                <NavSeparator />
                {workgroupLinks}
              </NavDropdown>
            </ul>
          </div>

        </div>
      </nav>
    );
  }
}
NavBar.contextType = PageContext;
