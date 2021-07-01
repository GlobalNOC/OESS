import React from 'react';
import getNodeDiffText from './../../api/nodes';

let noMargins = {'margin': '0px'};

export class Diff extends React.Component {
    constructor(props){
        super(props);
        this.state = {};

        if(!props.diffText && !props.nodeId){
            throw 'diffText or nodeID must be defined!';
        }
    }

    async componentDidMount(){
        if(!this.diffText){
            let diffText = await getNodeDiffText(this.props.nodeId);
            this.setState({diffText});
        }else{
            this.setState({diffText: this.props.diffText});
        }
    }

    render(){
        let diffTextLines = [];
        if(this.state.diffText)
            diffTextLines = this.state.diffText.split('\n');

        return (
            <pre className="container-fluid">
                {diffTextLines.map((line) => {
                    console.log(line);
                    let firstChar = line.substring(0, 1);
                    if(firstChar === '+'){
                        return <p style={noMargins} className="mt-5 bg-success">{line}</p>;
                    }else if(firstChar === '-'){
                        return <p style={noMargins} className="mt-5 bg-danger">{line}</p>;
                    }else{
                        return <p style={noMargins} className="">{line}</p>;
                    }
                })}
            </pre>
        );
    }
}