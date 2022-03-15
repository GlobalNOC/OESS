import React, { useContext } from "react";
import { useState } from "react";

import { Table } from "./Table";


export const TableContext = React.createContext({
    page:      0,
    setPage:   () => {},
    items:     0,
    filter:    '',
    setFilter: () => {},
});


const TablePageSelector = (props) => {
    const { items, page, setPage } = useContext(TableContext);

    let pages = [];
    for (let i = 0; i < Math.ceil(items / props.pageSize); i++) {
        let isActive = (page == i) ? 'active' : '';
        // A position of static ensures that page number appears under modals'
        // backdrop
        pages.push( <li className={isActive} key={i}><a style={{position: 'static'}} href="#" onClick={() => setPage(i)}>{i+1}</a></li> );
    }

    return (
        <nav aria-label="Page navigation">
            <ul className="pagination">
            {pages}
            </ul>
        </nav>
    );
};


const TableFilter = (props) => {
    const { setFilter, setPage } = useContext(TableContext);

    const onChangeHandler = (e) => {
        setPage(0);
        setFilter(e.target.value);
    };

    return (
        <form id="table_search_div" className="form-inline">
            <div className="form-group">
                <div className="input-group">
                    <span className="input-group-addon" id="icon"><span className="glyphicon glyphicon-search" aria-hidden="true"></span></span>
                    <input type="text" className="form-control" id="table_search" placeholder="Search" aria-describedby="icon" onChange={onChangeHandler} />
                </div>
            </div>
        </form>
    );
}


export const CustomTable = (props) => {
    const [page, setPage] = useState(0);
    const [filter, setFilter] = useState('');

    const { columns, rows, size } = props;

    let start = size * page; // replace 1 with page number
    let end   = start + size;
    let items = 0;

    let filteredRows = rows.filter((d) => {
        if (!filter || !props.filter || !Array.isArray(props.filter)) {
            return true;
        }

        for (let i = 0; i < props.filter.length; i++) {
            if ( (new RegExp(filter, 'i').test(d[props.filter[i]])) ) {
              return true;
            }
        }
        return false;
    }).filter((d, i) => {
        // Any items not filtered by search are displayed and the count
        // of these are used to determine the number of table pages to
        // show.
        items += 1;

        if (i >= start && i < end) {
            return true;
        } else {
            return false;
        }
    });

    let menuItems = [];
    React.Children.forEach(props.children, (child) => {
        if (child.type.name == "TableMenuItem") {
            menuItems.push(child);
        }
    });

    let tableFilter = null;
    if (props.filter && Array.isArray(props.filter)) {
        tableFilter = <TableFilter />
    }

    return (
        <TableContext.Provider value={{page, setPage, items, setFilter}}>
            <div style={{display: "flex", flexDirection: "row", columnGap: ".75em"}}>
                {tableFilter}
                {menuItems}
            </div>
            <Table columns={columns} rows={filteredRows} />
            <center>
                <TablePageSelector pageNumber={page} pageSize={size} />
            </center>
        </TableContext.Provider>
    );
};


const TableMenuItem = (props) => {
    return (
        <div style={{marginBottom: '14px'}}>
        {props.children}
        </div>
    );
}
CustomTable.MenuItem = TableMenuItem;
