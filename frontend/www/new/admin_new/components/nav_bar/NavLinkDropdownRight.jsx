import React from 'react'
import ReactDOM from "react-dom";
import NavLink from './NavLink';

export default class NavLinkDropdownRight extends React.Component{

constructor(props) {
                super(props);
                this.state = {}
        }
render(){

	var detail_text = "";
    var links = this.props.links.map(function(link){
      if(link.details){
        detail_text = link.first_name+" "+link.last_name +" "+link.username+" "+link.email;
      }else{
	  detail_text = link.text;
	}
      return (
        <NavLink linkTo={link.linkTo} text={detail_text} active={link.active} />
      );
    });
    return (
      <li>
        <a href="#" className="dropdown-toggle" data-toggle="dropdown" role="button" aria-haspopup="true" aria-expanded="false">
          {this.props.text}
          <span className="caret"></span>
        </a>
        <ul key={+new Date() + Math.random()} className="dropdown-menu">
          {links}
        </ul>
      </li>
    );

}



}
