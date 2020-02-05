import React from "react";
import ReactDOM from "react-dom";
import { BrowserRouter as Router, Route, Link } from "react-router-dom";
import TableTemplate from '.././generic_components/TableTemplate.jsx';
import getUsers from '../../api/users.jsx';

export default class UsersTable extends React.Component {
    constructor(props) {
        super(props);
	this.pageUpdate = this.pageUpdate.bind(this);
        this.state = {
            users: [{
                "auth_name": [],
                "email_address": "",
                "status": "",
                "type": "",
                "user_id": "",
                "family_name": "",
                "first_name": ""
            }],
	    offset: 5,
	    curr_page: 1
        };
    }

    componentDidMount(props) {
	let currComponent =  this;
	getUsers().then(function (u) { 	     
            currComponent.setState({
                users: u
            })
        });
    }

    componentDidUpdate() {
        //to-do 
    }

    pageUpdate(event){
	//console.log(event);
	const target = event.target;
	const name = target.name;
	//const value = event.value;
	//console.log("clicked", name);
	const curr= this.state.curr_page;
	if(name == "first"){
		this.setState({curr_page: 1});
	}
	if(name == "previous"){
	    if(curr > 1){
		this.setState({curr_page: curr-1});
	    } 
	}
	if(name == "next"){
	     if(curr < 10){
		this.setState({curr_page: curr + 1});
	     }
	}
	if(name == "last"){
		// total result / offset --> num of pages ; now set to last number
		this.setState({curr_page: 10 });
	}	
    }
	
    render() {
        //Render Table if atleast 1 user data is available
        var currcomp = this;
	if (this.state.users[0].user_id != "") {
            var users_data = [];
            this.state.users.forEach(function (obj) {
                var data = {};
                data["First Name"] = obj.first_name;
                data["Last Name"] = obj.family_name;
                data["Username"] = obj.auth_name[0];
                data["Email Address"] = obj.email_address;
                data["User Type"] = obj.type;
                data["User Status"] = obj.status;
		data["userid"] = obj.user_id;

                users_data.push(data);
            });
            //UserTable component to create table from JSON
            //For Pagination
            // On click oft the num, set state of offset to page number
            // from total result, get current page to offset * per page, set to data and send to the component 
            return (
		    <div>
			<TableTemplate data={users_data} />
			
			<div id="user_table_nav">
                		<nav aria-label="Page navigation example">
                    		<ul className="pagination">

                        		<li className="page-item" name="first" onClick={this.pageUpdate}>
                            			<a name = "first" onClick={this.pageUpdate} className="page-link" aria-label="First">
                                			<span aria-hidden="true">&laquo;</span>
                                			<span className="sr-only">First</span>
                            			</a>
                        		</li>
                        		<li className="page-item" name="previous" onClick={this.pageUpdate}>
                            			<a name="previous" onClick= {this.pageUpdate} className="page-link" aria-label="Previous">
                                			<span aria-hidden="true">&lsaquo;</span>
                                			<span className="sr-only">Previous</span>
                           			 </a>
                        		</li>
                        		<li className="page-item" name="page-number"><a className="page-link" href="#">{this.state.curr_page}</a></li>
                        		<li className="page-item" name="next" onClick={this.pageUpdate}>
                            			<a name="next" onClick= {this.pageUpdate} className="page-link" aria-label="Next">
                                			<span aria-hidden="true">&rsaquo;</span>
                                			<span className="sr-only">Next</span>
                            			</a>
                        		</li>
                        		<li className="page-item" name="last" onClick={this.pageUpdate}>
                            			<a name="last" onClick= {this.pageUpdate} className="page-link" aria-label="Last">
                                			<span aria-hidden="true">&raquo;</span>
                                			<span className="sr-only">Last</span>
                            			</a>
                        		</li>
                    		</ul>
                		</nav>
            		</div>
		    </div>);
        } else {
            return null;
        }
    }
}

