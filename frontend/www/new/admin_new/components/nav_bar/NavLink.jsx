import React from 'react';



export default class NavLink extends React.Component{

constructor(props) {
                super(props);
                this.state = {}
        }

render(){

return(
      <li className={(this.props.active ? "active" : "")}><a href={this.props.linkTo}>{this.props.text}</a></li>
    );

}


}
