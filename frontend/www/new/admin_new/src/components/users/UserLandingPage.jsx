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
	  user: null,
      workgroup: null,
	  isVisible: false,
	  rowdata:{}
	};

    this.setWorkgroup = this.setWorkgroup.bind(this);
  }

  async componentDidMount(props) {
    let user = await getCurrentUser();

    let json = sessionStorage.getItem('data');
    if (!json) {
      let obj = {
        username:       user.username,
        workgroup_id:   user.workgroups[0].workgroup_id,
        workgroup_name: user.workgroups[0].name,
        workgroup_type: user.workgroups[0].type
      };

      sessionStorage.data = encodeURIComponent(JSON.stringify(obj));
    }

    json = sessionStorage.getItem('data');
    let data = JSON.parse(decodeURIComponent(json));

    this.setState({user: user, workgroup: {name: data.workgroup_name, workgroup_id: data.workgroup_id}});
  }

  setWorkgroup(e) {
    let json = sessionStorage.getItem('data');
    let data = JSON.parse(decodeURIComponent(json));
    data.workgroup_name = e.target.text;
    sessionStorage.data = encodeURIComponent(JSON.stringify(data));
    this.setState({workgroup: {name: data.workgroup_name, workgroup_id: data.workgroup_id}});
  }


  displaypopup(currComponent){
    var rowdata = {};
    this.setState({isVisible:true, rowdata:rowdata});
  }

  render() {
    if (this.state.user === null) {
      return null;
    }

    var currComponent = this;
    return (
      <div>
        <NavBar data={this.state.user} workgroup={this.state.workgroup} setWorkgroup={this.setWorkgroup} />

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
    );
  }
}

let mountNode = document.getElementById("show-users");
ReactDOM.render(<UserLandingPage />, mountNode);
