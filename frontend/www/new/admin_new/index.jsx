import React from "react";
import ReactDOM from "react-dom";
import { BrowserRouter as Router, Route, Link } from "react-router-dom";
import UserTable from './UserTable.jsx';

//To be modified
let path = 'https://rojraman-dev.grnoc.iu.edu/oess/';
async function getUsers() {
    let url = `${path}services/admin/admin.cgi?method=get_users`;

    try {
        const resp = await fetch(url, { method: 'get', credentials: 'include' });
        const data = await resp.json();
        if (data.error_text) throw data.error_text;
        return data.results;
    } catch (error) {
        console.log('Failure occurred in get_users.');
        console.log(error);
        return [];
    }
}

class Users extends React.Component {
    constructor(props) {
        super(props);
        this.state = {
            users: [{
                "auth_name": [],
                "email_address": "",
                "status": "",
                "type": "",
                "user_id": "",
                "family_name": "",
                "first_name": ""
            }]
        };
    }
    //Call to getUsers method
    fetchUsers(props, currComponent) {
        getUsers().then(function (u) {
            currComponent.setState({
                users: u
            })
        });
    }

    componentDidMount(props) {
        //Fetch Users
        this.fetchUsers(props, this);
    }

    componentDidUpdate() {
        //to-do 
    }
	
    render() {
        //Render Table if atleast 1 user data is available
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
                users_data[obj.user_id - 1] = data;
            });
            //UserTable component to create table from JSON
            return <UserTable data={users_data} />;
        } else {
            return null;
        }
    }
}

let mountNode = document.getElementById("users");
ReactDOM.render(<Users />, mountNode);
