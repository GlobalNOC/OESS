import React from "react";

import { Link, withRouter } from "react-router-dom";

const adminNavBar = (props) => {
  const { location } = props;

  let links = [
    // { name: 'Devices',    url: '/devices' },
    // { name: 'Links',      url: '/links' },
    // { name: 'Remote',     url: '/remote' },
    { name: 'Users',      url: '/users' },
    { name: 'Workgroups', url: '/workgroups' }
  ];

  let sideNavLinks = links.map((link, i) => {
    let classNames = '';
    if (location.pathname.includes(link.url)) {
      classNames = 'active';
    }
    return (
      <li key={i} role="presentation" className={classNames}>
        <Link to={link.url}>{link.name}</Link>
      </li>
    );
  });

  return (
    <ul className="nav nav-pills nav-stacked">
      { sideNavLinks }
    </ul>
  );
};

export const AdminNavBar = withRouter(adminNavBar);
