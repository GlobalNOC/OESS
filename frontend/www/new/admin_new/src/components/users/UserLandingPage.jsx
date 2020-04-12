import React from "react";
import ReactDOM from "react-dom";
import UsersTable from "../user_table/UserTable.jsx";
import getCurrentUser from '../../api/user_menu.jsx';
import { AdminNavBar } from "../nav_bar/AdminNavBar.jsx";
import ModalTemplate2 from '../generic_components/ModalTemplate2.jsx';
import { PageContextProvider } from '../../contexts/PageContext.jsx';
import NavBar from "../nav_bar/NavBar.jsx";

import "../../style.css";

class UserLandingPage extends React.Component {
	
  constructor(props){
	super(props);
	this.state={
	  isVisible: false,
	  rowdata:{}
	};
  }

  displaypopup(currComponent){
    var rowdata = {};
    this.setState({isVisible:true, rowdata:rowdata});
  }

  render() {
    var currComponent = this;
    return (
      <PageContextProvider>

        <div className="oess-page-container">
          <div className="oess-page-navigation">
            <NavBar />
          </div>

          <div className="oess-side-navigation">
            <AdminNavBar />
          </div>

          <div className="oess-page-content">
            <div>
              <p className="title"><b>Users</b></p>
              <p className="subtitle">Add, remove, or update users.</p>
            </div>
            <br />

            <form id="user_search_div" className="form-inline">
              <div className="form-group">
                <input type="text" className="form-control" id="user_search" placeholder="Username"/>
              </div>
              <button type="button" className="btn btn-primary" data-target="#myModal2" data-toggle="modal">Search</button>
              <button type="button" className="btn btn-default" data-target="#myModal2" data-toggle="modal">Add User</button>
            </form>
            <br />

            <UsersTable />
            <ModalTemplate2 />
          </div>
        </div>
      </PageContextProvider>
    );
  }
}

let mountNode = document.getElementById("show-users");
ReactDOM.render(<UserLandingPage />, mountNode);
