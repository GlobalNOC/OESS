import React from "react";
import ReactDOM from "react-dom";

import { UserLandingPage } from "./pages/Users.jsx";
import { Devices } from "./pages/Devices.jsx";
import { Workgroups } from "./pages/Workgroups.jsx";

import { BrowserRouter as Router, Switch, Route, Redirect } from "react-router-dom";

const App = () => {
  return (
    <Router basename="/oess/new/admin">
      <div>
        <Switch>
          <Route exact path="/">
            <Redirect to="/users" />
          </Route>
          <Route path="/users">
            <UserLandingPage />
          </Route>
          <Route path="/workgroups">
            <Workgroups />
          </Route>
          <Route path="/devices">
            <Devices />
          </Route>
        </Switch>
      </div>
    </Router>
  );
};

let mountNode = document.getElementById("app");
ReactDOM.render(<App />, mountNode);
