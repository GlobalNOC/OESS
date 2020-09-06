import React, { setState, useState } from 'react';

const validateForm = (e) => {
  return true;
};

export const UserForm = (props) => {
  let tEmail = (props.user && props.user.name) ? props.user.name : '';
  let tFirstName = (props.user && props.user.first_name) ? props.user.first_name : '';
  let tLastName = (props.user && props.user.last_name) ? props.user.last_name : '';
  let tUserId = (props.user && props.user.user_id) ? props.user.user_id : 0;
  let tUsername = (props.user && props.user.username) ? props.user.username : '';

  const [email, setEmail] = useState(tEmail);
  const [firstName, setFirstName] = useState(tFirstName);
  const [lastName, setLastName] = useState(tLastName);
  const [userId, setUserId] = useState(tUserId);
  const [username, setUsername] = useState(tUsername);

  let onSubmit = (e) => {
    e.preventDefault();
    const user = {
      email,
      firstName,
      lastName,
      username
    };
    let ok = validateForm(user);
    if (!ok) return;
    console.log('submit:', user, 'validated:', ok);

    if (props.onSubmit) {
      props.onSubmit(user);
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

      <div className="form-group">
        <label htmlFor="first-name">First Name</label>
        <input className="form-control" type="text" id="first-name" name="first_name" value={firstName} onChange={(e) => setFirstName(e.target.value)} />
      </div>
      <div className="form-group">
        <label htmlFor="last-name">Last Name</label>
        <input className="form-control" type="text" id="last-name" name="last_name" value={lastName} onChange={(e) => setLastName(e.target.value)} />
      </div>
      <div className="form-group">
        <label htmlFor="email">Email</label>
        <input className="form-control" type="text" id="email" name="email" value={email} onChange={(e) => setEmail(e.target.value)} />
      </div>
      <div className="form-group">
        <label htmlFor="first-name">Username(s)</label>
        <input className="form-control" type="text" id="username" name="username" value={username} onChange={(e) => setUsername(e.target.value)} />
      </div>

      <input type="hidden" name="user_id" value={userId} />

      <button type="submit" className="btn btn-primary" style={{margin: '0 2px'}}>Submit</button>
      <button type="button" className="btn btn-default" style={{margin: '0 2px'}} data-dismiss="modal" onClick={onCancel}>Cancel</button>
    </form>
  );
};
