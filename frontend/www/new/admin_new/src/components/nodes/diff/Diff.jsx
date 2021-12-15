import React from 'react';


export const Diff = (props) => {
    let diffTextLines = props.text.split('\n');
    let noMargins = {'margin': '0px'};

    return (
        <pre className="container-fluid">
            {diffTextLines.map((line) => {
                let firstChar = line.substring(0, 1);
                if (firstChar === '+') {
                    return <p style={noMargins} className="mt-5 bg-success">{line}</p>;
                } else if (firstChar === '-') {
                    return <p style={noMargins} className="mt-5 bg-danger">{line}</p>;
                } else {
                    return <p style={noMargins} className="">{line}</p>;
                }
            })}
        </pre>
    );
}
