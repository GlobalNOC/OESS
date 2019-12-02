import React from 'react';
import ModalTemplate from './ModalTemplate.jsx';

export default class TableTemplate extends React.Component {

    constructor(props) {
        super(props);
        this.getHeader = this.getHeader.bind(this);
        this.getRowsData = this.getRowsData.bind(this);
        this.getKeys = this.getKeys.bind(this);
	this.state={
		isVisible : false,
		rowdata : {}
	}
    }

    getKeys() {
        return Object.keys(this.props.data[0]);
    }

    getHeader() {
        var keys = this.getKeys();
        return keys.map((key, index) => {
            return <th scope="col" key={key}>{key}</th>
        })
    }
    displaypopup(currComponent, row){
	console.log("This is popup"+JSON.stringify(row));
	var rowdata = row;
	currComponent.setState({isVisible:true, rowdata:rowdata});
   }
    getRowsData() {
        var items = this.props.data;
        var keys = this.getKeys();
	var currComponent = this;
        return items.map((row, index) => {
            return <tr id={index} key={index} onClick={this.displaypopup.bind(this,currComponent,row)}><RenderRow key={index} data={row} keys={keys} /></tr>
        })
    }

    render() {
	console.log(this.state);
        return (
            <div>
                <table className="table table-striped">
                    <thead>
                        <tr>{this.getHeader()}</tr>
                    </thead>
                    <tbody>
                        {this.getRowsData()}
                    </tbody>
                </table>
	<ModalTemplate isVisible={[this.state.isVisible, this.state.rowdata]} />
        </div>
        );
    }
}

const RenderRow = (props) => {
    return props.keys.map((key, index) => {
        return <td key={key}>{props.data[key]}</td>
    })
}
