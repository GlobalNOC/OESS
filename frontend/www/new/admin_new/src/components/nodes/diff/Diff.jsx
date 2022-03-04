import React from 'react';


export const Diff = (props) => {
    let diffTextLines = props.text.split('\n');
    let noMargins = {'margin': '0px'};

    // word-break and white-space result in lines being wrapped
    // ideally this lines would not be wrapped, but i had trouble
    // getting the highlighting to span lines longer than the
    // initial width
    return (
        <pre className="container-fluid" style={{marginBottom: '20px', wordBreak: 'break-word', whiteSpace: 'pre-wrap'}}>
            {diffTextLines.map((line) => {
                let firstChar = line.substring(0, 1);
                if (firstChar === '+') {
                    return <p style={noMargins} className="mt-5 bg-success">{line}</p>;
                } else if (firstChar === '-') {
                    return <p style={noMargins} className="mt-5 bg-danger">{line}</p>;
                } else {
                    return <p style={noMargins} className="mt-5">{line}</p>;
                }
            })}
        </pre>
    );
}
