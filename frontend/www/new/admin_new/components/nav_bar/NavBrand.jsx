import React from 'react'



export default class NavBrand extends React.Component{
	
	constructor(props) {
                super(props);
                this.state = {}
        }	
	
	render(){

		const textstyle = {
			fontSize: '2em'
		};
		return (
      		<a className="navbar-brand" style={textstyle} href={this.props.linkTo}>
		<img className="navbar-brand-logo" src={this.props.src}/>	
		{this.props.text}
		</a>
    		); 
	}

}
