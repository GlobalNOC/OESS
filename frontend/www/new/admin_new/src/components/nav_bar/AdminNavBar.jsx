import React from "react";

import { Link } from "react-router-dom";

export const AdminNavBar = () => {
  // https://developer.mozilla.org/en-US/docs/Web/API/URL_API
  let url = new URL(document.location.href);

  let links = [
    { name: 'Devices',    url: '/devices' },
    { name: 'Links',      url: '/links' },
    { name: 'Remote',     url: '/remote' },
    { name: 'Users',      url: '/users' },
    { name: 'Workgroups', url: '/workgroups' }
  ];

  let sideNavLinks = links.map((link, i) => {
    let classNames = '';
    if (url.pathname.includes(link.url)) {
      classNames = 'active';
      link.url = '#';
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
