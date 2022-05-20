import React from 'react';

import { getNode } from '../../api/nodes.js';
import { getInterfaces, migrateInterface } from '../../api/interfaces.js';
import { PageContext } from "../../contexts/PageContext.jsx";
import { Link } from "react-router-dom";
import { MigrateInterfaceForm } from '../../components/interfaces/MigrateInterfaceForm.jsx';
import { BaseModal } from '../../components/generic_components/BaseModal.jsx';
import { CustomTable } from '../../components/generic_components/CustomTable.jsx';


class Interfaces extends React.Component {
    constructor(props) {
        super(props);        
        this.state = {
            node: null,
            interfaces: [],
            interface: null,
            migrateInterfaceModalVisible: false
        }
        this.migrateInterface = this.migrateInterface.bind(this);
    }

    async componentDidMount(){
        try {
            const node = await getNode(this.props.match.params['id']);            
            const interfaces = await getInterfaces(this.props.match.params['id']);
            interfaces.forEach(x => x.utilized_total_bandwith = x.utilized_bandwidth + ' / ' + x.bandwidth);

            this.setState({interfaces: interfaces, node: node});
        } catch(error) {
            this.context.setStatus({type: 'error', message: error.toString()});
        }
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
        if (!this.props.match || !this.state.node)
            return true;
        
        const rowButtons = (data) => {
            // If workgroup_id == null then management of acls or connection
            // migrations don't really make sense.
            let dropdownDisabled = (data.workgroup_id == null) ? true : false;

            return (
            <div>
                <div className="btn-group">
                    <Link to={(data.role === 'trunk') ? '#' : `/nodes/${data.node_id}/interfaces/${data.interface_id}`} className="btn btn-default btn-xs" disabled={data.role === 'trunk'}>Edit Interface</Link>
                    <button type="button" className="btn btn-default btn-xs dropdown-toggle" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false" disabled={dropdownDisabled}>
                        <span>▾</span>{/* className="caret" doesn't work idk why */}
                        <span className="sr-only">Toggle Dropdown</span>
                    </button>
                    <ul className="dropdown-menu" style={{fontSize: '12px'}}>
                        <li><Link to={`/nodes/${data.node_id}/interfaces/${data.interface_id}/acls`}>Manage ACLs</Link></li>
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

                <CustomTable columns={columns} rows={this.state.interfaces} size={15} filter={['interface_id', 'name', 'description', 'cloud_interconnect_type']} />
            </div>
        );

    }
}
Interfaces.contextType = PageContext;
export { Interfaces };
