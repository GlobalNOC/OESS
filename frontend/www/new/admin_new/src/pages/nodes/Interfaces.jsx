import React from 'react';
import { getNode } from '../../api/nodes.js';
import { getInterfaces } from '../../api/interfaces.js';
import { PageContext } from "../../contexts/PageContext.jsx";
import { PageSelector } from '../../components/generic_components/PageSelector.jsx';
import { Table } from "../../components/generic_components/Table.jsx";
import { Link } from "react-router-dom";

class Interfaces extends React.Component {
    constructor(props) {
        super(props);        
        this.state = {
            node: null,
            interfaces: [],
            pageSize: 20,
            pageNumber: 0,
            filter: '',
            match: props.match
        }
        this.filterInterfaces = this.filterInterfaces.bind(this);
    }

    async componentDidMount(){
        try {
            const node = await getNode(this.state.match.params['id']);            
            const interfaces = await getInterfaces(this.state.match.params['id']);
            this.setState({interfaces: interfaces, node: node});
        } catch(error) {
            this.context.setStatus({type: 'error', message: error.toString()});
        }
    }

    filterInterfaces(e) {
        // Reset back the first table page when the filter is changed
        this.setState({
            filter:     e.target.value,
            pageNumber: 0
        });
    }

    render() {
        if (!this.state.match || !this.state.node)
            return true;
        let pageStart = this.state.pageSize * this.state.pageNumber;
        let pageEnd = pageStart + this.state.pageSize;

        let filteredItemCount = 0;

        let interfaces = this.state.interfaces.filter((x) => {
            if ( !this.state.filter ){
                return true;
            }

            if ( (new RegExp(this.state.filter, 'i').test(x.name)) ) {
                return true;
            } else if ( (new RegExp(this.state.filter, 'i').test(x.description)) ) {
                return true;
            } else if ( this.state.filter == x.interface_id ) {
                return true;
            } else {
                return false;
            }
        }).filter((x, i) => {
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
        interfaces.forEach(x => x.utilized_total_bandwith = x.utilized_bandwidth + ' / ' + x.bandwidth);
        
        const rowButtons = (data) => {
            return (
            <div>
                <Link to={`/nodes/${data.node_id}/interfaces/${data.interface_id}`} className="btn btn-default btn-xs">Edit Interface</Link>
            </div>
            );
        }

        let columns = [
            {name: '', style: {verticalAlign: 'middle', fontSize: '.6em'}, render: (intf) => <span title={intf.operational_state}>{(intf.operational_state === "up") ? "🟢" : "🔴"}</span>},
            {name: 'ID', key: 'interface_id'},
            {name: 'Name', key: 'name'},
            {name: 'Description', key: 'description'},
            {name: 'Reserved Bandwidth (Mps)', key: 'utilized_total_bandwith'},
            {name: 'Cloud Interconnect Type', key: 'cloud_interconnect_type'},
            {name: 'Role', key: 'role'},
            {name: '', render: rowButtons, style: {textAlign: 'right'}}
        ];

        return (
            <div>
                <div>
                    <p className="title"><b>Node Interfaces</b></p>
                    <p className="subtitle">Edit Node Interfaces</p>
                </div>
                <br />
                <form id="user_search_div" className="form-inline">
                    <div className="form-group">
                        <div className="input-group">
                            <span className="input-group-addon" id="icon"><span className="glyphicon glyphicon-search" aria-hidden="true"></span></span>
                            <input type="text" className="form-control" id="user_search" placeholder="Filter Interfaces" aria-describedby="icon" onChange={(e) => this.filterInterfaces(e)} />
                        </div>
                    </div>
                </form>
                <Table columns={columns} rows={interfaces} />
                <center>
                    <PageSelector pageNumber={this.state.pageNumber} pageSize={this.state.pageSize} itemCount={filteredItemCount} onChange={(i) => this.setState({pageNumber: i})} />
                </center>
            </div>
        );

    }
}
Interfaces.contextType = PageContext;
export { Interfaces };