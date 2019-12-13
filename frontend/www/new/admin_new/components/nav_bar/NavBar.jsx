import React, { Component } from 'react';
import NavBrand from './NavBrand.jsx';
import NavMenu from './NavMenu.jsx';
import NavMenuRight from './NavMenuRight.jsx';
import { testConfig } from '../.././test.jsx';

export default class NavBar extends React.Component{
	constructor(props) {
        	super(props);
        	this.state = {
		}
	}

	render(){

	var navbar = {};
	let path = testConfig.user;
	navbar.brand = {linkTo: path+"new/index.cgi", src: path+'media/internet2-logo.png', text: "Cloud Connect"};
	navbar.links = [
		{dropdown: true, text: "New Connections", links: [
   			 {linkTo: path+"new/index.cgi?action=provision_l2vpn", text: "Layer 1"},
    			 {linkTo: path+"new/index.cgi?action=provision_cloud", text: "Layer 2"}
  		]},
  		{linkTo: path+"new/index.cgi?action=phonebook", text: "Explore"},
		{linkTo: path+"new/index.cgi?action=acl", text: "Workgroup"}
	];
	navbar.admin = [
		{linkTo: "#", is_admin: true, text: "Admin"}
	]
	navbar.login = [
		
	];


	return(
      <nav className="navbar navbar-inverse">
        <div className="container-fluid">
          <div className="navbar-header">
            <button type="button" className="navbar-toggle collapsed" data-toggle="collapse" data-target="#navbar-collapse" aria-expanded="false">
              <span className="sr-only">Toggle navigation</span>
              <span className="icon-bar"></span>
              <span className="icon-bar"></span>
              <span className="icon-bar"></span>
            </button>
            <NavBrand linkTo={navbar.brand.linkTo} src={navbar.brand.src} text={navbar.brand.text} />
          </div>
          <div className="collapse navbar-collapse" id="navbar-collapse">
            <NavMenu links={navbar.links} />
	    <NavMenuRight links={navbar.admin} />
          </div>
        </div>
      </nav>
    );
  }
 }

