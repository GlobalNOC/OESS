import React from 'react'
import ReactDOM from "react-dom";
import NavLink from './NavLink';

export default class NavLinkDropdown extends React.Component{

constructor(props) {
                super(props);
                this.state = {}
        }
render(){

	var active = false;
    var links = this.props.links.map(function(link){
      if(link.active){
        active = true;
      }
      return (
        <NavLink linkTo={link.linkTo} text={link.text} active={link.active} />
      );
    });
    return (
      <li className={"dropdown " + (active ? "active" : "")}>
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
