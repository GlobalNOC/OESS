import React from "react";
import ReactDOM from "react-dom";
import UsersTable from "../user_table/UserTable.jsx";
import getCurrentUser from '../../api/user_menu.jsx';
import ModalTemplate2 from '../generic_components/ModalTemplate2.jsx';

import { Page } from '../generic_components/Page.jsx';

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
      <Page>
        <div>

          <div>
            <div>
              <p className="title"><b>Users</b></p>
              <p className="subtitle">Add or remove users</p>
            </div>
            <br/>
            <br/>

            <form id="user_search_div" className="form-inline">
              <div className="form-group">
                <input type="text" className="form-control" id="user_search" placeholder="Username"/>
              </div>
              <button type="button" className="btn btn-primary" data-target="#myModal2" data-toggle="modal">Search</button>
              <button type="button" className="btn btn-default" data-target="#myModal2" data-toggle="modal">Add User</button>
            </form>

            <p id="soft_title"> Existing Users</p>
            <UsersTable/>
            <br/>
            <br/>
          </div>

          <ModalTemplate2/>

        </div>
      </Page>
    );
  }
}

let mountNode = document.getElementById("show-users");
ReactDOM.render(<UserLandingPage />, mountNode);
