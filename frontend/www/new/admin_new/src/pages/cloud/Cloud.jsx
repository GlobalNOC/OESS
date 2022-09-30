import React from "react";

import { PageContext } from "../../contexts/PageContext.jsx";
import { CustomTable } from "../../components/generic_components/CustomTable.jsx";
import { getEndpointsInReview, reviewEndpoint } from "../../api/admin.js";


class Cloud extends React.Component {
  constructor(props) {
    super(props);
    this.state = {
      endpoints:        [],
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
    try {
      console.info(`app ${approve} circ ${circuitEpId} vrf ${vrfEpId}`);

      await reviewEndpoint(approve, circuitEpId, vrfEpId);
      let status = (approve) ? 'approved' : 'denied';
      this.context.setStatus({type: 'success', message: `Endpoint was successfully ${status}.`});

      // Attempt to reload endpoints
      let endpoints = await getEndpointsInReview();
      this.setState({ endpoints });
    } catch(error) {
      this.context.setStatus({type: 'error', message: error.toString()});
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
            <span className="glyphicon glyphicon-ok-sign" aria-hidden="true"></span>&nbsp;
            Deny
          </button>
        </div>
      );
    };

    let columns = [
      { name: 'User', key: 'tag' },
      { name: 'Workgroup', key: 'tag' },
      { name: 'Type', key: 'cloud_interconnect_type' },
      { name: 'Entity', key: 'entity' },
      { name: 'Bandwidth (Mbps)', key: 'bandwidth' },
      { name: 'Date', key: 'tag' },
      { name: '', render: rowButtons, style: {textAlign: 'right'} }
    ];
    
    return (
      <div>
        <div>
        <p className="title"><b>Cloud</b></p>
        <p className="title2"><b>Provisioning Requests</b></p>
          <p className="subtitle">Approve or deny cloud provisioning requests</p>
        </div>
        <br />

        <CustomTable columns={columns} rows={this.state.endpoints} filter={[]}>
        </CustomTable>
      </div>
    );
  }
}
Cloud.contextType = PageContext;

export { Cloud };
