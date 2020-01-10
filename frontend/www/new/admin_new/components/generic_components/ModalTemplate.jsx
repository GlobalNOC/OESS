import React, { Component } from "react";
import { userState } from 'react';
import Modal from "react-bootstrap/Modal";
import Draggable from 'react-draggable';
import { Button } from 'reactstrap';
import ModalDialog from 'react-bootstrap/ModalDialog';
import editUser from '../../api/user_edit.jsx';

export default class ModalTemplate extends Component {
constructor(props) {
    super(props);
    console.log("props", props);
    this.handleChange = this.handleChange.bind(this);
    this.updateUser = this.updateUser.bind(this);
    this.refreshPage = this.refreshPage.bind(this);
    this.state = {
	firstname : "",
	lastname : "",
	email : "",
	username : "",	
	usertype: "",
	userstatus: "",
	userid: null
    };
    
  }

componentWillReceiveProps(nextProps, prevState) {
 	this.setState({
 	   firstname: nextProps.rowdata["First Name"],
	   lastname: nextProps.rowdata["Last Name"],
	   email: nextProps.rowdata["Email Address"],
           username: nextProps.rowdata["Username"],
           usertype: nextProps.rowdata["User Type"],
           userstatus: nextProps.rowdata["User Status"],
 	   userid:nextProps.rowdata["userid"] 
	})
 }
ComponentDidMount(props) {
   const { firstname, lastname, email, username, usertype, userstatus, userid  } = this.props.rowdata;
   this.setState({ firstname, lastname, email, username, usertype, userstatus, userid });
}
ComponentDidUpdate(props){
   
}
refreshPage() {
    window.location.reload(false);
}
updateUser(event) {
        //console.log("Updating"+event);
        editUser(this.state.userid,this.state.firstname, this.state.lastname, this.state.email, this.state.usertype, this.state.userstatus, this.state.username).then(function () {
             console.log("Updated");
	     window.location.reload(false); //To be changed from force refresh to component refresh	     	     	   
        });
    }

handleChange(event) { 
        const target = event.target;
        const name = target.name;        
        var value = target.value;         

        if(name === "firstname")            
            this.setState({firstname: value});     
        if(name === "lastname")                         
            this.setState({lastname: value});
	if(name === "email")                         
            this.setState({email: value});
	if(name === "username")                         
            this.setState({username: value});
	if(name === "usertype")
	    this.setState({usertype: value});
	if(name === "userstatus")
	    this.setState({userstatus: value});
    }

  render() {
  var currcomponent = this;
  var rowdata = this.state.username;
  //console.log("here data", JSON.stringify(rowdata));
  
  if(rowdata){
  return(
	<div className="modal fade" id="myModal" tabIndex="-1" role="dialog" aria-labelledby="myModalLabel">
  		<div className="modal-dialog" role="document">
    			<div className="modal-content">
      				<div className="modal-header">
        				<button type="button" className="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
        				<h4 className="modal-title" id="myModalLabel">User Details</h4>
     				 </div>
      				<div className="modal-body">
        				<form className="form-horizontal" role="form">
                  				<div className="form-group">
                    					<label  className="col-sm-2 control-label modal-label" htmlFor="firstname">First Name</label>
                    					<div className="col-sm-10">
                        					<input type="text" name="firstname"  className="form-control" id="firstname" placeholder="FirstName" value = {this.state.firstname} onChange={this.handleChange}/>
                    					</div>
                  				</div>
                  				<div className="form-group">
                    					<label className="col-sm-2 control-label modal-label" htmlFor="lastname" >Last Name</label>
                    					<div className="col-sm-10">
                        					<input type="text" className="form-control" id="lastname" name="lastname"  placeholder="Last Name" value={this.state.lastname} onChange={this.handleChange}/>
                    					</div>
                  				</div>
						<div className="form-group">
                                                        <label className="col-sm-2 control-label modal-label" htmlFor="email" >Email Address</label>
                                                        <div className="col-sm-10">
                                                                <input type="text" className="form-control" id="email" placeholder="email" value={this.state.email} name="email" onChange={this.handleChange}/>
                                                        </div>
                                                </div>
						<div className="form-group">
                                                        <label className="col-sm-2 control-label modal-label" htmlFor="username" >Username(s) (comma separated)</label>
                                                        <div className="col-sm-10">
                                                                <input type="text" className="form-control" id="username" placeholder="UserName" value={this.state.username} name="username" onChange={this.handleChange}/>
                                                        </div>
                                                </div>
						<div className="form-group">
                                                        <label className="col-sm-2 control-label modal-label" htmlFor="usertype" >User Type</label>
							<select className="form-control modal-select" name="usertype" id="usertype" value={this.state.usertype} onChange={this.handleChange}>
        							<option value="normal">Normal</option>
        							<option value="read-only">Read-Only</option>
      							</select>
                                                </div>
						<div className="form-group">
                                                        <label className="col-sm-2 control-label modal-label" htmlFor="status" >Status</label>
                                                        <select className="form-control modal-select" name="userstatus" id="status" value={this.state.userstatus} onChange={this.handleChange}>
                                                                <option value="active">Active</option>
                                                                <option value="decom">Decom</option>
                                                        </select>
                                                </div>

                			</form>
     				 </div>
      				<div className="modal-footer">
        				<button type="button" className="btn btn-default" data-dismiss="modal">Close</button>
        				<button className="btn btn-default" onClick={this.updateUser} data-dismiss="modal">Save changes</button>
      				</div>
    			</div>
  		</div>
	</div>);
	}else{
		return null;
	}
	}	
}
