import React from 'react';

export default class UserTable extends React.Component {

    constructor(props) {
        super(props);
        this.getHeader = this.getHeader.bind(this);
        this.getRowsData = this.getRowsData.bind(this);
        this.getKeys = this.getKeys.bind(this);
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

    getRowsData() {
        var items = this.props.data;
        var keys = this.getKeys();
        return items.map((row, index) => {
            return <tr key={index}><RenderRow key={index} data={row} keys={keys} /></tr>
        })
    }

    render() {

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
            </div>

        );
    }
}

const RenderRow = (props) => {
    return props.keys.map((key, index) => {
        return <td key={key}>{props.data[key]}</td>
    })
}
