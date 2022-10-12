import React from 'react';


//
// <Table columns={columns} rows={workgroups} />
//
// columns: [ { name: 'required', key: 'optional', render: 'optional', style: 'optional' } ]
//
const Table = (props) => {
  let columns = props.columns.map((column, ci) => {
    return <th key={ci}>{ column.name }</th>;
  });

  let rows = props.rows.map((row, ri) => {
    let cells = props.columns.map((column, ci) => {
      if ('key' in column) {
        return <td key={ci} style={column.style}>{ row[column.key] }</td>;
      }
      else if ('render' in column) {
        return <td key={ci} style={column.style}>{ column.render(row) }</td>;
      }
      else {
        return <td key={ci} style={column.style}>ERROR</td>;
      }
    });
    return <tr key={ri}>{ cells }</tr>;
  });

  return (
    <table className="table table-striped" style={{marginBottom: '0px'}}>
      <thead>
        <tr>
          {columns}
        </tr>
      </thead>
      <tbody>
        {rows}
      </tbody>
    </table>
  );
};

export { Table };
