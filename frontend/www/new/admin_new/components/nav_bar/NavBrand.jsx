import React from 'react'



export default class NavBrand extends React.Component{
	
	constructor(props) {
                super(props);
                this.state = {}
        }	
	
	render(){
		return (
      		<a className="navbar-brand" href={this.props.linkTo}>
		<img className="navbar-brand-logo" src={this.props.src}/>	
		{this.props.text}
		</a>
    		); 
	}

}
