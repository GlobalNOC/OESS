import React from "react";
import ReactDOM from "react-dom";

import { Link } from "react-router-dom";

import { config } from '../../config.jsx';

import getUsers, { deleteUser } from '../../api/users.jsx';
import { PageContext } from "../../contexts/PageContext.jsx";

import { CustomTable } from "../../components/generic_components/CustomTable.jsx";

import "../../style.css";


class Users extends React.Component {
  constructor(props){
    super(props);
    this.state = {
      users:      []
    };

    this.deleteUser = this.deleteUser.bind(this);
  }

  async componentDidMount() {
    try {
      let users = await getUsers();
      this.setState({ users });
    } catch (error) {
      console.error(error);
    }
  }

  async deleteUser(user) {
    let ok = confirm(`Delete user '${user.usernames[0]}'?`);
    if (!ok) return;

    try {
      await deleteUser(user.user_id);
      this.context.setStatus({type:'success', message:`User '${user.usernames[0]}' was successfully deleted.`});
      this.setState((state) => {
        return {users: state.users.filter((u) => (u.user_id == user.user_id) ? false : true)};
      });
    } catch (error) {
      this.context.setStatus({type:'error', message:error.toString()});
    }
  }

  render() {
    const rowButtons = (data) => {
      if (config.third_party_mgmt == 1) {
        return <div></div>;
      }

      return (
        <div>
          <div className="btn-group">
            <Link to={`/users/${data.user_id}`} className="btn btn-default btn-xs">Edit User</Link>
            <button type="button" className="btn btn-default btn-xs dropdown-toggle" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false">
              <span>▾</span>{/* className="caret" doesn't work idk why */}
              <span className="sr-only">Toggle Dropdown</span>
            </button>
            <ul className="dropdown-menu" style={{fontSize: '12px'}}>
              <li><a href="#" onClick={() => this.deleteUser(data)}>Delete User</a></li>
            </ul>
          </div>
        </div>
      );
    };

    let columns = [
      { name: 'ID', key: 'user_id' },
      { name: 'First Name', key: 'first_name' },
      { name: 'Last Name', key: 'last_name' },
      { name: 'Email', key: 'email' },
      { name: 'Status', key: 'status' },
      { name: '', render: rowButtons, style: {textAlign: 'right'} }
    ];

    return (
      <div>
        <div>
          <p className="title"><b>Users</b></p>
          <p className="subtitle">Create, edit, or delete Users</p>
        </div>
        <br />

        <CustomTable columns={columns} rows={this.state.users} size={15} filter={['first_name', 'last_name', 'email']}>
          { config.third_party_mgmt == 1 ? null : <CustomTable.MenuItem><Link to="/users/new" className="btn btn-default">Create User</Link></CustomTable.MenuItem> }
        </CustomTable>
      </div>
    );
  }
}
Users.contextType = PageContext;

export { Users };
