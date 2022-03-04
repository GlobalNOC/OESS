import React, { useContext, useEffect, useState } from "react";
import { withRouter } from "react-router-dom";

import { createUser } from '../../api/user_add.jsx';
import { editUser, getUser } from '../../api/users.jsx';
import { UserForm } from '../../components/users/UserForm.jsx';
import { PageContext } from "../../contexts/PageContext.jsx";

import "../../style.css";

const editUserComponent = (props) => {
  const { history, match } = props;
  const { setStatus } = useContext(PageContext);
  const [user, setUser] = useState(null);

  useEffect(() => {
    getUser(match.params["id"]).then(user => {
      console.log(user);
      setUser(user);
    }).catch(error => {
      console.log(error);
      setStatus(error);
    });
  }, [match]);

  let submitHandler = async (e) => {
    try {
      await editUser(e);
      setStatus({type:'success', message:`User '${e.usernames[0]}' was successfully edited.`});
    } catch (error) {
      setStatus({type:'error', message:error.toString()});
    }
    history.push('/users');
  };

  let cancelHandler = async () => {
    history.push('/users');
  };

  if (user == null) {
    return <p>Loading</p>;
  };

  return (
    <div>
      <div>
        <p className="title"><b>Edit User</b> {user.username}</p>
        <p className="subtitle">Edit User.</p>
      </div>
      <br />

      <UserForm user={user} onSubmit={submitHandler} onCancel={cancelHandler} />
    </div>
  );
};

export const EditUser = withRouter(editUserComponent);
