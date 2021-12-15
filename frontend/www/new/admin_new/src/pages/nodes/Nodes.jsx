import React from "react";
import ReactDOM from "react-dom";

import { Link } from "react-router-dom";

import { getNodes, deleteNode } from "../../api/nodes.js";
import { PageContext } from "../../contexts/PageContext.jsx";
import { PageSelector } from '../../components/generic_components/PageSelector.jsx';
import { Table } from "../../components/generic_components/Table.jsx";
import { DiffApprovalForm } from "../../components/nodes/diff/DiffApprovalForm.jsx";
import { BaseModal } from "../../components/generic_components/BaseModal.jsx";

class Nodes extends React.Component {
  constructor(props) {
    super(props);
    this.state = {
      pageNumber: 0,
      pageSize:   4,
      filter:     '',
      nodes:      [],
      diffNodeId: -1,
      visible:    false
    };

    this.filterNodes = this.filterNodes.bind(this);
    this.deleteNode = this.deleteNode.bind(this);
  }
  
  async componentDidMount() {
    try {
      let nodes = await getNodes();
      this.setState({ nodes });
    } catch (error) {
      console.error(error);
    }
  }

  filterNodes(e) {
    // Reset back the first table page when the filter is changed
    this.setState({
      filter:     e.target.value,
      pageNumber: 0
    });
  }

  async deleteNode(node) {
    let ok = confirm(`Delete node '${node.name}'?`);
    if (!ok) return;
    try{
      await deleteNode(node.node_id);
      this.context.setStatus({type: 'success', message: `Node '${node.name}' was successfully deleted.`});
      this.setState((state) => {
        return {nodes: state.nodes.filter((n) => (n.node_id == node.node_id) ? false : true)};
      });
    }catch(error){
      this.context.setStatus({type: 'error', message: error.toString()});
    }    
  }

  render() {
    let pageStart = this.state.pageSize * this.state.pageNumber;
    let pageEnd = pageStart + this.state.pageSize;
    let filteredItemCount = 0;

    let nodes = this.state.nodes.filter((d) => {
      if (!this.state.filter) {
        return true;
      }

      if ( (new RegExp(this.state.filter, 'i').test(d.name)) ) {
        return true;
      } else if ( (new RegExp(this.state.filter, 'i').test(d.ip_address)) ) {
        return true;
      } else if ( this.state.filter == d.node_id ) {
        return true;
      } else {
        return false;
      }
    }).filter((d, i) => {
      // Any items not filtered by search are displayed and the count
      // of these are used to determine the number of table pages to
      // show.
      filteredItemCount += 1;

      if (i >= pageStart && i < pageEnd) {
        return true;
      } else {
        return false;
      }
    });

    const rowButtons = (data) => {
      return (
        <div>
          <button type="button" className="btn btn-default btn-xs" onClick={() => this.setState({visible: true, diffNodeId: data.node_id})}>Preview Changes</button>&nbsp;
          <div className="btn-group">
              <Link to={`/nodes/${data.node_id}`} className="btn btn-default btn-xs">Edit Node</Link>
              <button type="button" className="btn btn-default btn-xs dropdown-toggle" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false">
                <span>▾</span>{/* className="caret" doesn't work idk why */}
                <span className="sr-only">Toggle Dropdown</span>
              </button>
              <ul className="dropdown-menu" style={{fontSize: '12px'}}>
                <li><a href="#" onClick={() => this.deleteNode(data)}>Delete Node</a></li>
                <li role="separator" className="divider" style={{margin: '4px 0'}}></li>
                <li><Link to={`/nodes/${data.node_id}/interfaces`}>Manage Interfaces</Link></li>
              </ul>
            </div>
        </div>
      );
    };

    let columns = [
      { name: 'ID', key: 'node_id' },
      { name: 'Name', key: 'name' },
      { name: 'IP Address', key: 'ip_address' },
      { name: 'Make', key: 'make' },
      { name: 'Model', key: 'model' },
      { name: 'Firmware', key: 'sw_version' },
      { name: '', render: rowButtons, style: {textAlign: 'right'} }
    ];
    
    return (
      <div>
        <BaseModal visible={this.state.visible} header="Preview Changes" modalID="diff-approval-modal" onClose={() => {this.setState({visible: false}); console.log(this.state); } }>
          <DiffApprovalForm nodeId={this.state.diffNodeId} onCancel={() => this.setState({visible: false})} />
        </BaseModal>

        <div>
          <p className="title"><b>Nodes</b></p>
          <p className="subtitle">Create, edit, or delete Nodes</p>
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

        <Table columns={columns} rows={nodes} />
        <center>
          <PageSelector pageNumber={this.state.pageNumber} pageSize={this.state.pageSize} itemCount={filteredItemCount} onChange={(i) => this.setState({pageNumber: i})} />
        </center>
      </div>
    );
  }
}
Nodes.contextType = PageContext;

export { Nodes };
