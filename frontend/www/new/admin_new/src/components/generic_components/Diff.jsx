import React from 'react';
import {getNodeDiffText} from './../../api/nodes';

let noMargins = {'margin': '0px'};

export class Diff extends React.Component {
    constructor(props){
        super(props);
        this.state = {errorMsg: null, loading: true};

        if(!props.diffText && !props.nodeId){
            throw 'diffText or nodeId must be defined!';
        }
    }

    async componentDidMount(){
        if(!this.props.diffText){
            try{
                let diffText = await getDiffText(this.props.nodeId);            
                this.setState({diffText: diffText, loading: false});
            }catch(error){
                console.log(error);
                this.setState({errorMsg: error.toString(), loading: false});
            }
        }else{
            this.setState({diffText: this.props.diffText, loading: false});
        }
    }

    render(){
        let diffTextLines;
        if(this.state.diffText)
            diffTextLines = this.state.diffText.split('\n');

        if(this.state.errorMsg){
            return (
                <pre>
                    <p className="text-danger">Error Getting Diff: {this.state.errorMsg}</p>
                </pre>
            );
        }else if(this.state.loading){
          return (
              <div role="status">
                  <span>Loading...</span>
              </div>
          );
        }else{

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
}