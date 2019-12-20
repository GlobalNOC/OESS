import React, { Component } from "react";
import { userState } from 'react';
import Modal from "react-bootstrap/Modal";
import Draggable from 'react-draggable';
import { Button } from 'reactstrap';
import ModalDialog from 'react-bootstrap/ModalDialog';


export default class ModalTemplate extends Component {
constructor(props) {
    super(props);
    console.log("props", props);
    this.state = {
      show: false,
      rowdata: null
    };
  }

componentWillReceiveProps(nextProps, prevState) {
 	this.setState({
 	   show: nextProps.isVisible[0],
 	   rowdata: nextProps.isVisible[1]
 	 })
 }




  render() {
  var rowdata = this.state.rowdata;
  console.log("here data", JSON.stringify(rowdata));
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
                        					<input type="text" className="form-control" id="firstname" placeholder="FirstName" value = {this.state.rowdata["First Name"]}/>
                    					</div>
                  				</div>
                  				<div className="form-group">
                    					<label className="col-sm-2 control-label modal-label" htmlFor="lastname" >Last Name</label>
                    					<div className="col-sm-10">
                        					<input type="text" className="form-control" id="lastname" placeholder="Last Name" value={this.state.rowdata["Last Name"]}/>
                    					</div>
                  				</div>
						<div className="form-group">
                                                        <label className="col-sm-2 control-label modal-label" htmlFor="email" >Email Address</label>
                                                        <div className="col-sm-10">
                                                                <input type="text" className="form-control" id="email" placeholder="email" value={this.state.rowdata["Email Address"]}/>
                                                        </div>
                                                </div>
						<div className="form-group">
                                                        <label className="col-sm-2 control-label modal-label" htmlFor="username" >Username(s) (comma separated)</label>
                                                        <div className="col-sm-10">
                                                                <input type="text" className="form-control" id="username" placeholder="UserName" value={this.state.rowdata["Username"]}/>
                                                        </div>
                                                </div>
						<div className="form-group">
                                                        <label className="col-sm-2 control-label modal-label" htmlFor="usertype" >User Type</label>
							<select class="form-control modal-select" id="usertype">
        							<option>Normal</option>
        							<option>Read-Only</option>
      							</select>
                                                </div>
						<div className="form-group">
                                                        <label className="col-sm-2 control-label modal-label" htmlFor="status" >Status</label>
                                                        <select class="form-control modal-select" id="status">
                                                                <option>Active</option>
                                                                <option>Decom</option>
                                                        </select>
                                                </div>

                			</form>
     				 </div>
      				<div className="modal-footer">
        				<button type="button" className="btn btn-default" data-dismiss="modal">Close</button>
        				<button type="button" className="btn btn-primary">Save changes</button>
      				</div>
    			</div>
  		</div>
	</div>);
	}else{
		return null;
	}
	}	
}
