import React, { useContext } from "react";
import { withRouter } from "react-router-dom";

import { createUser } from '../../api/users.jsx';
import { UserForm } from '../../components/users/UserForm.jsx';
import { PageContext } from "../../contexts/PageContext.jsx";

import "../../style.css";

const createUserComponent = (props) => {
  const { history } = props;
  const { setStatus } = useContext(PageContext);

  let submitHandler = async (e) => {
    try {
      await createUser(e);
      setStatus({type:'success', message:`User '${e.usernames[0]}' was successfully created.`});
    } catch (error) {
      setStatus({type:'error', message:error});
    }
    history.push('/users');
  };

  let cancelHandler = async () => {
    history.push('/users');
  };

  return (
    <div>
      <div>
        <p className="title"><b>Create User</b></p>
        <p className="subtitle">Create a new User.</p>
      </div>
      <br />

      <UserForm user={null} onSubmit={submitHandler} onCancel={cancelHandler} />
    </div>
  );
}

export const CreateUser = withRouter(createUserComponent);
