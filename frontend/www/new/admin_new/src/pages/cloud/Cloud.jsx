import React from "react";
import { config } from '../../config.jsx';

import { PageContext } from "../../contexts/PageContext.jsx";
import { BaseModal } from "../../components/generic_components/BaseModal.jsx";
import { CustomTable } from "../../components/generic_components/CustomTable.jsx";
import { getEndpointsInReview, reviewEndpoint } from "../../api/admin.js";


class Cloud extends React.Component {
  constructor(props) {
    super(props);
    this.state = {
      endpoints: [],
      onApprovalHandlerLoading: false,
    };

    this.onApprovalHandler = this.onApprovalHandler.bind(this);
  }
  
  async componentDidMount() {
    try {
      let endpoints = await getEndpointsInReview();
      this.setState({ endpoints });
    } catch (error) {
      this.context.setStatus({type: 'error', message: error.toString()});
    }
  }

  async onApprovalHandler(approve, circuitEpId, vrfEpId) {
    if (approve) {
      let ok = confirm(`Are you sure you want to 'approve' this endpoint?`);
      if (!ok) return;
    } else {
      let ok = confirm(`Are you sure you want to 'deny' this endpoint?`);
      if (!ok) return;
    }
    
    this.setState({onApprovalHandlerLoading: true});
    try {
      await reviewEndpoint(approve, circuitEpId, vrfEpId);
      let status = (approve) ? 'approved' : 'denied';
      this.context.setStatus({type: 'success', message: `Endpoint was successfully ${status}.`});
    } catch(error) {
      this.context.setStatus({type: 'error', message: error.toString()});
    }
    this.setState({onApprovalHandlerLoading: false});
    
    try {
      let endpoints = await getEndpointsInReview();
      this.setState({ endpoints });
    } catch(error) {
      console.error(error.toString());
    }
  }

  render() {
    const rowButtons = (data) => {
      return (
        <div>
          <button type="button" className="btn btn-default btn-xs" onClick={() => this.onApprovalHandler(true, data["circuit_ep_id"], data["vrf_endpoint_id"])}>
            <span className="glyphicon glyphicon-ok-sign" aria-hidden="true"></span>&nbsp;
            Approve
          </button>
          &nbsp;
          <button type="button" className="btn btn-default btn-xs" onClick={() => this.onApprovalHandler(false, data["circuit_ep_id"], data["vrf_endpoint_id"])}>
            <span className="glyphicon glyphicon-minus-sign" aria-hidden="true"></span>&nbsp;
            Deny
          </button>
        </div>
      );
    };

    const connectionLink = (data) => {
      let url;
      if (data.circuit_id) {
        url = `../../index.cgi?action=modify_l2vpn&circuit_id=${data.circuit_id}`;
      } else {
        url = `../../index.cgi?action=modify_cloud&vrf_id=${data.vrf_id}`;
      }

      return ( <a href={url}><code>{data.circuit_id || data.vrf_id }</code></a> );
    };

    let columns = [
      { name: 'Connection', render: connectionLink },
      { name: 'Workgroup', key: 'workgroup.name' },
      { name: 'User', key: 'last_modified_by.email' },
      { name: 'Bandwidth (Mbps)', key: 'bandwidth' },
      { name: 'Entity', key: 'entity' },
      { name: 'Type', key: 'cloud_interconnect_type' },
      { name: 'Date', render: data => `${new Date(data.last_modified_on * 1000).toLocaleString()}` },
      { name: '', render: rowButtons, style: {textAlign: 'right'} }
    ];

    return (
      <div>
        <BaseModal visible={this.state.onApprovalHandlerLoading} modalID="approve-handler-modal">
          <center><img src={`${config.base_url}/media/loading.gif`} /></center>
        </BaseModal>

        <div>
          <p className="title"><b>Cloud</b></p>
          <p className="subtitle">Approve or deny endpoint provisioning requests</p>
        </div>
        <br />

        <CustomTable columns={columns} rows={this.state.endpoints} filter={[]} />
      </div>
    );
  }
}
Cloud.contextType = PageContext;

export { Cloud };
