import React from "react";
import ReactDOM from "react-dom";
import UsersTable from "../user_table/UserTable.jsx";
import NavBar from "../nav_bar/NavBar.jsx";
import getCurrentUser from '../../api/user_menu.jsx';
class UserLandingPage extends React.Component {
	
	constructor(props){
		super(props);
		this.state={
		     user: []
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


	render(){

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
            <div id="user_table_nav">
                <nav aria-label="Page navigation example">
                    <ul className="pagination">

                        <li className="page-item">
                            <a className="page-link" href="#" aria-label="First">
                                <span aria-hidden="true">&laquo;</span>
                                <span className="sr-only">First</span>
                            </a>
                        </li>
                        <li className="page-item">
                            <a className="page-link" href="#" aria-label="Previous">
                                <span aria-hidden="true">&lsaquo;</span>
                                <span className="sr-only">Previous</span>
                            </a>
                        </li>
                        <li className="page-item"><a className="page-link" href="#">1</a></li>
                        <li className="page-item">
                            <a className="page-link" href="#" aria-label="Next">
                                <span aria-hidden="true">&rsaquo;</span>
                                <span className="sr-only">Next</span>
                            </a>
                        </li>
                        <li className="page-item">
                            <a className="page-link" href="#" aria-label="Last">
                                <span aria-hidden="true">&raquo;</span>
                                <span className="sr-only">Last</span>
                            </a>
                        </li>
                    </ul>
                </nav>
            </div>
            <button type="button" className="button is-link">Add User</button>
	</div>
    </center>
</div>
		);
	}

}

let mountNode = document.getElementById("show-users");
ReactDOM.render(<UserLandingPage />, mountNode);


