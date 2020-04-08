import React from "react";

export const AdminNavBar = () => {
  // https://developer.mozilla.org/en-US/docs/Web/API/URL_API
  let url = new URL(document.location.href);

  let links = [
    { name: 'Devices',    url: 'devices.html' },
    { name: 'Links',      url: 'links.html' },
    { name: 'Remote',     url: 'remote.html' },
    { name: 'Users',      url: 'index.html' },
    { name: 'Workgroups', url: 'workgroups.html' }
  ];

  let sideNavLinks = links.map((link, i) => {
    let classNames = '';
    if (url.pathname.includes(link.url)) {
      classNames = 'active';
      link.url = '#';
    }
    return <li key={i} role="presentation" className={classNames}><a href={link.url}>{link.name}</a></li>;
  });

  return (
    <ul className="nav nav-pills nav-stacked">
      { sideNavLinks }
    </ul>
  );
};
