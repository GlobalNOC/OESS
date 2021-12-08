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
       
        let columns = [
            {name: 'ID', key: 'interface_id'},
            {name: 'Name', key: 'name'},
            {name: 'Description', key: 'description'},
            {name: 'Status', key: 'operational_status', key:  'operational_state'},
            {name: 'Utilized/Total Bandwidth(Mps)', key: 'utilized_total_bandwith'},
            {name: 'Cloud Interconnection Type', key: 'cloud_interconnect_type'},
            {name: 'Role', key: 'role'}
        ];

        return (
            <div>
                <div>
                    <p className="title">Interfaces</p>
                    <p className="subtitle">{this.state.node.name}</p>
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