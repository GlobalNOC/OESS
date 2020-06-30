import React from "react";
import ReactDOM from "react-dom";
import UsersTable from "../components/user_table/UserTable.jsx";
import getCurrentUser from '../api/user_menu.jsx';
import { AdminNavBar } from "../components/nav_bar/AdminNavBar.jsx";
import ModalTemplate2 from '../components/generic_components/ModalTemplate2.jsx';
import { PageContextProvider } from '../contexts/PageContext.jsx';
import NavBar from "../components/nav_bar/NavBar.jsx";

import "../style.css";

class UserLandingPage extends React.Component {
	
  constructor(props){
	super(props);
	this.updateSearchQuery = this.updateSearchQuery.bind(this);
	this.handleKeyDown = this.handleKeyDown.bind(this);
	this.state={
	  isVisible: false,
	  rowdata:{},
	  search_query:'',
	};
  }

  displaypopup(currComponent){
    var rowdata = {};
    this.setState({isVisible:true, rowdata:rowdata});
  }

  updateSearchQuery(event){
        var value = document.getElementById("user_search").value;
	this.setState({search_query:value});
  }
  handleKeyDown(event){
	if (event.key === 'Enter') {
     		 this.updateSearchQuery();
    	}
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

            <form id="user_search_div" className="form-inline" onSubmit={e => { e.preventDefault(); }}> 
		<div className="form-group">
                <input type="text" className="form-control" id="user_search" placeholder="Username" onKeyDown={this.handleKeyDown}/>
            	</div>
              <button type="button" className="btn btn-primary" onClick={this.updateSearchQuery}>Search</button>
              <button type="button" className="btn btn-default" data-target="#myModal2" data-toggle="modal">Add User</button>
            <br />
	   </form>
            <UsersTable  query={this.state.search_query} />
            <ModalTemplate2 />
          </div>
        </div>
      </PageContextProvider>
    );
  }
}

export { UserLandingPage };
