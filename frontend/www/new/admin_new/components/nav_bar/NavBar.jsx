import React, { Component } from 'react';
import NavBrand from './NavBrand.jsx';
import NavMenu from './NavMenu.jsx';

export default class NavBar extends React.Component{
	constructor(props) {
        	super(props);
        	this.state = {}
	}

	render(){

	var navbar = {};
	navbar.brand = {linkTo: "#", text: "Cloud Connect"};
	navbar.links = [
 		 {linkTo: "#", text: "Discovery"},
  		{linkTo: "#", text: "Network"},
		{linkTo: "#", text: "Users"},
		{linkTo: "#", text: "Workgroups"},
		{linkTo: "#", text: "Remote Links"},
		{linkTo: "#", text: "Remote Devices"},
		{linkTo: "#", text: "Maintainances"},
		{linkTo: "#", text: "Config Changes"},
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
            <NavBrand linkTo={navbar.brand.linkTo} text={navbar.brand.text} />
          </div>
          <div className="collapse navbar-collapse" id="navbar-collapse">
            <NavMenu links={navbar.links} />
          </div>
        </div>
      </nav>
    );
  }
 }

