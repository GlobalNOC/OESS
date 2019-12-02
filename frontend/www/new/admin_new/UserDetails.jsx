import React, { Component } from "react";
import { userState } from 'react';
import Modal from "react-bootstrap/Modal";
import Draggable from 'react-draggable';
import { Button } from 'reactstrap';
import ModalDialog from 'react-bootstrap/ModalDialog';

class DraggableModalDialog extends React.Component {
    render() {
        return <Draggable handle=".modal-title"><ModalDialog {...this.props} /> 
   </Draggable>
    }
}

export default class UserDetails extends Component {
constructor(props) {
    super(props);
    console.log("props", props);
    this.handleClose = this.handleClose.bind(this);
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


  handleClose() {
    this.setState({ show: false });
  };

  render() {
    return (
      <Modal dialogAs={DraggableModalDialog} show={this.state.show} onHide={this.handleClose}>
        <Modal.Header closeButton>
          <Modal.Title>User Details</Modal.Title>
        </Modal.Header>
        <Modal.Body>Woohoo, you're reading this text in a modal!</Modal.Body>
        <Modal.Footer>
          <Button variant="secondary" onClick={this.handleClose}>
            Close
          </Button>
          <Button variant="primary" onClick={this.handleClose}>
            Save Changes
          </Button>
        </Modal.Footer>
      </Modal>
    );
  }
	
}
