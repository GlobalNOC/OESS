import React from "react";

import { Link } from "react-router-dom";

import { getNodes, deleteNode, approveDiff } from "../../api/nodes.js";
import { PageContext } from "../../contexts/PageContext.jsx";
import { DiffApprovalForm } from "../../components/nodes/diff/DiffApprovalForm.jsx";
import { BaseModal } from "../../components/generic_components/BaseModal.jsx";
import { CustomTable } from "../../components/generic_components/CustomTable.jsx";


class Nodes extends React.Component {
  constructor(props) {
    super(props);
    this.state = {
      nodes:        [],
      diffNodeId:   -1,
      diffNodeName: '',
      visible:      false
    };

    this.deleteNode = this.deleteNode.bind(this);
    this.onApprovalHandler = this.onApprovalHandler.bind(this);
  }
  
  async componentDidMount() {
    try {
      let nodes = await getNodes();
      this.setState({ nodes });
    } catch (error) {
      console.error(error);
    }
  }

  async onApprovalHandler(e) {
    try {
      await approveDiff(this.state.diffNodeId);
      this.context.setStatus({type: 'success', message: `Pending changes for '${this.state.diffNodeName}' were successfully approved.`});

      // Attempt to reload nodes
      let nodes = await getNodes();
      this.setState({ nodes });
    } catch(error) {
      this.context.setStatus({type: 'error', message: error.toString()});
    }
    this.setState({visible: false});
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
    const rowButtons = (data) => {
      console.log(data);
      let diffButton = (
        <button type="button" className="btn btn-default btn-xs" onClick={() => this.setState({visible: true, diffNodeId: data.node_id, diffNodeName: data.name})}>
          <span className="glyphicon glyphicon-ok-sign" aria-hidden="true"></span>&nbsp;
          Pending Changes
        </button>
      );

      if (data.pending_diff == 1) {
        diffButton = (
          <button  type="button" className="btn btn-warning btn-xs" onClick={() => this.setState({visible: true, diffNodeId: data.node_id, diffNodeName: data.name})}>
            <span className="glyphicon glyphicon-info-sign" aria-hidden="true"></span>&nbsp;
            Pending Changes
          </button>
        );
      }

      return (
        <div>
          {diffButton}&nbsp;
          <div className="btn-group">
            <Link to={`/nodes/${data.node_id}`} className="btn btn-default btn-xs">Edit Node</Link>
            <button type="button" className="btn btn-default btn-xs dropdown-toggle" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false">
              <span>▾</span>{/* className="caret" doesn't work idk why */}
              <span className="sr-only">Toggle Dropdown</span>
            </button>
            <ul className="dropdown-menu" style={{fontSize: '12px'}}>
              <li><Link to={`/nodes/${data.node_id}/interfaces`}>Manage Interfaces</Link></li>
              <li role="separator" className="divider" style={{margin: '4px 0'}}></li>
              <li><a href="#" onClick={() => this.deleteNode(data)}>Delete Node</a></li>
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
        <BaseModal visible={this.state.visible} header={`Pending Changes: ${this.state.diffNodeName}`} modalID="diff-approval-modal" onClose={() => this.setState({visible: false})}>
          <DiffApprovalForm nodeId={this.state.diffNodeId} onCancel={() => this.setState({visible: false})} onApproval={this.onApprovalHandler} />
        </BaseModal>

        <div>
          <p className="title"><b>Nodes</b></p>
          <p className="subtitle">Create, edit, or delete Nodes</p>
        </div>
        <br />

        <CustomTable columns={columns} rows={this.state.nodes} size={5} filter={['node_id', 'name', 'ip_address']}>
          <CustomTable.MenuItem><Link to="/nodes/new" className="btn btn-default">Create Node</Link></CustomTable.MenuItem>
        </CustomTable>
      </div>
    );
  }
}
Nodes.contextType = PageContext;

export { Nodes };
