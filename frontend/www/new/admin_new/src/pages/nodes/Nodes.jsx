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

  filterNodes(e) {
    // Reset back the first table page when the filter is changed
    this.setState({
      filter:     e.target.value,
      pageNumber: 0
    });
  }
    
  render() {
    
    return (
      <div>
        <div>
          <p className="title"><b>Nodes</b></p>
          <p className="subtitle">Add, remove, or update nodes.</p>
        </div>
        <br />

        <form id="user_search_div" className="form-inline">
          <div className="form-group">
            <div className="input-group">
              <span className="input-group-addon" id="icon"><span className="glyphicon glyphicon-search" aria-hidden="true"></span></span>
              <input type="text" className="form-control" id="user_search" placeholder="Filter Nodes" aria-describedby="icon" onChange={(e) => this.filterNodes(e)} />
            </div>
          </div>
          <Link to="/nodes/new" className="btn btn-default">Create Node</Link>
        </form>
        <br />

        {/* <NodeForm /> */}
      </div>
    );
  }
}
Nodes.contextType = PageContext;

export { Nodes };
