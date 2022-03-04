import React from 'react';
import { getNode } from '../../api/nodes.js';
import { getInterfaces, migrateInterface } from '../../api/interfaces.js';
import { PageContext } from "../../contexts/PageContext.jsx";
import { PageSelector } from '../../components/generic_components/PageSelector.jsx';
import { Table } from "../../components/generic_components/Table.jsx";
import { Link } from "react-router-dom";
import { MigrateInterfaceForm } from '../../components/interfaces/MigrateInterfaceForm.jsx';
import { BaseModal } from '../../components/generic_components/BaseModal.jsx';

class Interfaces extends React.Component {
    constructor(props) {
        super(props);        
        this.state = {
            node: null,
            interfaces: [],
            pageSize: 20,
            pageNumber: 0,
            filter: '',
            match: props.match,
            interface: null,
            migrateInterfaceModalVisible: false
        }
        this.filterInterfaces = this.filterInterfaces.bind(this);
        this.migrateInterface = this.migrateInterface.bind(this);
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

    async migrateInterface(data) {
        let ok = confirm("Are you sure you wish to continue?")
        if (!ok) return;
        console.info('migrateInterface:', data);

        try {
            await migrateInterface(data.srcInterfaceId, data.dstInterfaceId);
            history.go(0); // refresh
        } catch(error) {
            this.setState({migrateInterfaceModalVisible: false});
            this.context.setStatus({type: 'error', message: error.toString()});
        }
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
            // If workgroup_id == null then management of acls or connection
            // migrations don't really make sense.
            let dropdownDisabled = (data.workgroup_id == null) ? true : false;

            return (
            <div>
                <div className="btn-group">
                    <Link to={`/nodes/${data.node_id}/interfaces/${data.interface_id}`} className="btn btn-default btn-xs">Edit Interface</Link>
                    <button type="button" className="btn btn-default btn-xs dropdown-toggle" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false" disabled={dropdownDisabled}>
                        <span>▾</span>{/* className="caret" doesn't work idk why */}
                        <span className="sr-only">Toggle Dropdown</span>
                    </button>
                    <ul className="dropdown-menu" style={{fontSize: '12px'}}>
                    <li><Link to={`/nodes/${data.node_id}/interfaces/${data.interface_id}/acls`}>Manage ACLs</Link></li>
                        <li role="separator" className="divider" style={{margin: '4px 0'}}></li>
                        <li><a href="#" onClick={() => this.setState({migrateInterfaceModalVisible: true, interface: data})}>Migrate Interface</a></li>
                    </ul>
                </div>
            </div>
            );
        }

        let columns = [
            {name: '', style: {verticalAlign: 'middle', fontSize: '.6em'}, render: (intf) => <span title={intf.operational_state}>{(intf.operational_state === "up") ? "🟢" : "🔴"}</span>},
            {name: 'ID', key: 'interface_id'},
            {name: 'Name', key: 'name'},
            {name: 'Description', key: 'description'},
            {name: 'Reserved Bandwidth (Mps)', key: 'utilized_total_bandwith'},
            {name: 'Interconnect Type', key: 'cloud_interconnect_type'},
            {name: 'Role', key: 'role'},
            {name: '', render: rowButtons, style: {textAlign: 'right'}}
        ];

        let interfaceComp = null;
        let interfaceCompHdr = '';
        if (this.state.interface) {
            interfaceComp = (
                <MigrateInterfaceForm interfaceId={this.state.interface.interface_id} onCancel={() => this.setState({migrateInterfaceModalVisible: false})} onSubmit={this.migrateInterface} />
            );
            interfaceCompHdr = `Migrate Interface: ${this.state.interface.node} - ${this.state.interface.name}`;
        }

        return (
            <div>
                <BaseModal visible={this.state.migrateInterfaceModalVisible} header={interfaceCompHdr} modalID="migrate-interface-modal" onClose={() => this.setState({migrateInterfaceModalVisible: false})}>
                    {interfaceComp}
                </BaseModal>

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