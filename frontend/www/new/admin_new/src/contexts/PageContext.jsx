import React, { useEffect, useState } from "react";

import getCurrentUser from '../api/user_menu.jsx';


export const PageContext = React.createContext({
  user:         null,
  workgroup:    null,
  setWorkgroup: () => {},
  status:       null,
  setStatus:    () => {}
});


export const PageContextProvider = (props) => {
  const [user, setUser] = useState(null);
  const [workgroup, setWorkgroup] = useState(null);
  const [status, setStatus] = useState({type: null, message: ''});

  const selectWorkgroup = (obj) => {
    sessionStorage.data = encodeURIComponent(JSON.stringify(obj));
  };

  useEffect(() => {
    getCurrentUser().then((resp) => {
      console.log('user:', resp);

      let json = sessionStorage.getItem('data');
      let obj  = {};
      if (!json) {
        selectWorkgroup({
          username:       resp.username,
          workgroup_id:   resp.workgroups[0].workgroup_id,
          workgroup_name: resp.workgroups[0].name,
          workgroup_type: resp.workgroups[0].type
        });
      } else {
        let data = JSON.parse(decodeURIComponent(json));

        for (let i = 0; i < resp.workgroups.length; i++) {
          if (data.workgroup_id == resp.workgroups[i].workgroup_id) {
            selectWorkgroup({
              username:       resp.username,
              workgroup_id:   resp.workgroups[i].workgroup_id,
              workgroup_name: resp.workgroups[i].name,
              workgroup_type: resp.workgroups[i].type
            });
            break;
          }
        }
      }

      json = sessionStorage.getItem('data');
      let data = JSON.parse(decodeURIComponent(json));

      setWorkgroup({ name: data.workgroup_name, workgroup_id: data.workgroup_id });
      setUser(resp);
    }).catch((error) => {
      console.error(error);
    });

  }, []);

  useEffect(() => {
    if (user == null) return;

    selectWorkgroup({
      username:       user.username,
      workgroup_id:   workgroup.workgroup_id,
      workgroup_name: workgroup.name,
      workgroup_type: workgroup.type
    });
  }, [user, workgroup]);

  // Do not render page until user info is loaded from backend.
  if (user == null || workgroup == null) {
    return <div></div>;
  }

  return (
    <PageContext.Provider value={{ user, workgroup, setWorkgroup, status, setStatus }}>
      {props.children}
    </PageContext.Provider>
  );
};
