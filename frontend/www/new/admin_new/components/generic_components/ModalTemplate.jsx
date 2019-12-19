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

  return(
	<div className="modal fade" id="myModal" tabIndex="-1" role="dialog" aria-labelledby="myModalLabel">
  <div className="modal-dialog" role="document">
    <div className="modal-content">
      <div className="modal-header">
        <button type="button" className="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
        <h4 className="modal-title" id="myModalLabel">Modal title</h4>
      </div>
      <div className="modal-body">
        ...
      </div>
      <div className="modal-footer">
        <button type="button" className="btn btn-default" data-dismiss="modal">Close</button>
        <button type="button" className="btn btn-primary">Save changes</button>
      </div>
    </div>
  </div>
</div>);
	}	
}
