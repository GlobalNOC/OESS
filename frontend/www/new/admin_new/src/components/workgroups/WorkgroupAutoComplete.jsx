import React, { useEffect, useState } from "react";

import { getAllWorkgroups } from "../../api/workgroup";

import { AutoComplete } from "../generic_components/AutoComplete";


export const WorkgroupAutoComplte = (props) => {
  // const [workgroupId, setWorkgroupId] = useState(props.value);
  const [workgroups, setWorkgroups] = useState([]);

  useEffect(() => {
    try {
      getAllWorkgroups().then((workgroups) => {
        console.info(workgroups);
        setWorkgroups(workgroups);
      });
    } catch (error) {
      // TODO Show error message to user? If this fails workgroups can't be loaded.
      setWorkgroups([]);
      console.error(error);
    }
  }, []);

  let suggestions = workgroups.map((wg) => {
    return {name: wg.name, value: parseInt(wg.workgroup_id)};
  });
  if (props.nullOption) {
    suggestions = [props.nullOption, ...suggestions];
  }

  return (
    <div className="input-group">
      <AutoComplete id={props.id} name={props.name} placeholder="Search by workgroup" value={props.value} onChange={props.onChange} suggestions={suggestions} style={{borderRadius: "4px 0px 0px 4px"}}/>
      <span class="input-group-addon"><span class="glyphicon glyphicon-search" aria-hidden="true"></span></span>
    </div>
  );
};
