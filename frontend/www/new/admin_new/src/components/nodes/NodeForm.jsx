import React, { setState, useState } from 'react';

const validateForm = (e) => {
  return true;
};

export const NodeForm = (props) => {

  let onSubmit = (e) => {
    e.preventDefault();
    const node = {

    };
    let ok = validateForm(node);
    if (!ok) return;
    console.log('submit:', user, 'validated:', ok);

    if (props.onSubmit) {
      props.onSubmit(node);
    }
  };

  let onCancel = (e) => {
    let ok = confirm('Are you sure you wish to cancel? Any changes will be lost.');
    if (!ok) return;

    if (props.onCancel) {
      props.onCancel(e);
    }
  };

  return (
    <form onSubmit={onSubmit}>
      <h4>Settings</h4>
          <hr/>
      <div className="form-group">
        <label htmlFor="exampleInputEmail1">Name</label>
        <input type="text" className="form-control" id="exampleInputEmail1" placeholder="Email" />
      </div>
      <div className="form-group">
        <label htmlFor="exampleInputPassword1">IP Address</label>
        <input type="text" className="form-control" id="exampleInputPassword1" placeholder="Password" />
      </div>
      <div style={{display: 'inline-flex', width: '100%', gap: '12px'}}>
        <div className="form-group" style={{flex: '1'}}>
          <label htmlFor="exampleInputEmail1">Latitude</label>
          <input type="text" className="form-control" id="exampleInputEmail1" placeholder="Email" />
        </div>
        <div className="form-group" style={{flex: '1'}}>
          <label htmlFor="exampleInputPassword1">Longitude</label>
          <input type="text" className="form-control" id="exampleInputPassword1" placeholder="Password" />
        </div>
      </div>

      <div className="form-group">
        <label htmlFor="exampleInputPassword1">Network Controller</label>
        <select className="form-control" id="exampleInputPassword1">
          <option>NETCONF</option>
          <option>NSO</option>
        </select>
      </div>

      <br/>
      <h4>NETCONF</h4>
      <hr/>
      <div className="form-group">
        <label htmlFor="exampleInputPassword1">TCP Port</label>
        <input type="text" className="form-control" id="exampleInputPassword1" placeholder="Password" />
      </div>
      <div className="form-group">
        <label htmlFor="exampleInputPassword1">Make</label>
        <input type="text" className="form-control" id="exampleInputPassword1" placeholder="Password" />
      </div>
      <div className="form-group">
        <label htmlFor="exampleInputPassword1">Model</label>
        <input type="text" className="form-control" id="exampleInputPassword1" placeholder="Password" />
      </div>
      <div className="form-group">
        <label htmlFor="exampleInputPassword1">Firmware</label>
        <input disabled type="text" className="form-control" id="exampleInputPassword1" placeholder="Password" />
      </div>

      <br/>
      <button type="submit" className="btn btn-primary" style={{margin: '0 2px'}}>Submit</button>
      <button type="button" className="btn btn-default" style={{margin: '0 2px'}} data-dismiss="modal" onClick={onCancel}>Cancel</button>
    </form>
  );
};
