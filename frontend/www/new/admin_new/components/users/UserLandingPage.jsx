import React from "react";
import ReactDOM from "react-dom";
import UsersTable from "../user_table/UserTable.jsx";
import NavBar from "../nav_bar/NavBar.jsx";
import getCurrentUser from '../../api/user_menu.jsx';
import ModalTemplate2 from '../generic_components/ModalTemplate2.jsx';
class UserLandingPage extends React.Component {
	
	constructor(props){
		super(props);
		this.state={
		     user: [],
		     isVisible: false,
		     rowdata:{}
		};
	}

	componentDidMount(props) {
        	let currComponent =  this;
       		 getCurrentUser().then(function (u) {
            		currComponent.setState({
                	user: u
           	 	})
       		 });
    	}

	displaypopup(currComponent){
             console.log("Add user popup");
             var rowdata = {};
             currComponent.setState({isVisible:true, rowdata:rowdata});
   	}


	render(){
		var currComponent = this;
		return (
		<div>
	<NavBar data={this.state.user}/>
        <center>
        <div>
            <center>
                <div>
                    <p className="title"><b>Users</b></p>
                    <p className="subtitle">Add or remove users</p>
                </div>
            </center>
            <br/>
            <br/>
            <div id="user_search_div">
                <label htmlFor="user_search" id="user_search_label">Search</label>
                <input type="text" className="form-control" size="25" id="user_search"/>
            </div>
            <br/>
            <br/>
            <p id="soft_title"> Existing Users</p>
            <center>
		<UsersTable/>
            </center>
            <br/>
            <br/>
            

		<button type="button" className="button is-link" data-target="#myModal2" data-toggle="modal">Add User</button>
	</div>
    </center>
	<ModalTemplate2/>
</div>
		);
	}

}

let mountNode = document.getElementById("show-users");
ReactDOM.render(<UserLandingPage />, mountNode);


