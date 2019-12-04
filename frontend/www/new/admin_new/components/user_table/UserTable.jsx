import React from "react";
import ReactDOM from "react-dom";
import { BrowserRouter as Router, Route, Link } from "react-router-dom";
import TableTemplate from '.././generic_components/TableTemplate.jsx';
import getUsers from '../../api/users.jsx';

export default class UsersTable extends React.Component {
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
                users_data.push(data);
            });
            //UserTable component to create table from JSON
            return <TableTemplate data={users_data} />;
        } else {
            return null;
        }
    }
}

