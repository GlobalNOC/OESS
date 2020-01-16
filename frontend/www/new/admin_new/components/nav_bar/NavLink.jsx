
import React from 'react';

export default class NavLink extends React.Component{
  render() {
    if (this.props.children) {
      return <li><a href={this.props.linkTo}>{this.props.children}</a></li>;
    }
    return <li><a href={this.props.linkTo}>{this.props.text}</a></li>;
  }
}
