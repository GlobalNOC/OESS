import React from "react";

import { Link, withRouter } from "react-router-dom";

const adminNavBar = (props) => {
  const { location } = props;

  let links = [
    { name: 'Links',      url: '/links' },
    { name: 'Nodes',    url: '/nodes' },
    { name: 'Users',      url: '/users' },
    { name: 'Workgroups', url: '/workgroups' }
  ];

  let sideNavLinks = links.map((link, i) => {
    let classNames = '';
    if (location.pathname.startsWith(link.url)) {
      classNames = 'active';
    }
    return (
      <li key={i} role="presentation" className={classNames}>
        <Link to={link.url}>{link.name}</Link>
      </li>
    );
  });

  // TODO Remove when admin section fully migrated
  let legacyLink = (
    <li key={-1} role="presentation">
      <Link to={'/../../admin'} target="_blank">Other</Link>
    </li>
  );
  sideNavLinks.push(legacyLink);

  return (
    <ul className="nav nav-pills nav-stacked">
      { sideNavLinks }
    </ul>
  );
};

export const AdminNavBar = withRouter(adminNavBar);
