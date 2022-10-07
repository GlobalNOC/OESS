import React, { Component } from "react";

class BaseModal extends Component {
  render() {
    // this.props.children
    // this.props.header
    // this.props.modalID

  let classes = 'modal fade';
  let style = {display: 'none', zIndex: 2};
  let backdrop = null;

  if (this.props.visible) {
    classes = 'modal fade in';
    style = {display: 'block', zIndex: 3};
    backdrop = <div className="modal-backdrop fade in" style={{zIndex: 3}} />;
  }

  let onClose = (this.props.onClose) ? this.props.onClose : () => {};

  let header = null;
  if (this.props.header !== undefined) {
    header = (
      <div className="modal-header">
        <button type="button" className="close" aria-label="Close" onClick={onClose}>
          <span aria-hidden="true">&times;</span>
        </button>
        <h4 className="modal-title" id={this.props.modalID}>{this.props.header}</h4>
      </div>
    );
  }

	return (
      <div>
        {backdrop}

        <div className={classes} style={style} id={this.props.modalID} tabIndex="-1" role="dialog" aria-labelledby={this.props.modalID}>
          <div className="modal-dialog" role="document">
            <div className="modal-content">
              {header}
              <div className="modal-body">
                  {this.props.children}
              </div>
            </div>
          </div>
        </div>
      </div>
    );
  }
}

export { BaseModal };
