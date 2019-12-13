import React from 'react';



export default class NavLink extends React.Component{

constructor(props) {
                super(props);
                this.state = {}
}

render(){
	let list;
 	if(this.props.is_admin == true){
                list = <li className="admin-link"><a href={this.props.linkTo}>Admin</a></li>;
        }
        else{
                list =  <li><a href={this.props.linkTo}>{this.props.text}</a></li>;
        }	
return(
	list
	);
}


}
