import React from 'react'



export default class NavBrand extends React.Component{
	
	constructor(props) {
                super(props);
                this.state = {}
        }	
	
	render(){
		return (
      		<a className="navbar-brand" href={this.props.linkTo}>{this.props.text}</a>
    		); 
	}

}
