import React from 'react';

export default class NavDropdown extends React.Component{
  render() {
    return (
      <li className={"dropdown"}>
        <a href="#" className="dropdown-toggle" data-toggle="dropdown" role="button" aria-haspopup="true" aria-expanded="false">
          {this.props.text} <span className="caret"></span>
        </a>
        <ul className="dropdown-menu">
          {this.props.children}
        </ul>
      </li>
    );
  }
}
