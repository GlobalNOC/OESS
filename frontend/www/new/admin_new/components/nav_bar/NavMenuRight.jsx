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
        			<div class="dropdown-menu">
   					 <a class="dropdown-item" href="#">{link.first_name}{link.last_name}{link.username}{link.email}</a>
    				<div class="dropdown-divider"></div>
    					<a class="dropdown-item" href="#">admin</a>
  				</div>
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
