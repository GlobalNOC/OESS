import React from 'react';
import NavLinkDropdownRight from "./NavLinkDropdownRight";
import NavLink from "./NavLink";

export default class NavMenuRight extends React.Component{

	constructor(props) {
                super(props);
                this.state = {}
        }

	render(){
		var links = this.props.links.map(function(link){
     		 if(link.dropdown) {
        		if(link.details){
				return (
          				<NavLinkDropdownRight links={link.links} details={link.details} first_name={link.first_name} last_name={link.last_name} username={link.username} email={link.email} />
        			);
			}else{
				return (
                                	<NavLinkDropdownRight links={link.links} text={link.text} />
                        	);
			}
			
     		 }
     		 else {
        		return (
       				 <NavLink linkTo={link.linkTo} text={link.text} is_admin={link.is_admin} />
       			 );
     		 }
    		});
    		return (
			
     			 <ul key={+new Date() + Math.random()} className="nav navbar-nav navbar-right">
        			{links}
      			</ul>
    		);

	}
}
