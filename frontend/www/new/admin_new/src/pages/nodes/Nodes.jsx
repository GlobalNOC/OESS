import React from "react";
import ReactDOM from "react-dom";

import { Link } from "react-router-dom";

import { PageContext } from "../../contexts/PageContext.jsx";
import { NodeForm } from "../../components/nodes/NodeForm.jsx";

class Nodes extends React.Component {
    constructor(props) {
      super(props);
      this.state = {
      };
    }
  
    async componentDidMount() {
    //   try {
    //     let users = await getUsers();
    //     this.setState({ users });
    //   } catch (error) {
      //     console.error(error);
      //   }
    }
    
  render() {
    
    return (
      <div>
        <div>
          <p className="title"><b>Nodes</b></p>
          <p className="subtitle">Add, remove, or update nodes.</p>
        </div>
        <br />

        {/* <NodeForm /> */}
      </div>
    );
  }
}
Nodes.contextType = PageContext;

export { Nodes };
