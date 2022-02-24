import React from 'react';

import "./navbar.css";

export default class NavBrand extends React.Component {
  render() {
    return (
      <a className="navbar-brand oess-navbar-brand" href={this.props.linkTo}>
        <img className="navbar-brand-logo" src={this.props.src} alt="Cloud Connect Logo" />	
        {this.props.text}
      </a>
    ); 
  }
}
