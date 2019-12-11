import React, { Component } from 'react';
import NavBrand from './NavBrand.jsx';
import NavMenu from './NavMenu.jsx';
import { testConfig } from '../.././test.jsx';

export default class NavBar extends React.Component{
	constructor(props) {
        	super(props);
        	this.state = {}
	}

	render(){

	var navbar = {};
	let path = testConfig.user;
	navbar.brand = {linkTo: "#", src: path+'media/internet2-logo.png', text: "Cloud Connect"};
	navbar.links = [
		{dropdown: true, text: "New Connections", links: [
   			 {linkTo: "#", text: "Layer 1"},
    			 {linkTo: "#", text: "Layer 2"}
  		]},
  		{linkTo: "#", text: "Explore"},
		{linkTo: "#", text: "Workgroup"},
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
          </div>
        </div>
      </nav>
    );
  }
 }

