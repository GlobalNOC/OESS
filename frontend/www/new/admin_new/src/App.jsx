import React from "react";
import ReactDOM from "react-dom";

import { AdminNavBar } from "./components/nav_bar/AdminNavBar.jsx";
import NavBar from "./components/nav_bar/NavBar.jsx";
import { PageContextProvider } from './contexts/PageContext.jsx';

import { Users } from "./pages/users/Users.jsx";
import { Nodes } from "./pages/nodes/Nodes.jsx";
import { Workgroups } from "./pages/workgroups/Workgroups.jsx";
import { Toast } from "./components/generic_components/Toast.jsx";

import { BrowserRouter as Router, Switch, Route, Redirect } from "react-router-dom";

import "./style.css";
import { CreateWorkgroup } from "./pages/workgroups/CreateWorkgroup.jsx";
import { EditWorkgroup } from "./pages/workgroups/EditWorkgroup.jsx";
import { WorkgroupUsers } from "./pages/workgroups/WorkgroupUsers.jsx";
import { AddWorkgroupUser } from "./pages/workgroups/users/AddWorkgroupUser.jsx";
import { WorkgroupInterfaces } from "./pages/workgroups/WorkgroupInterfaces.jsx";
import { CreateUser } from "./pages/users/CreateUser.jsx";
import { EditUser } from "./pages/users/EditUser.jsx";
import { CreateNode } from "./pages/nodes/CreateNode.jsx";
import { EditNode } from "./pages/nodes/EditNode.jsx";
import { Interfaces } from "./pages/nodes/Interfaces.jsx";
import { Acls } from "./pages/nodes/interfaces/Acls.jsx";
import { CreateAcl } from "./pages/nodes/interfaces/acls/CreateAcl.jsx";
import { EditAcl } from "./pages/nodes/interfaces/acls/EditAcl.jsx";
import { EditInterface } from "./pages/nodes/interfaces/EditInterface.jsx";

const App = () => {
  return (
    <Router basename="/oess/new/admin">
      <PageContextProvider>
        <div className="oess-page-container">
          <div className="oess-page-navigation">
            <NavBar />
          </div>

          <div className="oess-side-navigation">
            <AdminNavBar />
          </div>

          <div className="oess-page-content">
            <Toast />

            <Switch>
              <Route exact path="/">
                <Redirect to="/users" />
              </Route>

              <Route path="/users/new"><CreateUser /></Route>
              <Route path="/users/:id" component={EditUser} />
              <Route path="/users" component={Users}></Route>
              
              <Route path="/nodes/new"><CreateNode /></Route>
              <Route path="/nodes/:id/interfaces/:interfaceId/acls/new" component={CreateAcl} />
              <Route path="/nodes/:id/interfaces/:interfaceId/acls/:interfaceAclId" component={EditAcl} />
              <Route path="/nodes/:id/interfaces/:interfaceId/acls" component={Acls} />
              <Route path="/nodes/:id/interfaces/:interfaceId" component={EditInterface} />
              <Route path="/nodes/:id/interfaces" component={Interfaces} />
              <Route path="/nodes/:id" component={EditNode} />
              <Route path="/nodes" component={Nodes} />

              <Route path="/workgroups/new">
                <CreateWorkgroup />
              </Route>
              <Route path="/workgroups/:id/interfaces" component={WorkgroupInterfaces} />
              <Route path="/workgroups/:id/users/add" component={AddWorkgroupUser} />
              <Route path="/workgroups/:id/users" component={WorkgroupUsers} />
              <Route path="/workgroups/:id" component={EditWorkgroup} />
              <Route path="/workgroups">
                <Workgroups />
              </Route>
            </Switch>
          </div>
        </div>
      </PageContextProvider>
    </Router>
  );
};

let mountNode = document.getElementById("app");
ReactDOM.render(<App />, mountNode);
