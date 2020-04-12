import React from "react";
import ReactDOM from "react-dom";

import getCurrentUser from '../api/user_menu.jsx';

import { AdminNavBar } from "../components/nav_bar/AdminNavBar.jsx";
import ModalTemplate2 from '../components/generic_components/ModalTemplate2.jsx';
import NavBar from "../components/nav_bar/NavBar.jsx";
import UsersTable from "../components/user_table/UserTable.jsx";

import { PageContextProvider } from '../contexts/PageContext.jsx';

import "../style.css";


class Workgroups extends React.Component {
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

    // https://developer.mozilla.org/en-US/docs/Web/API/URL_API
    let url = new URL(document.location.href);
    let workgroup_id = url.searchParams.get('workgroup_id');
    console.log(url.pathname);

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
              <p className="title"><b>Workgroups</b></p>
              <p className="subtitle">Add, remove, or update Workgroups.</p>
            </div>
            <br />

            <form id="user_search_div" className="form-inline">
              <div className="form-group">
                <input type="text" className="form-control" id="user_search" placeholder="Workgroup"/>
              </div>
              <button type="button" className="btn btn-primary" data-target="#myModal2" data-toggle="modal">Search</button>
              <button type="button" className="btn btn-default" data-target="#myModal2" data-toggle="modal">Add Workgroup</button>
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

let mountNode = document.getElementById("app");
ReactDOM.render(<Workgroups />, mountNode);
