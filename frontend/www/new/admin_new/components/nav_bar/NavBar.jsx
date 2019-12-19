import React, { Component } from 'react';
import NavBrand from './NavBrand.jsx';
import NavMenu from './NavMenu.jsx';
import NavMenuRight from './NavMenuRight.jsx';
import { testConfig } from '../.././test.jsx';
export default class NavBar extends React.Component{
	constructor(props) {
        	super(props);
        	this.state = {
            		users: []
		};
	}

	user_menu(userdata){
		var navbarlinks = []
		if(userdata.is_admin == "1"){
			navbarlinks.push({linkTo: "#", is_admin: userdata.is_admin, text: "Admin"});
		}
		var links = []
		links.push({linkTo: "#", details: true, first_name:userdata.first_name, last_name: userdata.last_name, username:userdata.username, email:userdata.email});
		if(userdata.length > 0 && (userdata.workgroups).length > 0){
			var workgroups = userdata.workgroups;
			workgroups.forEach(function(i){
			 	links.push({linkTo: "#", text: i.name});});	
		navbarlinks.push({dropdown: true, text: userdata.username+"/"+userdata.workgroups[0].name, links: links});
		}else{
			navbarlinks.push({dropdown: true, text: userdata.username, links: links});
		}
		return navbarlinks;
		
	}

	render(){
	console.log(JSON.stringify(this.props));
	var current_user = this.props.data;
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
	console.log("change it from cookie", JSON.stringify(current_user));
	/*navbar.admin = [
		{linkTo: "#", is_admin: current_user.is_admin, text: "Admin"},
		{dropdown: true, text: current_user.username+"/admin", links: [
                         {linkTo: "#", details: true, first_name:current_user.first_name, last_name: current_user.last_name, username:current_user.username, email:current_user.email},
			 {linkTo: "#", text: current_user.workgroups}
                ]},
	]*/
	navbar.admin = this.user_menu(current_user);
	console.log("data formed ",navbar.admin);


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

