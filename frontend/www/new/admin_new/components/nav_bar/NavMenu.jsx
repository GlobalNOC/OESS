import React from 'react';
import NavLinkDropdown from "./NavLinkDropdown";
import NavLink from "./NavLink";

export default class NavMenu extends React.Component{

	constructor(props) {
                super(props);
                this.state = {}
        }

	render(){
		var links = this.props.links.map(function(link){
     		 if(link.dropdown) {
        		return (
          			<NavLinkDropdown links={link.links} text={link.text} active={link.active} />
        		);
     		 }
     		 else {
        		return (
       				 <NavLink linkTo={link.linkTo} text={link.text} active={link.active} />
       			 );
     		 }
    		});
    		return (
     			 <ul key={+new Date() + Math.random()} className="nav navbar-nav">
        			{links}
      			</ul>
    		);

	}
}
