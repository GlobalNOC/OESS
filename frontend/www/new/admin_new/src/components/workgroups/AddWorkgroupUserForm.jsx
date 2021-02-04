import React, { useContext, useState, useEffect } from "react";
import { withRouter } from "react-router-dom";
import { AutoComplete } from '../generic_components/AutoComplete.jsx';

import { getUsers } from '../../api/users.jsx';

const validateForm = (e) => {
  // if (!e.userId) {
  //   return false;
  // }
  return true;
};

export const AddWorkgroupUserForm = (props) => {
  let [userId, setUserId] = useState(null);
  let [role, setRole] = useState('read-only');
  let [workgroupId, setWorkgroupId] = useState(props.workgroupId || 0);
  let [users, setUsers] = useState([]);

  useEffect(() => {
    try {
      getUsers().then((users) => {
        setUsers(users);
      });
    } catch (error) {
      // TODO Show error message to user
      setUsers([]);
      console.error(error);
      // this.context.setStatus({type:'error', message:error.toString()});
    }
  }, []);

  let onSubmit = (e) => {
    e.preventDefault();
    const payload = {
      role,
      userId,
      workgroupId
    };
    let ok = validateForm(payload);
    if (!ok) return;
    console.log('submit:', payload, 'validated:', ok);

    if (props.onSubmit) {
      props.onSubmit(payload);
    }
  };

  let onCancel = (e) => {
    let ok = confirm('Are you sure you wish to cancel? Any changes will be lost.');
    if (!ok) return;

    if (props.onCancel) {
      props.onCancel(e);
    }
  };

  let suggestions = users.map((user) => {
    return {name: user.auth_name[0], value: parseInt(user.user_id)};
  });

  return (
    <form onSubmit={onSubmit}>
      <div className="form-group">
        <label htmlFor="username">Username</label>
        <AutoComplete id="username" placeholder="Search by username" value={userId} onChange={(e) => setUserId(e)} suggestions={suggestions} />
      </div>

      <label htmlFor="role">Role</label>
      <select className="form-control" id="role" value={role} onChange={(e) => setRole(e.target.value)}>
        <option value="read-only">Read-Only</option>
        <option value="normal">Normal</option>
        <option value="admin">Admin</option>
      </select>

      <input type="hidden" name="workgroup-id" value={workgroupId} />
      <br/>

      <button type="submit" className="btn btn-primary" style={{margin: '0 2px'}}>Submit</button>
      <button type="button" className="btn btn-default" style={{margin: '0 2px'}} data-dismiss="modal" onClick={onCancel}>Cancel</button>
    </form>
  );
};
